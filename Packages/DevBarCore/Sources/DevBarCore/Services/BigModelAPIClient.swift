import Foundation

public final class BigModelAPIClient: Sendable {
    private let session: URLSession
    private static let pingModel = "glm-4.7"

    public init() {
        let config = URLSessionConfiguration.default
        config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never
        config.httpCookieStorage = nil
        self.session = URLSession(configuration: config)
    }

    public func fetchSubscriptionList(credentials: AuthCredentials) async throws -> [Subscription] {
        var request = URLRequest(url: URL(string: DevBarCoreConstants.API.subscriptionListURL)!)
        request.httpMethod = "GET"
        request.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
        request.setValue("zh", forHTTPHeaderField: "Accept-Language")
        request.setValue(credentials.token, forHTTPHeaderField: "Authorization")
        request.setValue(credentials.cookieString, forHTTPHeaderField: "Cookie")

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200:
            break
        case 401:
            throw APIError.unauthorized
        default:
            if let raw = String(data: data, encoding: .utf8) {
                print("[DevBar] Subscription HTTP \(httpResponse.statusCode): \(raw.prefix(500))")
            }
            throw APIError.httpError(httpResponse.statusCode)
        }

        do {
            let subResponse = try JSONDecoder().decode(SubscriptionResponse.self, from: data)
            guard subResponse.success == true, let subscriptions = subResponse.data else {
                throw APIError.invalidResponse
            }
            return subscriptions
        } catch let error as APIError {
            throw error
        } catch {
            throw APIError.decodingError(error)
        }
    }

    public func fetchQuotaLimit(credentials: AuthCredentials) async throws -> QuotaData {
        var request = URLRequest(url: URL(string: DevBarCoreConstants.API.quotaLimitURL)!)
        request.httpMethod = "GET"
        request.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
        request.setValue("zh", forHTTPHeaderField: "Accept-Language")
        request.setValue(credentials.token, forHTTPHeaderField: "Authorization")
        request.setValue(credentials.cookieString, forHTTPHeaderField: "Cookie")

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        if data.isEmpty {
            throw APIError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200:
            break
        case 401:
            throw APIError.unauthorized
        default:
            if let raw = String(data: data, encoding: .utf8) {
                print("[DevBar] HTTP \(httpResponse.statusCode): \(raw.prefix(500))")
            }
            throw APIError.httpError(httpResponse.statusCode)
        }

        do {
            let quotaResponse = try JSONDecoder().decode(QuotaResponse.self, from: data)
            guard quotaResponse.success == true, let quotaData = quotaResponse.data else {
                throw APIError.invalidResponse
            }
            return quotaData
        } catch let error as APIError {
            throw error
        } catch {
            throw APIError.decodingError(error)
        }
    }

    public func sendPing(apiKey: String) async throws {
        let authorization = Self.normalizedBearerToken(apiKey)
        guard !authorization.isEmpty,
              let url = URL(string: DevBarCoreConstants.API.glmChatCompletionsURL) else {
            throw APIError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(authorization, forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(GLMPingRequest(
            model: Self.pingModel,
            messages: [GLMPingMessage(role: "user", content: "ping")],
            maxTokens: 1,
            temperature: 0
        ))

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200..<300:
            return
        case 401, 403:
            throw APIError.unauthorized
        default:
            if let raw = String(data: data, encoding: .utf8), !raw.isEmpty {
                print("[DevBar] GLM ping HTTP \(httpResponse.statusCode): \(raw.prefix(300))")
            }
            throw APIError.httpError(httpResponse.statusCode)
        }
    }

    public static func normalizedBearerToken(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        return trimmed.hasPrefix("Bearer ") ? trimmed : "Bearer \(trimmed)"
    }
}

private struct GLMPingRequest: Encodable {
    let model: String
    let messages: [GLMPingMessage]
    let maxTokens: Int
    let temperature: Int

    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case maxTokens = "max_tokens"
        case temperature
    }
}

private struct GLMPingMessage: Encodable {
    let role: String
    let content: String
}
