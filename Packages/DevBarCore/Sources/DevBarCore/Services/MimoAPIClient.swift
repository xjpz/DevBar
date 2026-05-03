import Foundation

public final class MimoAPIClient: Sendable {
    private static let cookieName = "serviceToken"
    private static let platformCookiePrefix = "api-platform_"

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

    /// Build a cookie string from platform cookies for Keychain storage.
    public static func platformCookieString(from cookies: [HTTPCookie]) -> String {
        let targetNames: Set<String> = [
            "\(platformCookiePrefix)serviceToken",
            "\(platformCookiePrefix)slh",
            "\(platformCookiePrefix)ph",
            "userId",
            "passToken",
        ]
        return cookies
            .filter { targetNames.contains($0.name) }
            .map { cookie in
                let value = stripQuotes(cookie.value)
                return "\(cookie.name)=\"\(value)\""
            }
            .joined(separator: "; ")
    }

    public static func normalizedServiceToken(from rawValue: String) -> String {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        for pair in cookiePairs(from: trimmed) {
            if pair.name == cookieName || pair.name == "\(platformCookiePrefix)\(cookieName)" {
                return pair.value
            }
        }

        return stripQuotes(trimmed)
    }

    public static func cookieHeaderValue(for rawValue: String) -> String {
        let pairs = cookiePairs(from: rawValue)

        // Input already contains api-platform_* cookies from WebView — send as-is
        if pairs.contains(where: { $0.name.hasPrefix(platformCookiePrefix) }) {
            return pairs
                .map { pair in
                    pair.wasQuoted ? "\(pair.name)=\"\(pair.value)\"" : "\(pair.name)=\(pair.value)"
                }
                .joined(separator: "; ")
        }

        // Legacy: user pasted serviceToken=... or raw value
        if pairs.contains(where: { $0.name == cookieName }) {
            return pairs
                .map { pair in
                    pair.wasQuoted ? "\(pair.name)=\"\(pair.value)\"" : "\(pair.name)=\(pair.value)"
                }
                .joined(separator: "; ")
        }

        // Raw token value — wrap as serviceToken="value"
        return "\(cookieName)=\"\(normalizedServiceToken(from: rawValue))\""
    }

    private func fetch<Response: Decodable>(url: URL, serviceToken: String) async throws -> Response {
        let normalizedToken = Self.normalizedServiceToken(from: serviceToken)
        guard !normalizedToken.isEmpty else {
            throw APIError.providerMessage(CoreL10n.text("mimo_cookie_required"))
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        let cookieHeader = Self.cookieHeaderValue(for: serviceToken)
        request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("en", forHTTPHeaderField: "Accept-Language")

        #if DEBUG
        print("[MimoAPIClient] GET \(url.absoluteString)")
        print("[MimoAPIClient] Cookie: \(cookieHeader.prefix(80))...")
        print("[MimoAPIClient] normalizedToken prefix: \(normalizedToken.prefix(30))...")
        #endif

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        #if DEBUG
        print("[MimoAPIClient] Response: \(httpResponse.statusCode)")
        if httpResponse.statusCode != 200 {
            let body = String(data: data, encoding: .utf8) ?? "(not utf8)"
            print("[MimoAPIClient] Error body: \(body.prefix(500))")
        }
        #endif

        switch httpResponse.statusCode {
        case 200:
            break
        case 401, 403:
            throw APIError.mimoCookieExpired
        default:
            throw mimoHTTPError(httpResponse.statusCode)
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
            let serverMessage = text?.isEmpty == false ? text! : CoreL10n.text("invalid_response")
            throw APIError.providerMessage("\(serverMessage) (platform.xiaomimimo.com)")
        }

        guard dataExists else {
            throw APIError.invalidResponse
        }
    }

    private func mimoHTTPError(_ statusCode: Int) -> APIError {
        switch statusCode {
        case 429:
            return .providerMessage(CoreL10n.text("mimo_rate_limited"))
        case 500...599:
            return .providerMessage(CoreL10n.text("mimo_server_error"))
        default:
            return .httpError(statusCode)
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
