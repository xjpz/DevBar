import Foundation

public final class DeepSeekAPIClient: Sendable {
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

    public func fetchUsage(token: String, cookieString: String) async throws -> DeepSeekUsageResponse {
        guard let url = URL(string: DevBarCoreConstants.DeepSeek.userSummaryURL) else {
            throw APIError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        request.setValue(cookieString, forHTTPHeaderField: "Cookie")
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/149.0.0.0 Safari/537.36",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("https://platform.deepseek.com/usage", forHTTPHeaderField: "Referer")
        request.setValue("1.0.0", forHTTPHeaderField: "x-app-version")

        #if DEBUG
        print("[DeepSeekAPIClient] GET \(url.absoluteString)")
        #endif

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        #if DEBUG
        print("[DeepSeekAPIClient] Response: \(httpResponse.statusCode)")
        if httpResponse.statusCode != 200 {
            let body = String(data: data, encoding: .utf8) ?? "(not utf8)"
            print("[DeepSeekAPIClient] Error body: \(body.prefix(500))")
        }
        #endif

        switch httpResponse.statusCode {
        case 200:
            break
        case 401, 403:
            throw APIError.deepseekUnauthorized
        default:
            throw deepseekHTTPError(httpResponse.statusCode)
        }

        do {
            let decoded = try decoder.decode(DeepSeekUsageResponse.self, from: data)
            try validateResponse(decoded)
            return decoded
        } catch let error as APIError {
            throw error
        } catch {
            throw APIError.decodingError(error)
        }
    }

    private func validateResponse(_ response: DeepSeekUsageResponse) throws {
        if let code = response.code, code != 0 {
            let message = response.msg?.trimmingCharacters(in: .whitespacesAndNewlines)
            throw APIError.providerMessage(message?.isEmpty == false ? message! : CoreL10n.text("invalid_response"))
        }

        guard response.data?.bizData != nil else {
            throw APIError.invalidResponse
        }
    }

    private func deepseekHTTPError(_ statusCode: Int) -> APIError {
        switch statusCode {
        case 429:
            return .providerMessage(CoreL10n.text("deepseek_rate_limited"))
        case 500...599:
            return .providerMessage(CoreL10n.text("deepseek_server_error"))
        default:
            return .httpError(statusCode)
        }
    }
}
