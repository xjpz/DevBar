import Foundation

public final class OpenAIAPIClient: Sendable {
    private let session: URLSession

    public init() {
        let config = URLSessionConfiguration.default
        config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never
        config.httpCookieStorage = nil
        config.timeoutIntervalForRequest = 15
        self.session = URLSession(configuration: config)
    }

    public func fetchUsage(accessToken: String, accountId: String?) async throws -> OpenAIUsageResponse {
        guard let url = URL(string: DevBarCoreConstants.OpenAI.usageURL) else {
            throw APIError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let accountId, !accountId.isEmpty {
            request.setValue(accountId, forHTTPHeaderField: "ChatGPT-Account-Id")
        }

        print("[OpenAIAPIClient] GET \(url.absoluteString)")
        print("[OpenAIAPIClient] Headers: Accept=application/json Authorization=<redacted> ChatGPT-Account-Id=\(accountId?.isEmpty == false ? "set" : "unset")")

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            print("[OpenAIAPIClient] Invalid response body: \(Self.responseBodyString(from: data))")
            throw APIError.invalidResponse
        }

        print("[OpenAIAPIClient] Response status: \(httpResponse.statusCode)")
        print("[OpenAIAPIClient] Response body: \(Self.responseBodyString(from: data))")

        switch httpResponse.statusCode {
        case 200:
            break
        case 401:
            throw APIError.openAIUnauthorized
        default:
            throw APIError.httpError(httpResponse.statusCode)
        }

        do {
            return try JSONDecoder().decode(OpenAIUsageResponse.self, from: data)
        } catch {
            throw APIError.decodingError(error)
        }
    }

    private static func responseBodyString(from data: Data) -> String {
        if let body = String(data: data, encoding: .utf8) {
            return body
        }
        return "<non-utf8 body \(data.count) bytes>"
    }
}
