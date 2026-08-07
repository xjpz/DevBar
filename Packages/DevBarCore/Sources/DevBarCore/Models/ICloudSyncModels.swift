import Foundation

public enum ICloudSyncEntity: String, Codable, CaseIterable, Sendable {
    case memo
    case markdownDocument
    case chatConversation
    case chatMessage
    case apiRecord
    case terminalServer
    case webHistoryRecord
    case hermesSettings
    case homeAssistantSettings
}

public struct ICloudSyncSettings: Codable, Equatable, Sendable {
    public static let schemaVersion = 2

    public var schemaVersion: Int
    public var isEnabled: Bool
    public var enabledEntities: Set<ICloudSyncEntity>
    public var syncAPISensitiveFields: Bool
    public var syncTerminalSecrets: Bool
    public var syncProviderCredentials: Bool

    public init(
        schemaVersion: Int = Self.schemaVersion,
        isEnabled: Bool = false,
        enabledEntities: Set<ICloudSyncEntity> = Self.defaultEnabledEntities,
        syncAPISensitiveFields: Bool = false,
        syncTerminalSecrets: Bool = false,
        syncProviderCredentials: Bool = false
    ) {
        self.schemaVersion = schemaVersion
        self.isEnabled = isEnabled
        self.enabledEntities = enabledEntities
        self.syncAPISensitiveFields = syncAPISensitiveFields
        self.syncTerminalSecrets = syncTerminalSecrets
        self.syncProviderCredentials = syncProviderCredentials
    }

    public static let defaultEnabledEntities: Set<ICloudSyncEntity> = [
        .memo,
        .markdownDocument,
        .chatConversation,
        .chatMessage,
        .terminalServer,
        .hermesSettings,
        .homeAssistantSettings,
    ]

    public static let `default` = ICloudSyncSettings()

    public static let firstVersionSupportedEntities: Set<ICloudSyncEntity> = [
        .memo,
        .markdownDocument,
        .chatConversation,
        .chatMessage,
        .terminalServer,
        .hermesSettings,
        .homeAssistantSettings,
    ]

    public func isSyncEnabled(for entity: ICloudSyncEntity) -> Bool {
        enabledEntities.contains(entity)
    }

    public var normalizedForFirstVersion: ICloudSyncSettings {
        var copy = self
        if copy.schemaVersion < Self.schemaVersion {
            copy.enabledEntities.formUnion([.hermesSettings, .homeAssistantSettings])
            copy.schemaVersion = Self.schemaVersion
        }
        copy.enabledEntities = copy.enabledEntities.intersection(Self.firstVersionSupportedEntities)
        return copy
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case isEnabled
        case enabledEntities
        case syncAPISensitiveFields
        case syncTerminalSecrets
        case syncProviderCredentials
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? false
        enabledEntities = try container.decodeIfPresent(Set<ICloudSyncEntity>.self, forKey: .enabledEntities)
            ?? Self.defaultEnabledEntities
        syncAPISensitiveFields = try container.decodeIfPresent(Bool.self, forKey: .syncAPISensitiveFields) ?? false
        syncTerminalSecrets = try container.decodeIfPresent(Bool.self, forKey: .syncTerminalSecrets) ?? false
        syncProviderCredentials = try container.decodeIfPresent(Bool.self, forKey: .syncProviderCredentials) ?? false
    }
}

public struct ICloudPreferenceState<Value: Codable & Equatable & Sendable>: Codable, Equatable, Sendable {
    public var value: Value
    public var updatedAt: Date

    public init(value: Value, updatedAt: Date) {
        self.value = value
        self.updatedAt = updatedAt
    }
}

public struct HermesCloudSyncSnapshot: Codable, Equatable, Sendable {
    public static let schemaVersion = 1

    public var schemaVersion: Int
    public var apiBaseURL: String
    public var hermesModel: String
    public var hermesProvider: String
    public var isStreamingEnabled: Bool
    public var chatTabProvider: ChatBotProviderKind
    public var hermesChatRemark: String
    public var hermesChatTag: String

    public init(settings: HermesSettings, schemaVersion: Int = Self.schemaVersion) {
        self.schemaVersion = schemaVersion
        self.apiBaseURL = settings.apiBaseURL
        self.hermesModel = settings.hermesModel
        self.hermesProvider = settings.hermesProvider
        self.isStreamingEnabled = settings.isStreamingEnabled
        self.chatTabProvider = settings.normalizedChatTabProvider
        self.hermesChatRemark = settings.hermesChatRemark
        self.hermesChatTag = settings.hermesChatTag
    }

    public var settings: HermesSettings {
        HermesSettings(
            apiBaseURL: apiBaseURL,
            hermesModel: hermesModel,
            hermesProvider: hermesProvider,
            isStreamingEnabled: isStreamingEnabled,
            chatTabProvider: chatTabProvider,
            hermesChatRemark: hermesChatRemark,
            hermesChatTag: hermesChatTag
        )
    }
}

public struct HomeAssistantCloudSyncSnapshot: Codable, Equatable, Sendable {
    public static let schemaVersion = 1

    public var schemaVersion: Int
    public var connectionSettings: HomeAssistantConnectionSettings
    public var instanceFingerprint: String?
    public var deviceVisibility: HomeAssistantDeviceVisibilitySettings?
    public var dashboardLayout: HomeAssistantDashboardLayoutSettings?
    public var devicePresentations: HomeAssistantDevicePresentationSettings?
    public var accessoryPresentations: HomeAssistantAccessoryPresentationSettings?
    public var accessoryGrouping: HomeAssistantAccessoryGroupingSettings?

    public init(
        connectionSettings: HomeAssistantConnectionSettings,
        instanceFingerprint: String? = nil,
        deviceVisibility: HomeAssistantDeviceVisibilitySettings? = nil,
        dashboardLayout: HomeAssistantDashboardLayoutSettings? = nil,
        devicePresentations: HomeAssistantDevicePresentationSettings? = nil,
        accessoryPresentations: HomeAssistantAccessoryPresentationSettings? = nil,
        accessoryGrouping: HomeAssistantAccessoryGroupingSettings? = nil,
        schemaVersion: Int = Self.schemaVersion
    ) {
        self.schemaVersion = schemaVersion
        self.connectionSettings = connectionSettings
        self.instanceFingerprint = instanceFingerprint
        self.deviceVisibility = deviceVisibility
        self.dashboardLayout = dashboardLayout
        self.devicePresentations = devicePresentations
        self.accessoryPresentations = accessoryPresentations
        self.accessoryGrouping = accessoryGrouping
    }
}

public struct ICloudSyncRecord: Codable, Equatable, Sendable {
    public var id: String
    public var entity: ICloudSyncEntity
    public var localID: String
    public var updatedAt: Date
    public var deletedAt: Date?
    public var fields: [String: String]
    public var needsCredentialRestore: Bool

    public init(
        id: String,
        entity: ICloudSyncEntity,
        localID: String,
        updatedAt: Date,
        deletedAt: Date? = nil,
        fields: [String: String],
        needsCredentialRestore: Bool = false
    ) {
        self.id = id
        self.entity = entity
        self.localID = localID
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.fields = fields
        self.needsCredentialRestore = needsCredentialRestore
    }
}

public struct ICloudChatMessageSnapshot: Equatable, Sendable {
    public var id: UUID
    public var sortIndex: Int?
    public var createdAt: Date
    public var updatedAt: Date
    public var content: String

    public init(
        id: UUID,
        sortIndex: Int?,
        createdAt: Date,
        updatedAt: Date,
        content: String
    ) {
        self.id = id
        self.sortIndex = sortIndex
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.content = content
    }
}
