import Foundation

public enum PushNotificationServiceError: Error, Equatable {
    case invalidURL
    case invalidResponse
    case httpError(Int)
    case serverError(String)
}

public final class PushNotificationService: Sendable {
    public static let shared = PushNotificationService()

    private let baseURL: URL
    private let session: URLSession

    public init(
        baseURL: URL = URL(string: DevBarCoreConstants.DeviceRelay.baseURL)!,
        session: URLSession = .shared
    ) {
        self.baseURL = baseURL
        self.session = session
    }

    public func register(
        _ registration: PushDeviceRegistration,
        deviceToken: String
    ) async throws -> PushDeviceRegistrationResponse {
        try await sendJSON(
            path: DevBarCoreConstants.PushNotifications.registerPath,
            method: "POST",
            body: registration,
            bearerToken: deviceToken
        )
    }

    public func fetchPreferences(deviceToken: String) async throws -> PushNotificationPreferences {
        try await sendJSON(
            path: DevBarCoreConstants.PushNotifications.preferencesPath,
            method: "GET",
            body: Optional<EmptyBody>.none,
            bearerToken: deviceToken
        )
    }

    public func updatePreferences(
        _ preferences: PushNotificationPreferences,
        deviceToken: String
    ) async throws -> PushNotificationPreferences {
        try await sendJSON(
            path: DevBarCoreConstants.PushNotifications.preferencesPath,
            method: "PUT",
            body: preferences,
            bearerToken: deviceToken
        )
    }

    public func registerLiveActivityPushToStart(
        _ registration: LiveActivityPushToStartRegistration,
        deviceToken: String
    ) async throws -> LiveActivityPushToStartRegistrationResponse {
        try await sendJSON(
            path: DevBarCoreConstants.PushNotifications.liveActivityPushToStartPath,
            method: "POST",
            body: registration,
            bearerToken: deviceToken
        )
    }

    public func registerLiveActivity(
        _ registration: LiveActivityPushRegistration,
        deviceToken: String
    ) async throws -> LiveActivityPushRegistrationResponse {
        try await sendJSON(
            path: DevBarCoreConstants.PushNotifications.liveActivitiesPath,
            method: "POST",
            body: registration,
            bearerToken: deviceToken
        )
    }

    public func sendLiveMessage(
        _ message: LiveMessageRequest,
        deviceToken: String
    ) async throws -> LiveMessageResponse {
        try await sendJSON(
            path: DevBarCoreConstants.PushNotifications.liveMessagePath,
            method: "POST",
            body: message,
            bearerToken: deviceToken
        )
    }

    public func sendSMSAlert(
        _ alert: SMSAlertRequest,
        deviceToken: String
    ) async throws -> SMSAlertResponse {
        try await sendJSON(
            path: DevBarCoreConstants.PushNotifications.smsAlertPath,
            method: "POST",
            body: alert,
            bearerToken: deviceToken
        )
    }

    public func createOpenKey(
        name: String,
        deviceToken: String
    ) async throws -> PushOpenKeyCreated {
        try await sendJSON(
            path: DevBarCoreConstants.PushNotifications.openKeysPath,
            method: "POST",
            body: PushOpenKeyCreateRequest(name: name),
            bearerToken: deviceToken
        )
    }

    public func listOpenKeys(deviceToken: String) async throws -> [PushOpenKeySummary] {
        let response: PushOpenKeyListResponse = try await sendJSON(
            path: DevBarCoreConstants.PushNotifications.openKeysPath,
            method: "GET",
            body: Optional<EmptyBody>.none,
            bearerToken: deviceToken
        )
        return response.keys
    }

    @discardableResult
    public func revokeOpenKey(
        id: Int64,
        deviceToken: String
    ) async throws -> Bool {
        let response: PushOpenKeyRevokeResponse = try await sendJSON(
            path: DevBarCoreConstants.PushNotifications.openKeyPath(id: id),
            method: "DELETE",
            body: Optional<EmptyBody>.none,
            bearerToken: deviceToken
        )
        return response.revoked
    }

    private func sendJSON<RequestBody: Encodable, ResponseBody: Decodable>(
        path: String,
        method: String,
        body: RequestBody?,
        bearerToken: String
    ) async throws -> ResponseBody {
        guard let endpoint = URL(string: path, relativeTo: baseURL)?.absoluteURL else {
            throw PushNotificationServiceError.invalidURL
        }
        var request = URLRequest(url: endpoint)
        request.httpMethod = method
        request.timeoutInterval = 8
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        if let body {
            request.httpBody = try JSONEncoder().encode(body)
        }

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw PushNotificationServiceError.invalidResponse
        }
        guard 200..<300 ~= httpResponse.statusCode else {
            throw PushNotificationServiceError.httpError(httpResponse.statusCode)
        }

        if let envelope = try? JSONDecoder().decode(ErrorEnvelope.self, from: data),
           envelope.success == false {
            throw PushNotificationServiceError.serverError(envelope.message ?? String(envelope.code ?? 0))
        }

        do {
            return try JSONDecoder().decode(SuccessEnvelope<ResponseBody>.self, from: data).data
        } catch {
            throw PushNotificationServiceError.invalidResponse
        }
    }
}

private struct SuccessEnvelope<Content: Decodable>: Decodable {
    let data: Content
}

private struct ErrorEnvelope: Decodable {
    let success: Bool?
    let code: Int?
    let message: String?

    private enum CodingKeys: String, CodingKey {
        case success
        case code
        case message = "msg"
    }
}

private struct EmptyBody: Encodable {}
