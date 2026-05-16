import Foundation

public final class MimoAPIClient: Sendable {
    private static let requiredCookieNames: Set<String> = [
        "userId",
        "api-platform_slh",
        "api-platform_ph",
        "api-platform_serviceToken",
    ]

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

        let result: (MimoUsageResponse, String?) = try await fetchWithCookies(url: url, serviceToken: serviceToken)
        try validatePlatformResponse(code: result.0.code, message: result.0.message, dataExists: result.0.data != nil)
        return result.0
    }

    public func fetchUsageWithUpdate(serviceToken: String) async throws -> (MimoUsageResponse, String?) {
        guard let url = URL(string: DevBarCoreConstants.MiMO.platformUsageURL) else {
            throw APIError.invalidResponse
        }

        let result: (MimoUsageResponse, String?) = try await fetchWithCookies(url: url, serviceToken: serviceToken)
        try validatePlatformResponse(code: result.0.code, message: result.0.message, dataExists: result.0.data != nil)
        return result
    }

    public func fetchPlanDetail(serviceToken: String) async throws -> MimoPlanDetailResponse {
        guard let url = URL(string: DevBarCoreConstants.MiMO.platformPlanDetailURL) else {
            throw APIError.invalidResponse
        }

        let result: (MimoPlanDetailResponse, String?) = try await fetchWithCookies(url: url, serviceToken: serviceToken)
        try validatePlatformResponse(code: result.0.code, message: result.0.message, dataExists: result.0.data != nil)
        return result.0
    }

    /// Build a cookie string from platform cookies for Keychain storage.
    public static func platformCookieString(from cookies: [HTTPCookie]) -> String {
        cookies
            .filter { requiredCookieNames.contains($0.name) }
            .map { cookie in
                let value = stripQuotes(cookie.value)
                return "\(cookie.name)=\"\(value)\""
            }
            .joined(separator: "; ")
    }

    public static func normalizedServiceToken(from rawValue: String) -> String {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        let pairs = cookiePairs(from: trimmed)
        let present = Set(pairs.map(\.name))
        return requiredCookieNames.isSubset(of: present) ? trimmed : ""
    }

    public static func cookieHeaderValue(for rawValue: String) -> String {
        let pairs = cookiePairs(from: rawValue)
        return pairs
            .filter { requiredCookieNames.contains($0.name) }
            .map { pair in
                pair.wasQuoted ? "\(pair.name)=\"\(pair.value)\"" : "\(pair.name)=\(pair.value)"
            }
            .joined(separator: "; ")
    }

    public static func isSameRequiredCookie(_ lhs: String, _ rhs: String) -> Bool {
        let lhsValues = requiredCookieValues(from: lhs)
        let rhsValues = requiredCookieValues(from: rhs)
        return !lhsValues.isEmpty && lhsValues == rhsValues
    }

    public static func requiredCookieValues(from rawValue: String) -> [String: String] {
        var values: [String: String] = [:]
        for pair in cookiePairs(from: rawValue) where requiredCookieNames.contains(pair.name) {
            values[pair.name] = pair.value
        }
        return values
    }

    private func fetchWithCookies<Response: Decodable>(url: URL, serviceToken: String) async throws -> (Response, String?) {
        let normalizedToken = Self.normalizedServiceToken(from: serviceToken)
        guard !normalizedToken.isEmpty else {
            throw APIError.providerMessage(CoreL10n.text("mimo_cookie_required"))
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        let cookieHeader = Self.cookieHeaderValue(for: serviceToken)
        request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
        request.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
        request.setValue("https://platform.xiaomimimo.com", forHTTPHeaderField: "Origin")
        request.setValue("https://platform.xiaomimimo.com/console/plan-manage", forHTTPHeaderField: "Referer")
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/143.0.0.0 Safari/537.36",
            forHTTPHeaderField: "User-Agent"
        )

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

        let setCookieHeaders: [String] = httpResponse.allHeaderFields
            .compactMap { key, value -> String? in
                guard (key as? String)?.lowercased() == "set-cookie",
                      let val = value as? String else { return nil }
                return val
            }

        let updatedCookie = mergeSetCookies(serviceToken, setCookieHeaders: setCookieHeaders)

        do {
            let decoded = try decoder.decode(Response.self, from: data)
            return (decoded, updatedCookie)
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

    private static let targetCookieNames: Set<String> = requiredCookieNames

    private func mergeSetCookies(_ currentCookie: String, setCookieHeaders: [String]) -> String? {
        var merged = Self.cookiePairs(from: currentCookie)

        for header in setCookieHeaders {
            let pair = header.components(separatedBy: ";").first?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard let eqIndex = pair.firstIndex(of: "=") else { continue }
            let name = String(pair[..<eqIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
            let value = String(pair[pair.index(after: eqIndex)...])

            guard Self.targetCookieNames.contains(name), !value.isEmpty else { continue }

            if let idx = merged.firstIndex(where: { $0.name == name }) {
                merged[idx] = (name, Self.stripQuotes(value), false)
            } else {
                merged.append((name, Self.stripQuotes(value), false))
            }
        }

        guard !merged.isEmpty else { return nil }

        let newCookie = merged
            .map { $0.wasQuoted ? "\($0.name)=\"\($0.value)\"" : "\($0.name)=\($0.value)" }
            .joined(separator: "; ")

        return newCookie == currentCookie.trimmingCharacters(in: .whitespacesAndNewlines) ? nil : newCookie
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
