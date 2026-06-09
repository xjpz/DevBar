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
        agentWatcherEnabled: Bool = DevBarCoreConstants.Features.agentWatcherEnabled,
        summaryEnabled: Bool = true,
        iconUrl: String? = nil
    ) {
        self.relayDeviceId = relayDeviceId
        self.pushEnabled = pushEnabled
        self.agentWatcherEnabled = DevBarCoreConstants.Features.agentWatcherEnabled && agentWatcherEnabled
        self.summaryEnabled = summaryEnabled
        self.iconUrl = iconUrl
    }
}

public enum LiveMessageActivityType: String, Codable, Sendable, Equatable {
    case devBarLiveMessage = "devbar_live_message"
}

public enum LiveActivityStartedBy: String, Codable, Sendable, Equatable {
    case local
    case remote
}

public enum LiveMessageDelivery: String, Codable, Sendable, Equatable {
    case liveActivity = "live_activity"
    case notificationFallback = "notification_fallback"
}

public enum SMSAlertDelivery: String, Codable, Sendable, Equatable {
    case relayForwarded = "relay_forwarded"
    case apnsFallback = "apns_fallback"
    case duplicate
    case targetMissing = "target_missing"
    case pushUnavailable = "push_unavailable"
    case targetOffline = "target_offline"
}

public struct LiveActivityPushToStartRegistration: Codable, Sendable, Equatable {
    public let activityType: LiveMessageActivityType
    public let pushToStartToken: String
    public let bundleId: String
    public let environment: PushEnvironment
    public let minimumIOSVersion: String?

    public init(
        activityType: LiveMessageActivityType,
        pushToStartToken: String,
        bundleId: String,
        environment: PushEnvironment,
        minimumIOSVersion: String?
    ) {
        self.activityType = activityType
        self.pushToStartToken = pushToStartToken
        self.bundleId = bundleId
        self.environment = environment
        self.minimumIOSVersion = minimumIOSVersion
    }
}

public struct LiveActivityPushToStartRegistrationResponse: Codable, Sendable, Equatable {
    public let registered: Bool
    public let activityType: LiveMessageActivityType

    public init(registered: Bool, activityType: LiveMessageActivityType) {
        self.registered = registered
        self.activityType = activityType
    }
}

public struct LiveActivityPushRegistration: Codable, Sendable, Equatable {
    public let activityId: String
    public let activityType: LiveMessageActivityType
    public let activityPushToken: String
    public let bundleId: String
    public let environment: PushEnvironment
    public let startedBy: LiveActivityStartedBy

    public init(
        activityId: String,
        activityType: LiveMessageActivityType,
        activityPushToken: String,
        bundleId: String,
        environment: PushEnvironment,
        startedBy: LiveActivityStartedBy
    ) {
        self.activityId = activityId
        self.activityType = activityType
        self.activityPushToken = activityPushToken
        self.bundleId = bundleId
        self.environment = environment
        self.startedBy = startedBy
    }
}

public struct LiveActivityPushRegistrationResponse: Codable, Sendable, Equatable {
    public let registered: Bool
    public let activityId: String

    public init(registered: Bool, activityId: String) {
        self.registered = registered
        self.activityId = activityId
    }
}

public struct LiveMessageRequest: Codable, Sendable, Equatable {
    public let targetDeviceId: String
    public let message: String
    public let source: String?
    public let projectName: String?
    public let eventId: String?
    public let allowRemoteStart: Bool
    public let fallbackNotification: Bool

    public init(
        targetDeviceId: String,
        message: String,
        source: String?,
        projectName: String?,
        eventId: String?,
        allowRemoteStart: Bool = true,
        fallbackNotification: Bool = true
    ) {
        self.targetDeviceId = targetDeviceId
        self.message = message
        self.source = source
        self.projectName = projectName
        self.eventId = eventId
        self.allowRemoteStart = allowRemoteStart
        self.fallbackNotification = fallbackNotification
    }
}

public struct LiveMessageResponse: Codable, Sendable, Equatable {
    public let delivery: LiveMessageDelivery
    public let activityId: String?
    public let startedBy: LiveActivityStartedBy?
    public let fallbackSent: Bool

    public init(
        delivery: LiveMessageDelivery,
        activityId: String?,
        startedBy: LiveActivityStartedBy?,
        fallbackSent: Bool
    ) {
        self.delivery = delivery
        self.activityId = activityId
        self.startedBy = startedBy
        self.fallbackSent = fallbackSent
    }
}

public struct SMSAlertRequest: Codable, Sendable, Equatable {
    public let targetDeviceId: String
    public let messageText: String
    public let sender: String?
    public let matchedKeyword: String?
    public let notificationTitle: String?
    public let receivedAt: Int64?
    public let dedupKey: String?
    public let fallbackNotification: Bool

    public init(
        targetDeviceId: String,
        messageText: String,
        sender: String? = nil,
        matchedKeyword: String? = nil,
        notificationTitle: String? = nil,
        receivedAt: Int64? = nil,
        dedupKey: String? = nil,
        fallbackNotification: Bool = true
    ) {
        self.targetDeviceId = targetDeviceId
        self.messageText = messageText
        self.sender = sender
        self.matchedKeyword = matchedKeyword
        self.notificationTitle = notificationTitle
        self.receivedAt = receivedAt
        self.dedupKey = dedupKey
        self.fallbackNotification = fallbackNotification
    }
}

public struct SMSAlertResponse: Codable, Sendable, Equatable {
    public let eventId: String
    public let targetDeviceId: String
    public let delivery: SMSAlertDelivery
    public let fallbackSent: Bool
    public let duplicate: Bool

    public init(
        eventId: String,
        targetDeviceId: String,
        delivery: SMSAlertDelivery,
        fallbackSent: Bool,
        duplicate: Bool
    ) {
        self.eventId = eventId
        self.targetDeviceId = targetDeviceId
        self.delivery = delivery
        self.fallbackSent = fallbackSent
        self.duplicate = duplicate
    }
}
