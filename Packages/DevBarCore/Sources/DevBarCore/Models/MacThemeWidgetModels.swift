import Foundation

public enum MacThemeWidgetPage: String, Codable, Sendable, CaseIterable {
    case quota
    case macConsole
}

public enum MacWidgetScreenState: String, Codable, Sendable {
    case locked
    case unlocked
    case unknown
}

public enum MacWidgetDisplayState: String, Codable, Sendable {
    case awake
    case sleeping
    case unknown
}

public enum MacWidgetKeepAwakeState: String, Codable, Sendable {
    case active
    case inactive
    case unknown
}

public enum MacWidgetConnectionMode: String, Codable, Sendable {
    case local
    case relay
    case unknown
}

public struct MacStatusWidgetSnapshot: Codable, Sendable, Equatable {
    public let deviceID: String
    public let deviceName: String
    public let isOnline: Bool
    public let lastSeenAt: Date?
    public let screenState: MacWidgetScreenState
    public let displayState: MacWidgetDisplayState
    public let keepAwakeState: MacWidgetKeepAwakeState
    public let connectionMode: MacWidgetConnectionMode
    public let batteryPercent: Int?
    public let cpuPercent: Int?
    public let memoryPercent: Int?
    public let lastUpdated: Date

    public init(
        deviceID: String,
        deviceName: String,
        isOnline: Bool,
        lastSeenAt: Date?,
        screenState: MacWidgetScreenState,
        displayState: MacWidgetDisplayState,
        keepAwakeState: MacWidgetKeepAwakeState,
        connectionMode: MacWidgetConnectionMode,
        batteryPercent: Int?,
        cpuPercent: Int?,
        memoryPercent: Int?,
        lastUpdated: Date
    ) {
        self.deviceID = deviceID
        self.deviceName = deviceName
        self.isOnline = isOnline
        self.lastSeenAt = lastSeenAt
        self.screenState = screenState
        self.displayState = displayState
        self.keepAwakeState = keepAwakeState
        self.connectionMode = connectionMode
        self.batteryPercent = batteryPercent
        self.cpuPercent = cpuPercent
        self.memoryPercent = memoryPercent
        self.lastUpdated = lastUpdated
    }
}

public struct MacThemeWidgetUserSnapshot: Codable, Sendable, Equatable {
    public let displayName: String
    public let avatarSymbol: String
    public let avatarFileName: String?

    public static let `default` = MacThemeWidgetUserSnapshot(
        displayName: "DevBar",
        avatarSymbol: "sparkles"
    )

    public init(displayName: String, avatarSymbol: String, avatarFileName: String? = nil) {
        self.displayName = displayName
        self.avatarSymbol = avatarSymbol
        self.avatarFileName = avatarFileName
    }
}

public struct MacThemeWidgetSnapshot: Codable, Sendable, Equatable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let user: MacThemeWidgetUserSnapshot
    public let macStatus: MacStatusWidgetSnapshot?
    public let lastUpdated: Date

    public static let placeholder = MacThemeWidgetSnapshot(
        schemaVersion: currentSchemaVersion,
        user: .default,
        macStatus: nil,
        lastUpdated: .distantPast
    )

    public init(
        schemaVersion: Int,
        user: MacThemeWidgetUserSnapshot,
        macStatus: MacStatusWidgetSnapshot?,
        lastUpdated: Date
    ) {
        self.schemaVersion = schemaVersion
        self.user = user
        self.macStatus = macStatus
        self.lastUpdated = lastUpdated
    }
}

public enum MacThemeWidgetPolicy {
    public static let availablePages: [MacThemeWidgetPage] = [.macConsole, .quota]

    public static func percentText(_ percent: Int?) -> String {
        guard let percent else { return "--" }
        return "\(max(0, min(percent, 100)))%"
    }
}
