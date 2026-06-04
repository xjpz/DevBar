import Foundation

public enum PushEnvironment: String, Codable, Sendable {
    case development
    case production
}

public struct PushDeviceRegistration: Codable, Sendable, Equatable {
    public let pushToken: String
    public let bundleId: String
    public let environment: PushEnvironment
    public let locale: String?

    public init(pushToken: String, bundleId: String, environment: PushEnvironment, locale: String? = nil) {
        self.pushToken = pushToken
        self.bundleId = bundleId
        self.environment = environment
        self.locale = locale
    }
}

public struct PushDeviceRegistrationResponse: Codable, Sendable, Equatable {
    public let registered: Bool
    public let relayDeviceId: String
    public let environment: PushEnvironment

    public init(registered: Bool, relayDeviceId: String, environment: PushEnvironment) {
        self.registered = registered
        self.relayDeviceId = relayDeviceId
        self.environment = environment
    }
}

public struct PushNotificationPreferences: Codable, Sendable, Equatable {
    public let relayDeviceId: String?
    public var pushEnabled: Bool
    public var agentWatcherEnabled: Bool
    public var summaryEnabled: Bool
    public var iconUrl: String?

    public init(
        relayDeviceId: String? = nil,
        pushEnabled: Bool = true,
        agentWatcherEnabled: Bool = true,
        summaryEnabled: Bool = true,
        iconUrl: String? = nil
    ) {
        self.relayDeviceId = relayDeviceId
        self.pushEnabled = pushEnabled
        self.agentWatcherEnabled = agentWatcherEnabled
        self.summaryEnabled = summaryEnabled
        self.iconUrl = iconUrl
    }
}
