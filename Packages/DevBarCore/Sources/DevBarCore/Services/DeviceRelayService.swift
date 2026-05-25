import Foundation

public enum DeviceRelayPairQRCodeCodec {
    public static func encode(_ payload: DeviceRelayPairQRCodePayload) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(payload)
        guard let text = String(data: data, encoding: .utf8) else {
            throw DeviceRelayError.invalidQRCode
        }
        return text
    }

    public static func decode(_ rawValue: String) throws -> DeviceRelayPairQRCodePayload {
        guard let data = rawValue.data(using: .utf8) else {
            throw DeviceRelayError.invalidQRCode
        }
        do {
            return try JSONDecoder().decode(DeviceRelayPairQRCodePayload.self, from: data)
        } catch {
            throw DeviceRelayError.invalidQRCode
        }
    }

    public static func canDecode(_ rawValue: String) -> Bool {
        (try? decode(rawValue)) != nil
    }
}

public enum DeviceRelayMessageCodec {
    public static func encode(_ message: DeviceRelayMessage) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(message)
        guard let text = String(data: data, encoding: .utf8) else {
            throw DeviceRelayError.invalidRelayResponse
        }
        return text
    }

    public static func decode(_ rawValue: String) throws -> DeviceRelayMessage {
        guard let data = rawValue.data(using: .utf8) else {
            throw DeviceRelayError.invalidRelayResponse
        }
        return try decode(data)
    }

    public static func decode(_ data: Data) throws -> DeviceRelayMessage {
        try JSONDecoder().decode(DeviceRelayMessage.self, from: data)
    }
}

extension DeviceRelayMessage {
    private enum CodingKeys: String, CodingKey {
        case type
        case requestId
        case fromDeviceId
        case targetDeviceId
        case timestamp
        case payload
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.type = try container.decode(DeviceRelayMessageType.self, forKey: .type)
        self.requestId = try container.decodeIfPresent(String.self, forKey: .requestId)
        self.fromDeviceId = try container.decodeIfPresent(String.self, forKey: .fromDeviceId)
        self.targetDeviceId = try container.decodeIfPresent(String.self, forKey: .targetDeviceId)
        self.timestamp = try container.decodeIfPresent(Int64.self, forKey: .timestamp) ??
            Int64(Date().timeIntervalSince1970 * 1000)
        self.payload = try container.decodeIfPresent(DeviceRelayStringPayload.self, forKey: .payload)?.values ?? [:]
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        try container.encodeIfPresent(requestId, forKey: .requestId)
        try container.encodeIfPresent(fromDeviceId, forKey: .fromDeviceId)
        try container.encodeIfPresent(targetDeviceId, forKey: .targetDeviceId)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encode(payload, forKey: .payload)
    }
}

private struct DeviceRelayStringPayload: Decodable {
    let values: [String: String]

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicCodingKey.self)
        var values: [String: String] = [:]
        for key in container.allKeys {
            if let string = try? container.decode(String.self, forKey: key) {
                values[key.stringValue] = string
            } else if let int = try? container.decode(Int64.self, forKey: key) {
                values[key.stringValue] = String(int)
            } else if let double = try? container.decode(Double.self, forKey: key) {
                values[key.stringValue] = String(double)
            } else if let bool = try? container.decode(Bool.self, forKey: key) {
                values[key.stringValue] = String(bool)
            }
        }
        self.values = values
    }
}

private struct DynamicCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }

    init?(intValue: Int) {
        self.stringValue = String(intValue)
        self.intValue = intValue
    }
}

public final class DeviceRelayService: Sendable {
    public static let shared = DeviceRelayService()

    private let baseURL: URL
    private let session: URLSession

    public init(
        baseURL: URL = URL(string: DevBarCoreConstants.DeviceRelay.baseURL)!,
        session: URLSession = .shared
    ) {
        self.baseURL = baseURL
        self.session = session
    }

    public func registerDevice(_ registration: DeviceRelayRegistration) async throws -> DeviceRelayRegistrationResponse {
        try await sendJSON(
            path: DevBarCoreConstants.DeviceRelay.registerPath,
            method: "POST",
            body: registration,
            bearerToken: nil
        )
    }

    public func fetchPeers(deviceToken: String) async throws -> [DeviceRelayDevice] {
        let response: DeviceRelayPeersEnvelope = try await sendJSON(
            path: DevBarCoreConstants.DeviceRelay.peersPath,
            method: "GET",
            body: Optional<EmptyBody>.none,
            bearerToken: deviceToken
        )
        return response.devices
    }

    public func createPairCode(macDeviceId: String, deviceToken: String) async throws -> DeviceRelayPairCode {
        try await sendJSON(
            path: DevBarCoreConstants.DeviceRelay.createPairPath,
            method: "POST",
            body: CreatePairRequest(macDeviceId: macDeviceId),
            bearerToken: deviceToken
        )
    }

    public func confirmPair(
        pairCode: String,
        macDeviceId: String,
        iphoneDeviceId: String,
        iphoneDeviceName: String?,
        publicKey: String?
    ) async throws -> DeviceRelayConfirmPairResponse {
        try await sendJSON(
            path: DevBarCoreConstants.DeviceRelay.confirmPairPath,
            method: "POST",
            body: ConfirmPairRequest(
                pairCode: pairCode,
                macDeviceId: macDeviceId,
                iphoneDeviceId: iphoneDeviceId,
                iphoneDeviceName: iphoneDeviceName,
                publicKey: publicKey
            ),
            bearerToken: nil
        )
    }

    public func revokePair(macDeviceId: String, iphoneDeviceId: String, deviceToken: String) async throws -> Bool {
        let response: RevokePairResponse = try await sendJSON(
            path: DevBarCoreConstants.DeviceRelay.revokePairPath,
            method: "POST",
            body: RevokePairRequest(macDeviceId: macDeviceId, iphoneDeviceId: iphoneDeviceId),
            bearerToken: deviceToken
        )
        return response.revoked
    }

    public func sendDeviceCommand(
        type: DeviceRelayCommandType,
        targetDeviceId: String,
        deviceToken: String,
        nonce: String? = nil,
        timestamp: Int64 = Int64(Date().timeIntervalSince1970 * 1000)
    ) async throws -> DeviceRelayCommandResponse {
        try await sendJSON(
            path: DevBarCoreConstants.DeviceRelay.commandPath(targetDeviceId: targetDeviceId),
            method: "POST",
            body: DeviceRelayCommandRequest(type: type, nonce: nonce ?? Self.makeNonce(), timestamp: timestamp),
            bearerToken: deviceToken
        )
    }

    public func makeWebSocketTask(deviceId: String, deviceToken: String) throws -> URLSessionWebSocketTask {
        let url = try Self.webSocketURL(baseURL: baseURL, deviceId: deviceId, deviceToken: deviceToken)
        return session.webSocketTask(with: url)
    }

    public static func webSocketURL(baseURL: URL, deviceId: String, deviceToken: String) throws -> URL {
        var components = URLComponents()
        components.scheme = baseURL.scheme == "http" ? "ws" : "wss"
        components.host = baseURL.host
        components.port = baseURL.port
        components.path = DevBarCoreConstants.DeviceRelay.socketPath
        components.queryItems = [
            URLQueryItem(name: "deviceId", value: deviceId),
            URLQueryItem(name: "token", value: deviceToken),
        ]
        guard let url = components.url else {
            throw DeviceRelayError.invalidURL
        }
        return url
    }

    private func sendJSON<RequestBody: Encodable, ResponseBody: Decodable>(
        path: String,
        method: String,
        body: RequestBody?,
        bearerToken: String?
    ) async throws -> ResponseBody {
        guard let endpoint = URL(string: path, relativeTo: baseURL)?.absoluteURL else {
            throw DeviceRelayError.invalidURL
        }
        var request = URLRequest(url: endpoint)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let bearerToken {
            request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            request.httpBody = try JSONEncoder().encode(body)
        }

        print("[DevBar:DeviceRelay] \(method) \(endpoint.absoluteString) auth=\(bearerToken == nil ? "none" : "bearer")")
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            print("[DevBar:DeviceRelay] \(method) no HTTP response")
            throw DeviceRelayError.invalidRelayResponse
        }
        print("[DevBar:DeviceRelay] \(method) status=\(httpResponse.statusCode) bytes=\(data.count) preview=\(Self.safeResponsePreview(from: data))")

        guard 200..<300 ~= httpResponse.statusCode else {
            if let error = try? JSONDecoder().decode(DeviceRelayErrorEnvelope.self, from: data) {
                throw DeviceRelayError.serverError(error.code)
            }
            throw DeviceRelayError.httpError(httpResponse.statusCode)
        }

        if let error = try? JSONDecoder().decode(DeviceRelayErrorEnvelope.self, from: data),
           error.isFailure {
            throw DeviceRelayError.serverError(error.code)
        }

        do {
            return try JSONDecoder().decode(ResponseBody.self, from: data)
        } catch {
            print("[DevBar:DeviceRelay] \(method) decode failed: \(error)")
            throw DeviceRelayError.invalidRelayResponse
        }
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
        return String(text.prefix(500))
    }

    private static func redactSensitiveValues(in value: Any) -> Any {
        if let dict = value as? [String: Any] {
            return Dictionary<String, Any>(uniqueKeysWithValues: dict.map { key, value -> (String, Any) in
                let lowercasedKey = key.lowercased()
                if lowercasedKey.contains("token") ||
                    lowercasedKey.contains("secret") ||
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

    private static func makeNonce() -> String {
        UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
    }
}

private struct DeviceRelayCommandRequest: Encodable {
    let type: DeviceRelayCommandType
    let nonce: String
    let timestamp: Int64
}

private struct CreatePairRequest: Encodable {
    let macDeviceId: String
}

private struct ConfirmPairRequest: Encodable {
    let pairCode: String
    let macDeviceId: String
    let iphoneDeviceId: String
    let iphoneDeviceName: String?
    let publicKey: String?
}

private struct RevokePairRequest: Encodable {
    let macDeviceId: String
    let iphoneDeviceId: String
}

extension DeviceRelayRegistrationResponse: Decodable {
    private enum CodingKeys: String, CodingKey {
        case deviceToken
        case device
        case data
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let token = try container.decodeIfPresent(String.self, forKey: .deviceToken),
           let device = try container.decodeIfPresent(DeviceRelayDevice.self, forKey: .device) {
            self.init(deviceToken: token, device: device)
            return
        }

        if let nested = try container.decodeIfPresent(DeviceRelayRegistrationResponse.self, forKey: .data) {
            self = nested
            return
        }

        throw DecodingError.keyNotFound(
            CodingKeys.deviceToken,
            DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Missing deviceToken")
        )
    }
}

extension DeviceRelayPairCode: Decodable {
    private enum CodingKeys: String, CodingKey {
        case pairCode
        case expiresAt
        case data
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let pairCode = try container.decodeIfPresent(String.self, forKey: .pairCode),
           let expiresAt = try container.decodeIfPresent(Int64.self, forKey: .expiresAt) {
            self.init(pairCode: pairCode, expiresAt: expiresAt)
            return
        }

        if let nested = try container.decodeIfPresent(DeviceRelayPairCode.self, forKey: .data) {
            self = nested
            return
        }

        throw DecodingError.keyNotFound(
            CodingKeys.pairCode,
            DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Missing pairCode")
        )
    }
}

extension DeviceRelayConfirmPairResponse: Decodable {
    private enum CodingKeys: String, CodingKey {
        case paired
        case deviceToken
        case macDevice
        case data
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let paired = try container.decodeIfPresent(Bool.self, forKey: .paired),
           let token = try container.decodeIfPresent(String.self, forKey: .deviceToken),
           let macDevice = try container.decodeIfPresent(DeviceRelayMacDevice.self, forKey: .macDevice) {
            self.init(paired: paired, deviceToken: token, macDevice: macDevice)
            return
        }

        if let nested = try container.decodeIfPresent(DeviceRelayConfirmPairResponse.self, forKey: .data) {
            self = nested
            return
        }

        throw DecodingError.keyNotFound(
            CodingKeys.deviceToken,
            DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Missing deviceToken")
        )
    }
}

private struct DeviceRelayPeersEnvelope: Decodable {
    let devices: [DeviceRelayDevice]

    private enum CodingKeys: String, CodingKey {
        case devices
        case data
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let devices = try container.decodeIfPresent([DeviceRelayDevice].self, forKey: .devices) {
            self.devices = devices
            return
        }

        if let nested = try container.decodeIfPresent(DeviceRelayPeersEnvelope.self, forKey: .data) {
            self = nested
            return
        }

        self.devices = []
    }
}

private struct RevokePairResponse: Decodable {
    let revoked: Bool

    private enum CodingKeys: String, CodingKey {
        case revoked
        case data
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let revoked = try container.decodeIfPresent(Bool.self, forKey: .revoked) {
            self.revoked = revoked
            return
        }

        if let nested = try container.decodeIfPresent(RevokePairResponse.self, forKey: .data) {
            self = nested
            return
        }

        self.revoked = false
    }
}

extension DeviceRelayCommandResponse: Decodable {
    private enum CodingKeys: String, CodingKey {
        case commandId
        case targetDeviceId
        case messageType
        case delivery
        case acceptedAt
        case data
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let commandId = try container.decodeIfPresent(String.self, forKey: .commandId),
           let targetDeviceId = try container.decodeIfPresent(String.self, forKey: .targetDeviceId),
           let messageType = try container.decodeIfPresent(DeviceRelayMessageType.self, forKey: .messageType),
           let delivery = try container.decodeIfPresent(String.self, forKey: .delivery),
           let acceptedAt = try container.decodeIfPresent(Int64.self, forKey: .acceptedAt) {
            self.init(
                commandId: commandId,
                targetDeviceId: targetDeviceId,
                messageType: messageType,
                delivery: delivery,
                acceptedAt: acceptedAt
            )
            return
        }

        if let nested = try container.decodeIfPresent(DeviceRelayCommandResponse.self, forKey: .data) {
            self = nested
            return
        }

        throw DecodingError.keyNotFound(
            CodingKeys.commandId,
            DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Missing commandId")
        )
    }
}

private struct DeviceRelayErrorEnvelope: Decodable {
    let success: Bool?
    let numericCode: Int?
    let message: String?

    var isFailure: Bool {
        success == false
    }

    var code: String {
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
    }
}

private struct EmptyBody: Encodable {}
