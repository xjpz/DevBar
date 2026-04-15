// BigModelAPIClient.swift
// DevBar

import Foundation

enum APIError: Error, LocalizedError {
    case notLoggedIn
    case invalidResponse
    case httpError(Int)
    case unauthorized
    case decodingError(Error)

    var errorDescription: String? {
        switch self {
        case .notLoggedIn:
            return "未登录"
        case .invalidResponse:
            return "无效的响应"
        case .httpError(let code):
            return "请求失败 (\(code))"
        case .unauthorized:
            return "登录已过期，请重新登录"
        case .decodingError(let error):
            return "数据解析失败: \(error.localizedDescription)"
        }
    }
}

final class BigModelAPIClient: Sendable {
    private let session: URLSession

    deinit {
        print("[DevBar] BigModelAPIClient DEINIT")
    }

    init() {
        let config = URLSessionConfiguration.default
        // Disable URLSession's built-in cookie handling to avoid conflicts
        config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never
        config.httpCookieStorage = nil
        self.session = URLSession(configuration: config)
    }

    // MARK: - Public API

    func fetchSubscriptionList(credentials: AuthCredentials) async throws -> [Subscription] {
        var request = URLRequest(url: URL(string: Constants.API.subscriptionListURL)!)
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

    func fetchQuotaLimit(credentials: AuthCredentials) async throws -> QuotaData {
        print("[DevBar] Fetching quota. token=\(!credentials.token.isEmpty), cookieLen=\(credentials.cookieString.count)")

        var request = URLRequest(url: URL(string: Constants.API.quotaLimitURL)!)
        request.httpMethod = "GET"
        request.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
        request.setValue("zh", forHTTPHeaderField: "Accept-Language")
        request.setValue(credentials.token, forHTTPHeaderField: "Authorization")
        request.setValue(credentials.cookieString, forHTTPHeaderField: "Cookie")

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            print("[DevBar] Invalid response type")
            throw APIError.invalidResponse
        }

        print("[DevBar] HTTP \(httpResponse.statusCode), url=\(httpResponse.url?.absoluteString ?? "nil"), dataLen=\(data.count)")

        if data.isEmpty {
            print("[DevBar] Empty response body for status \(httpResponse.statusCode)")
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
            // Print raw response for debugging
            if let raw = String(data: data, encoding: .utf8) {
                print("[DevBar] Raw API response: \(raw)")
            }
            let quotaResponse = try JSONDecoder().decode(QuotaResponse.self, from: data)
            guard quotaResponse.success == true, let quotaData = quotaResponse.data else {
                let message = quotaResponse.msg ?? "未知错误"
                print("[DevBar] API failure: \(message)")
                throw APIError.invalidResponse
            }
            return quotaData
        } catch let error as APIError {
            throw error
        } catch {
            if let raw = String(data: data, encoding: .utf8) {
                print("[DevBar] Decode error: \(error)")
                print("[DevBar] Raw: \(raw.prefix(1000))")
            }
            throw APIError.decodingError(error)
        }
    }
}
