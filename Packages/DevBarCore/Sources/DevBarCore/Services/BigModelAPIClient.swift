import Foundation

public final class BigModelAPIClient: Sendable {
    private let session: URLSession

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
}
