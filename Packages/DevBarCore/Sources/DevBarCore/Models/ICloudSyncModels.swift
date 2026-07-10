import Foundation

public enum ICloudSyncEntity: String, Codable, CaseIterable, Sendable {
    case memo
    case markdownDocument
    case chatConversation
    case chatMessage
    case apiRecord
    case terminalServer
    case webHistoryRecord
}

public struct ICloudSyncSettings: Codable, Equatable, Sendable {
    public var isEnabled: Bool
    public var enabledEntities: Set<ICloudSyncEntity>
    public var syncAPISensitiveFields: Bool
    public var syncTerminalSecrets: Bool
    public var syncProviderCredentials: Bool

    public init(
        isEnabled: Bool = false,
        enabledEntities: Set<ICloudSyncEntity> = Self.defaultEnabledEntities,
        syncAPISensitiveFields: Bool = false,
        syncTerminalSecrets: Bool = false,
        syncProviderCredentials: Bool = false
    ) {
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
    ]

    public static let `default` = ICloudSyncSettings()

    public static let firstVersionSupportedEntities: Set<ICloudSyncEntity> = [
        .memo,
        .markdownDocument,
        .chatConversation,
        .chatMessage,
        .terminalServer,
    ]

    public func isSyncEnabled(for entity: ICloudSyncEntity) -> Bool {
        enabledEntities.contains(entity)
    }

    public var normalizedForFirstVersion: ICloudSyncSettings {
        var copy = self
        copy.enabledEntities = copy.enabledEntities.intersection(Self.firstVersionSupportedEntities)
        return copy
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
