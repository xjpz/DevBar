import Foundation

public final class DevBarAccountAPIClient: @unchecked Sendable {
    private let baseURL: URL
    private let session: URLSession
    private let decoder = JSONDecoder()

    public init(
        baseURL: URL = URL(string: DevBarCoreConstants.Server.baseURL)!,
        session: URLSession = .shared
    ) {
        self.baseURL = baseURL
        self.session = session
    }

    public func loginWithApple(identityToken: String, nonce: String, displayNameCandidate: String?) async throws -> DevBarAppleLoginResponse {
        try await send(
            path: DevBarCoreConstants.Account.appleLoginPath,
            method: "POST",
            token: nil,
            body: AppleLoginBody(identityToken: identityToken, nonce: nonce, displayNameCandidate: displayNameCandidate),
            as: DevBarAppleLoginResponse.self
        )
    }

    public func profile(token: String) async throws -> DevBarUserProfile {
        try await send(path: DevBarCoreConstants.Account.mePath, method: "GET", token: token, as: DevBarUserProfile.self)
    }

    public func updateProfile(displayName: String, profileVersion: Int64, token: String) async throws -> DevBarUserProfile {
        try await send(
            path: DevBarCoreConstants.Account.profilePath,
            method: "PATCH",
            token: token,
            body: UpdateProfileBody(displayName: displayName, profileVersion: profileVersion),
            as: DevBarUserProfile.self
        )
    }

    public func logout(token: String) async throws {
        try await sendVoid(path: DevBarCoreConstants.Account.logoutPath, method: "POST", token: token)
    }

    public func deleteAccount(token: String) async throws {
        try await sendVoid(path: DevBarCoreConstants.Account.deleteAccountPath, method: "DELETE", token: token)
    }

    public func linkCurrentDevice(
        appToken: String,
        deviceToken: String,
        deviceSecret: String
    ) async throws -> DevBarDeviceBindingResult {
        try await send(
            path: DevBarCoreConstants.Account.deviceBindingPath,
            method: "POST",
            token: appToken,
            additionalHeaders: [
                "X-Device-Token": deviceToken,
                "X-Device-Secret": deviceSecret,
            ],
            as: DevBarDeviceBindingResult.self
        )
    }

    public func messages(filter: DevBarMessageFilter, cursor: Int64? = nil, limit: Int = 20, token: String) async throws -> DevBarMessagePage {
        var components = URLComponents()
        components.path = DevBarCoreConstants.Account.messagesPath
        components.queryItems = [
            URLQueryItem(name: "filter", value: filter.rawValue),
            URLQueryItem(name: "limit", value: String(limit)),
        ] + cursor.map { [URLQueryItem(name: "cursor", value: String($0))] }.getOrElse([])
        return try await send(path: components.string ?? DevBarCoreConstants.Account.messagesPath, method: "GET", token: token, as: DevBarMessagePage.self)
    }

    public func unreadCount(token: String) async throws -> Int {
        let value: DevBarUnreadCount = try await send(path: DevBarCoreConstants.Account.unreadCountPath, method: "GET", token: token, as: DevBarUnreadCount.self)
        return value.count
    }

    public func setMessageRead(_ messageId: Int64, isRead: Bool, token: String) async throws -> DevBarMessageMutationResult {
        try await send(
            path: "\(DevBarCoreConstants.Account.messagesPath)/\(messageId)/read",
            method: isRead ? "PUT" : "DELETE",
            token: token,
            as: DevBarMessageMutationResult.self
        )
    }

    public func markMessageRead(messageId: String, token: String) async throws -> DevBarMessageMutationResult {
        try await send(
            path: DevBarCoreConstants.Account.messageReadPath(messageId: messageId),
            method: "PUT",
            token: token,
            as: DevBarMessageMutationResult.self
        )
    }

    public func markAllRead(token: String) async throws -> DevBarMessageMutationResult {
        try await send(
            path: DevBarCoreConstants.Account.markAllReadPath,
            method: "PUT",
            token: token,
            as: DevBarMessageMutationResult.self
        )
    }

    public func deleteMessage(_ messageId: Int64, token: String) async throws -> DevBarMessageMutationResult {
        try await send(
            path: "\(DevBarCoreConstants.Account.messagesPath)/\(messageId)",
            method: "DELETE",
            token: token,
            as: DevBarMessageMutationResult.self
        )
    }

    private func send<Response: Decodable>(path: String, method: String, token: String?, as: Response.Type) async throws -> Response {
        try await send(path: path, method: method, token: token, bodyData: nil, additionalHeaders: [:], as: Response.self)
    }

    private func send<Response: Decodable>(
        path: String,
        method: String,
        token: String?,
        additionalHeaders: [String: String],
        as: Response.Type
    ) async throws -> Response {
        try await send(
            path: path,
            method: method,
            token: token,
            bodyData: nil,
            additionalHeaders: additionalHeaders,
            as: Response.self
        )
    }

    private func send<Response: Decodable, Body: Encodable>(path: String, method: String, token: String?, body: Body, as: Response.Type) async throws -> Response {
        try await send(
            path: path,
            method: method,
            token: token,
            bodyData: try JSONEncoder().encode(body),
            additionalHeaders: [:],
            as: Response.self
        )
    }

    private func send<Response: Decodable>(
        path: String,
        method: String,
        token: String?,
        bodyData: Data?,
        additionalHeaders: [String: String],
        as: Response.Type
    ) async throws -> Response {
        guard let url = URL(string: path, relativeTo: baseURL) else { throw DevBarAccountAPIError.invalidServerURL }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = bodyData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if bodyData != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        for (name, value) in additionalHeaders {
            request.setValue(value, forHTTPHeaderField: name)
        }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw DevBarAccountAPIError.invalidResponse }
        let errorMessage = (try? decoder.decode(ErrorEnvelope.self, from: data).msg) ?? "请求失败"
        guard (200..<300).contains(http.statusCode) else {
            switch http.statusCode {
            case 401: throw DevBarAccountAPIError.unauthorized(errorMessage)
            case 409: throw DevBarAccountAPIError.conflict(errorMessage)
            default: throw DevBarAccountAPIError.server(status: http.statusCode, message: errorMessage)
            }
        }
        guard let value = try? decoder.decode(SuccessEnvelope<Response>.self, from: data).data else {
            throw DevBarAccountAPIError.invalidResponse
        }
        return value
    }

    private func sendVoid(path: String, method: String, token: String) async throws {
        guard let url = URL(string: path, relativeTo: baseURL) else { throw DevBarAccountAPIError.invalidServerURL }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw DevBarAccountAPIError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let message = (try? decoder.decode(ErrorEnvelope.self, from: data).msg) ?? "请求失败"
            if http.statusCode == 401 { throw DevBarAccountAPIError.unauthorized(message) }
            throw DevBarAccountAPIError.server(status: http.statusCode, message: message)
        }
    }
}

private struct SuccessEnvelope<Value: Decodable>: Decodable { let data: Value }
private struct ErrorEnvelope: Decodable { let msg: String }
private struct AppleLoginBody: Encodable { let identityToken: String; let nonce: String; let displayNameCandidate: String? }
private struct UpdateProfileBody: Encodable { let displayName: String; let profileVersion: Int64 }

private extension Optional {
    func getOrElse(_ fallback: Wrapped) -> Wrapped { self ?? fallback }
}
