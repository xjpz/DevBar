import Foundation

public enum TransferPayloadCodec {
    public static let scheme = "devbar"
    public static let host = "transfer"
    public static let payloadQueryItemName = "payload"

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
}

public enum TransferPayloadError: LocalizedError, Equatable {
    case invalidURL
    case unsupportedScheme
    case missingPayload
    case expired
    case unsupportedSchemaVersion(Int)
    case compressionFailed
    case decompressionFailed

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
        }
    }
}
