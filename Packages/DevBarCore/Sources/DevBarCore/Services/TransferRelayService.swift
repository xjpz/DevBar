import CryptoKit
import Foundation
import Security

public struct TransferRelayClientInfo: Codable, Sendable, Equatable {
    public let platform: String
    public let appVersion: String?
    public let buildNumber: String?
    public let deviceName: String?
    public let locale: String?
    public let timezone: String?

    public init(
        platform: String,
        appVersion: String? = nil,
        buildNumber: String? = nil,
        deviceName: String? = nil,
        locale: String? = nil,
        timezone: String? = nil
    ) {
        self.platform = platform
        self.appVersion = appVersion
        self.buildNumber = buildNumber
        self.deviceName = deviceName
        self.locale = locale
        self.timezone = timezone
    }

    enum CodingKeys: String, CodingKey {
        case platform
        case appVersion = "app_version"
        case buildNumber = "build_number"
        case deviceName = "device_name"
        case locale
        case timezone
    }
}

public struct TransferRelayQRCode: Sendable, Equatable {
    public let payload: TransferPayload
    public let url: URL
    public let mode: TransferQRCodeMode
}

public enum TransferQRCodeMode: Sendable, Equatable {
    case direct
    case relay
}

public final class TransferRelayService: Sendable {
    public static let shared = TransferRelayService()

    private let baseURL: URL
    private let session: URLSession

    public init(
        baseURL: URL = URL(string: DevBarCoreConstants.TransferRelay.baseURL)!,
        session: URLSession = .shared
    ) {
        self.baseURL = baseURL
        self.session = session
    }

    public func makeTransferQRCode(
        for payload: TransferPayload,
        client: TransferRelayClientInfo
    ) async throws -> TransferRelayQRCode {
        let directURL = try TransferPayloadCodec.makeURL(for: payload)
        if directURL.absoluteString.count <= DevBarCoreConstants.TransferRelay.directQRCodeLengthThreshold {
            return TransferRelayQRCode(payload: payload, url: directURL, mode: .direct)
        }

        let encrypted = try TransferPayloadRelayCrypto.encrypt(payload)
        let request = CreateTransferRequest(
            schemaVersion: 2,
            encryption: "AES-256-GCM",
            ciphertext: encrypted.ciphertext,
            nonce: encrypted.nonce,
            tag: encrypted.tag,
            readTokenHash: TransferPayloadRelayCrypto.sha256HashString(for: encrypted.readToken),
            expiresIn: 300,
            client: client,
            metadata: TransferMetadata(
                providerCount: payload.providers.count,
                providers: payload.providers.map { $0.provider.rawValue }
            )
        )

        let response: CreateTransferResponse = try await sendJSON(
            path: DevBarCoreConstants.TransferRelay.transfersPath,
            method: "POST",
            body: request,
            bearerToken: nil
        )

        let url = try TransferPayloadCodec.makeRelayURL(
            transferID: response.transferID,
            readToken: encrypted.readToken,
            encryptionKey: encrypted.encryptionKey
        )
        return TransferRelayQRCode(payload: payload, url: url, mode: .relay)
    }

    public func resolveRelayTransfer(from url: URL) async throws -> TransferPayload {
        let descriptor = try TransferPayloadCodec.parseRelayURL(url)
        let response: FetchTransferResponse = try await sendJSON(
            path: "\(DevBarCoreConstants.TransferRelay.transfersPath)/\(descriptor.transferID)",
            method: "GET",
            body: Optional<EmptyBody>.none,
            bearerToken: descriptor.readToken
        )

        return try TransferPayloadRelayCrypto.decrypt(
            ciphertext: response.ciphertext,
            nonce: response.nonce,
            tag: response.tag,
            encryptionKey: descriptor.encryptionKey
        )
    }

    public func deleteRelayTransfer(from url: URL) async throws {
        let descriptor = try TransferPayloadCodec.parseRelayURL(url)
        let _: DeleteTransferResponse = try await sendJSON(
            path: "\(DevBarCoreConstants.TransferRelay.transfersPath)/\(descriptor.transferID)",
            method: "DELETE",
            body: Optional<EmptyBody>.none,
            bearerToken: descriptor.readToken
        )
    }

    private func sendJSON<RequestBody: Encodable, ResponseBody: Decodable>(
        path: String,
        method: String,
        body: RequestBody?,
        bearerToken: String?
    ) async throws -> ResponseBody {
        guard let endpoint = URL(string: path, relativeTo: baseURL)?.absoluteURL else {
            throw TransferPayloadError.invalidURL
        }
        var request = URLRequest(url: endpoint)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let bearerToken {
            request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            let encoder = JSONEncoder()
            request.httpBody = try encoder.encode(body)
        }

        print("[DevBar:TransferRelay] \(method) \(endpoint.absoluteString)")
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            print("[DevBar:TransferRelay] \(method) no HTTP response")
            throw TransferPayloadError.invalidRelayResponse
        }
        print("[DevBar:TransferRelay] \(method) status=\(httpResponse.statusCode) bytes=\(data.count) keys=\(Self.responseKeysDescription(from: data))")

        guard 200..<300 ~= httpResponse.statusCode else {
            if let errorResponse = try? JSONDecoder().decode(TransferRelayErrorResponse.self, from: data) {
                print("[DevBar:TransferRelay] \(method) server error code=\(errorResponse.code)")
                throw TransferPayloadError.relayServerError(errorResponse.code)
            }
            throw TransferPayloadError.relayHTTPError(httpResponse.statusCode)
        }

        if let envelopeError = try? JSONDecoder().decode(TransferRelayErrorResponse.self, from: data),
           envelopeError.isFailure {
            print("[DevBar:TransferRelay] \(method) server error code=\(envelopeError.code)")
            throw TransferPayloadError.relayServerError(envelopeError.code)
        }

        if ResponseBody.self == EmptyResponse.self {
            return EmptyResponse() as! ResponseBody
        }

        do {
            return try JSONDecoder().decode(ResponseBody.self, from: data)
        } catch {
            print("[DevBar:TransferRelay] \(method) decode failed: \(error)")
            print("[DevBar:TransferRelay] \(method) response preview=\(Self.safeResponsePreview(from: data))")
            throw TransferPayloadError.invalidRelayResponse
        }
    }

    private static func responseKeysDescription(from data: Data) -> String {
        guard let object = try? JSONSerialization.jsonObject(with: data) else {
            return "non-json"
        }

        if let dict = object as? [String: Any] {
            return dict.keys.sorted().joined(separator: ",")
        }

        return String(describing: type(of: object))
    }

    private static func safeResponsePreview(from data: Data) -> String {
        guard let object = try? JSONSerialization.jsonObject(with: data) else {
            return String(decoding: data.prefix(300), as: UTF8.self)
        }

        let redacted = redactSensitiveValues(in: object)
        guard let redactedData = try? JSONSerialization.data(withJSONObject: redacted, options: [.sortedKeys]),
              let text = String(data: redactedData, encoding: .utf8) else {
            return "unprintable-json"
        }
        return String(text.prefix(600))
    }

    private static func redactSensitiveValues(in value: Any) -> Any {
        if let dict = value as? [String: Any] {
            return Dictionary<String, Any>(uniqueKeysWithValues: dict.map { key, value -> (String, Any) in
                let lowercasedKey = key.lowercased()
                if lowercasedKey.contains("cipher") ||
                    lowercasedKey.contains("token") ||
                    lowercasedKey == "tag" ||
                    lowercasedKey == "nonce" ||
                    lowercasedKey.contains("key") {
                    return (key, "<redacted>")
                }
                return (key, redactSensitiveValues(in: value))
            })
        }

        if let array = value as? [Any] {
            return array.map(redactSensitiveValues(in:))
        }

        return value
    }
}

struct TransferRelayDescriptor: Sendable, Equatable {
    let transferID: String
    let readToken: String
    let encryptionKey: String
}

private enum TransferPayloadRelayCrypto {
    struct EncryptedPayload {
        let ciphertext: String
        let nonce: String
        let tag: String
        let readToken: String
        let encryptionKey: String
    }

    static func encrypt(_ payload: TransferPayload) throws -> EncryptedPayload {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(payload)
        let keyData = randomData(byteCount: 32)
        let key = SymmetricKey(data: keyData)
        let sealedBox = try AES.GCM.seal(data, using: key)
        let readToken = "rt_\(randomData(byteCount: 32).base64URLEncodedString())"

        return EncryptedPayload(
            ciphertext: sealedBox.ciphertext.base64URLEncodedString(),
            nonce: Data(sealedBox.nonce).base64URLEncodedString(),
            tag: sealedBox.tag.base64URLEncodedString(),
            readToken: readToken,
            encryptionKey: "ek_\(keyData.base64URLEncodedString())"
        )
    }

    static func decrypt(
        ciphertext: String,
        nonce: String,
        tag: String,
        encryptionKey: String
    ) throws -> TransferPayload {
        guard let keyData = Data(base64URLEncoded: stripPrefix("ek_", from: encryptionKey)),
              let ciphertextData = Data(base64URLEncoded: ciphertext),
              let nonceData = Data(base64URLEncoded: nonce),
              let tagData = Data(base64URLEncoded: tag) else {
            throw TransferPayloadError.invalidRelayPayload
        }

        let sealedBox = try AES.GCM.SealedBox(
            nonce: AES.GCM.Nonce(data: nonceData),
            ciphertext: ciphertextData,
            tag: tagData
        )
        let data = try AES.GCM.open(sealedBox, using: SymmetricKey(data: keyData))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let payload = try decoder.decode(TransferPayload.self, from: data)

        guard [1, 2].contains(payload.schemaVersion) else {
            throw TransferPayloadError.unsupportedSchemaVersion(payload.schemaVersion)
        }

        guard !payload.isExpired else {
            throw TransferPayloadError.expired
        }

        return payload
    }

    static func sha256HashString(for token: String) -> String {
        let digest = SHA256.hash(data: Data(token.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return "sha256:\(hex)"
    }

    private static func randomData(byteCount: Int) -> Data {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes)
    }

    private static func stripPrefix(_ prefix: String, from value: String) -> String {
        value.hasPrefix(prefix) ? String(value.dropFirst(prefix.count)) : value
    }
}

private struct CreateTransferRequest: Encodable {
    let schemaVersion: Int
    let encryption: String
    let ciphertext: String
    let nonce: String
    let tag: String
    let readTokenHash: String
    let expiresIn: Int
    let client: TransferRelayClientInfo
    let metadata: TransferMetadata

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case encryption
        case ciphertext
        case nonce
        case tag
        case readTokenHash = "read_token_hash"
        case expiresIn = "expires_in"
        case client
        case metadata
    }
}

private struct TransferMetadata: Codable {
    let providerCount: Int
    let providers: [String]

    enum CodingKeys: String, CodingKey {
        case providerCount = "provider_count"
        case providers
    }
}

private struct CreateTransferResponse: Decodable {
    let transferID: String

    enum CodingKeys: String, CodingKey {
        case transferID = "transfer_id"
        case id
        case data
        case result
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let transferID = try container.decodeIfPresent(String.self, forKey: .transferID) ??
            container.decodeIfPresent(String.self, forKey: .id) {
            self.transferID = transferID
            return
        }

        if let nested = try container.decodeIfPresent(CreateTransferResponse.self, forKey: .data) ??
            container.decodeIfPresent(CreateTransferResponse.self, forKey: .result) {
            self.transferID = nested.transferID
            return
        }

        throw DecodingError.keyNotFound(
            CodingKeys.transferID,
            DecodingError.Context(
                codingPath: decoder.codingPath,
                debugDescription: "Missing transfer_id or id"
            )
        )
    }
}

private struct FetchTransferResponse: Decodable {
    let ciphertext: String
    let nonce: String
    let tag: String

    enum CodingKeys: String, CodingKey {
        case ciphertext
        case cipherText
        case encryptedData = "encrypted_data"
        case encryptedPayload = "encrypted_payload"
        case payload
        case sealedBox = "sealed_box"
        case nonce
        case iv
        case tag
        case authTag = "auth_tag"
        case data
        case result
        case transfer
        case record
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let ciphertext = try container.decodeFirstString(forKeys: [
            .ciphertext,
            .cipherText,
            .encryptedData,
            .encryptedPayload,
            .payload,
        ])
        let nonce = try container.decodeFirstString(forKeys: [.nonce, .iv])
        let tag = try container.decodeFirstString(forKeys: [.tag, .authTag])

        if let ciphertext, let nonce, let tag {
            self.ciphertext = ciphertext
            self.nonce = nonce
            self.tag = tag
            return
        }

        if let nested = try container.decodeIfPresent(FetchTransferResponse.self, forKey: .data) ??
            container.decodeIfPresent(FetchTransferResponse.self, forKey: .result) ??
            container.decodeIfPresent(FetchTransferResponse.self, forKey: .transfer) ??
            container.decodeIfPresent(FetchTransferResponse.self, forKey: .record) {
            self = nested
            return
        }

        throw DecodingError.keyNotFound(
            CodingKeys.ciphertext,
            DecodingError.Context(
                codingPath: decoder.codingPath,
                debugDescription: "Missing ciphertext, nonce, or tag"
            )
        )
    }
}

private extension KeyedDecodingContainer {
    func decodeFirstString(forKeys keys: [Key]) throws -> String? {
        for key in keys {
            if let value = try decodeIfPresent(String.self, forKey: key), !value.isEmpty {
                return value
            }
        }
        return nil
    }
}

private struct DeleteTransferResponse: Decodable {
    let deleted: Bool?

    enum CodingKeys: String, CodingKey {
        case deleted
        case data
        case result
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.deleted = try container.decodeIfPresent(Bool.self, forKey: .deleted) ??
            container.decodeIfPresent(DeleteTransferResponse.self, forKey: .data)?.deleted ??
            container.decodeIfPresent(DeleteTransferResponse.self, forKey: .result)?.deleted
    }
}

private struct TransferRelayErrorResponse: Decodable {
    struct RelayError: Decodable {
        let code: String
        let message: String?
    }

    let success: Bool?
    let numericCode: Int?
    let message: String?
    let error: RelayError?

    var isFailure: Bool {
        if success == false { return true }
        return error != nil
    }

    var code: String {
        if let error {
            return error.code
        }
        if let message, !message.isEmpty {
            return message
        }
        if let numericCode {
            return String(numericCode)
        }
        return "unknown_error"
    }

    enum CodingKeys: String, CodingKey {
        case success
        case numericCode = "code"
        case message = "msg"
        case error
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        success = try container.decodeIfPresent(Bool.self, forKey: .success)
        numericCode = try? container.decodeIfPresent(Int.self, forKey: .numericCode)
        message = try container.decodeIfPresent(String.self, forKey: .message)
        error = try container.decodeIfPresent(RelayError.self, forKey: .error)
    }
}

private struct EmptyBody: Encodable {}
private struct EmptyResponse: Decodable {
    init() {}
}
