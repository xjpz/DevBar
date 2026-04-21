// OpenAIAPIClient.swift
// DevBar

import Foundation

final class OpenAIAPIClient: Sendable {
    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.default
        config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never
        config.httpCookieStorage = nil
        config.timeoutIntervalForRequest = 15
        self.session = URLSession(configuration: config)
    }

    func fetchUsage(accessToken: String, accountId: String?) async throws -> OpenAIUsageResponse {
        guard let url = URL(string: Constants.OpenAI.usageURL) else {
            throw APIError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let accountId, !accountId.isEmpty {
            request.setValue(accountId, forHTTPHeaderField: "ChatGPT-Account-Id")
        }

        print("[DevBar] OpenAI GET \(Constants.OpenAI.usageURL)")
        print("[DevBar]   accountId: \(accountId ?? "nil")")
        print("[DevBar]   token: \(accessToken.prefix(20))...\(accessToken.suffix(8))")

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        print("[DevBar] OpenAI HTTP \(httpResponse.statusCode), dataLen=\(data.count)")
        if let raw = String(data: data, encoding: .utf8) {
            print("[DevBar] OpenAI response: \(raw)")
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
            let usageResponse = try JSONDecoder().decode(OpenAIUsageResponse.self, from: data)
            return usageResponse
        } catch {
            throw APIError.decodingError(error)
        }
    }
}
