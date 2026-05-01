import Foundation

public final class MimoAPIClient: Sendable {
    private static let cookieName = "serviceToken"

    private let session: URLSession
    private let decoder = JSONDecoder()

    public init() {
        let config = URLSessionConfiguration.default
        config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never
        config.httpCookieStorage = nil
        config.timeoutIntervalForRequest = 15
        self.session = URLSession(configuration: config)
    }

    public func fetchUsage(serviceToken: String) async throws -> MimoUsageResponse {
        guard let url = URL(string: DevBarCoreConstants.MiMO.platformUsageURL) else {
            throw APIError.invalidResponse
        }

        let response: MimoUsageResponse = try await fetch(url: url, serviceToken: serviceToken)
        try validatePlatformResponse(code: response.code, message: response.message, dataExists: response.data != nil)
        return response
    }

    public func fetchPlanDetail(serviceToken: String) async throws -> MimoPlanDetailResponse {
        guard let url = URL(string: DevBarCoreConstants.MiMO.platformPlanDetailURL) else {
            throw APIError.invalidResponse
        }

        let response: MimoPlanDetailResponse = try await fetch(url: url, serviceToken: serviceToken)
        try validatePlatformResponse(code: response.code, message: response.message, dataExists: response.data != nil)
        return response
    }

    public static func normalizedServiceToken(from rawValue: String) -> String {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        for pair in cookiePairs(from: trimmed) {
            guard pair.name == cookieName else { continue }
            return pair.value
        }

        return stripQuotes(trimmed)
    }

    public static func cookieHeaderValue(for rawValue: String) -> String {
        let pairs = cookiePairs(from: rawValue)
        if pairs.contains(where: { $0.name == cookieName }) {
            return pairs
                .map { pair in
                    pair.wasQuoted ? "\(pair.name)=\"\(pair.value)\"" : "\(pair.name)=\(pair.value)"
                }
                .joined(separator: "; ")
        }

        return "\(cookieName)=\"\(normalizedServiceToken(from: rawValue))\""
    }

    private func fetch<Response: Decodable>(url: URL, serviceToken: String) async throws -> Response {
        let normalizedToken = Self.normalizedServiceToken(from: serviceToken)
        guard !normalizedToken.isEmpty else {
            throw APIError.providerMessage(CoreL10n.text("mimo_cookie_required"))
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(Self.cookieHeaderValue(for: serviceToken), forHTTPHeaderField: "Cookie")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("en", forHTTPHeaderField: "Accept-Language")

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200:
            break
        case 401, 403:
            throw APIError.mimoCookieExpired
        default:
            throw APIError.httpError(httpResponse.statusCode)
        }

        do {
            return try decoder.decode(Response.self, from: data)
        } catch {
            throw APIError.decodingError(error)
        }
    }

    private func validatePlatformResponse(code: Int?, message: String?, dataExists: Bool) throws {
        if let code, code != 0 {
            let text = message?.trimmingCharacters(in: .whitespacesAndNewlines)
            throw APIError.providerMessage(text?.isEmpty == false ? text! : CoreL10n.text("invalid_response"))
        }

        guard dataExists else {
            throw APIError.invalidResponse
        }
    }

    private static func stripQuotes(_ value: String) -> String {
        var result = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if result.hasPrefix("\"") {
            result.removeFirst()
        }
        if result.hasSuffix("\"") {
            result.removeLast()
        }
        return result
    }

    private static func cookiePairs(from rawValue: String) -> [(name: String, value: String, wasQuoted: Bool)] {
        rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: ";")
            .compactMap { part -> (name: String, value: String, wasQuoted: Bool)? in
                let pair = part.trimmingCharacters(in: .whitespacesAndNewlines)
                guard let separator = pair.firstIndex(of: "=") else { return nil }

                let name = pair[..<separator].trimmingCharacters(in: .whitespacesAndNewlines)
                let rawValue = String(pair[pair.index(after: separator)...])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let value = stripQuotes(rawValue)
                guard !name.isEmpty, !value.isEmpty else { return nil }

                return (name, value, rawValue.hasPrefix("\"") || rawValue.hasSuffix("\""))
            }
    }
}
