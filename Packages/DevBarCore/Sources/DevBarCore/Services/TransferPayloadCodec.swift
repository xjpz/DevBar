import Foundation

public enum TransferPayloadCodec {
    public static let scheme = "devbar"
    public static let host = "transfer"
    public static let relayPath = "/relay"
    public static let payloadQueryItemName = "payload"
    public static let transferIDQueryItemName = "id"
    public static let readTokenQueryItemName = "token"
    public static let encryptionKeyFragmentItemName = "key"

    public static func makeURL(for payload: TransferPayload) throws -> URL {
        let encodedPayload = try encodePayloadString(for: payload)

        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.queryItems = [
            URLQueryItem(name: payloadQueryItemName, value: encodedPayload),
        ]

        guard let url = components.url else {
            throw TransferPayloadError.invalidURL
        }

        return url
    }

    public static func decode(from rawValue: String) throws -> TransferPayload {
        guard let url = URL(string: rawValue) else {
            throw TransferPayloadError.invalidURL
        }
        return try decode(from: url)
    }

    public static func decodeResolvingRelay(from rawValue: String) async throws -> TransferPayload {
        guard let url = URL(string: rawValue) else {
            throw TransferPayloadError.invalidURL
        }
        return try await decodeResolvingRelay(from: url)
    }

    public static func isRelayTransferURL(_ rawValue: String) -> Bool {
        guard let url = URL(string: rawValue) else { return false }
        return isRelayURL(url)
    }

    public static func decodeResolvingRelay(from url: URL) async throws -> TransferPayload {
        if isRelayURL(url) {
            return try await TransferRelayService.shared.resolveRelayTransfer(from: url)
        }
        return try decode(from: url)
    }

    public static func decode(from url: URL) throws -> TransferPayload {
        guard url.scheme?.lowercased() == scheme,
              url.host?.lowercased() == host else {
            throw TransferPayloadError.unsupportedScheme
        }

        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let payloadValue = components.queryItems?.first(where: { $0.name == payloadQueryItemName })?.value,
              let encodedData = Data(base64URLEncoded: payloadValue) else {
            throw TransferPayloadError.missingPayload
        }

        let jsonData = try decompress(encodedData)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let payload = try decoder.decode(TransferPayload.self, from: jsonData)

        guard payload.schemaVersion == 1 else {
            throw TransferPayloadError.unsupportedSchemaVersion(payload.schemaVersion)
        }

        guard !payload.isExpired else {
            throw TransferPayloadError.expired
        }

        return payload
    }

    public static func makeRelayURL(
        transferID: String,
        readToken: String,
        encryptionKey: String
    ) throws -> URL {
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.path = relayPath
        components.queryItems = [
            URLQueryItem(name: transferIDQueryItemName, value: transferID),
            URLQueryItem(name: readTokenQueryItemName, value: readToken),
        ]
        components.fragment = "\(encryptionKeyFragmentItemName)=\(encryptionKey)"

        guard let url = components.url else {
            throw TransferPayloadError.invalidURL
        }

        return url
    }

    static func parseRelayURL(_ url: URL) throws -> TransferRelayDescriptor {
        guard isRelayURL(url),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems else {
            throw TransferPayloadError.invalidURL
        }

        guard let transferID = queryItems.first(where: { $0.name == transferIDQueryItemName })?.value,
              !transferID.isEmpty,
              let readToken = queryItems.first(where: { $0.name == readTokenQueryItemName })?.value,
              !readToken.isEmpty,
              let encryptionKey = fragmentValue(named: encryptionKeyFragmentItemName, in: components.fragment),
              !encryptionKey.isEmpty else {
            throw TransferPayloadError.missingRelayParameters
        }

        return TransferRelayDescriptor(
            transferID: transferID,
            readToken: readToken,
            encryptionKey: encryptionKey
        )
    }

    private static func isRelayURL(_ url: URL) -> Bool {
        url.scheme?.lowercased() == scheme &&
            url.host?.lowercased() == host &&
            url.path == relayPath
    }

    private static func encodePayloadString(for payload: TransferPayload) throws -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(payload)
        let compressedData = try compress(data)
        return compressedData.base64URLEncodedString()
    }

    private static func compress(_ data: Data) throws -> Data {
        #if canImport(Foundation)
        do {
            return try (data as NSData).compressed(using: .zlib) as Data
        } catch {
            throw TransferPayloadError.compressionFailed
        }
        #else
        return data
        #endif
    }

    private static func decompress(_ data: Data) throws -> Data {
        #if canImport(Foundation)
        do {
            return try (data as NSData).decompressed(using: .zlib) as Data
        } catch {
            throw TransferPayloadError.decompressionFailed
        }
        #else
        return data
        #endif
    }

    private static func fragmentValue(named name: String, in fragment: String?) -> String? {
        guard let fragment else { return nil }
        return fragment
            .split(separator: "&")
            .compactMap { pair -> (String, String)? in
                let parts = pair.split(separator: "=", maxSplits: 1)
                guard parts.count == 2 else { return nil }
                let key = String(parts[0]).removingPercentEncoding ?? String(parts[0])
                let value = String(parts[1]).removingPercentEncoding ?? String(parts[1])
                return (key, value)
            }
            .first(where: { $0.0 == name })?
            .1
    }
}

public enum TransferPayloadError: LocalizedError, Equatable {
    case invalidURL
    case unsupportedScheme
    case missingPayload
    case expired
    case unsupportedSchemaVersion(Int)
    case compressionFailed
    case decompressionFailed
    case missingRelayParameters
    case invalidRelayPayload
    case invalidRelayResponse
    case relayHTTPError(Int)
    case relayServerError(String)

    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "二维码内容无效"
        case .unsupportedScheme:
            return "不是 DevBar 配置二维码"
        case .missingPayload:
            return "二维码中缺少配置内容"
        case .expired:
            return "二维码已过期，请在 Mac 上重新生成"
        case let .unsupportedSchemaVersion(version):
            return "暂不支持该配置版本：\(version)"
        case .compressionFailed:
            return "生成二维码数据失败"
        case .decompressionFailed:
            return "解析二维码数据失败"
        case .missingRelayParameters:
            return "中继二维码缺少必要参数"
        case .invalidRelayPayload:
            return "中继二维码内容无效"
        case .invalidRelayResponse:
            return "中继服务响应无效"
        case let .relayHTTPError(statusCode):
            return "中继服务请求失败：\(statusCode)"
        case let .relayServerError(code):
            return "中继服务返回错误：\(code)"
        }
    }
}
