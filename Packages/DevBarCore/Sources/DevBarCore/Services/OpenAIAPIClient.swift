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

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

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
}
