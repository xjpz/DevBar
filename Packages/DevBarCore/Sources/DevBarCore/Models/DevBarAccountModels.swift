import Foundation

public struct DevBarUserProfile: Codable, Sendable, Equatable {
    public let userId: Int64
    public let displayName: String
    public let displayNameSource: String
    public let profileVersion: Int64
    public let updatedAt: Int64

    public init(userId: Int64, displayName: String, displayNameSource: String, profileVersion: Int64, updatedAt: Int64) {
        self.userId = userId
        self.displayName = displayName
        self.displayNameSource = displayNameSource
        self.profileVersion = profileVersion
        self.updatedAt = updatedAt
    }
}

public struct DevBarAppleLoginResponse: Codable, Sendable, Equatable {
    public let sessionToken: String
    public let expiresAt: Int64
    public let profile: DevBarUserProfile
}

public struct DevBarDeviceBindingResult: Codable, Sendable, Equatable {
    public let deviceId: String
    public let linked: Bool
    public let claimedSnippets: Int
    public let claimedMessages: Int
    public let claimedPushKeys: Int
}

public struct DevBarMessage: Codable, Sendable, Equatable, Identifiable {
    public let id: Int64
    public let messageId: String
    public let snippetId: Int64?
    public let title: String
    public let preview: String?
    public let body: String?
    public let source: String
    public let messageType: String
    public let targetURL: String?
    public var readTime: Int64
    public let createdAt: Int64

    public var isRead: Bool {
        get { readTime > 0 }
        set {
            readTime = newValue
                ? max(readTime, Int64(Date().timeIntervalSince1970 * 1_000))
                : 0
        }
    }

    /// Presentation category derived exclusively from the server-owned message type.
    /// The raw `messageType` is retained so newer server values remain observable.
    public var kind: DevBarMessageKind {
        DevBarMessageKind(messageType: messageType)
    }

    public init(
        id: Int64,
        messageId: String,
        snippetId: Int64?,
        title: String,
        preview: String?,
        body: String?,
        source: String,
        messageType: String,
        targetURL: String?,
        readTime: Int64,
        createdAt: Int64
    ) {
        self.id = id
        self.messageId = messageId
        self.snippetId = snippetId
        self.title = title
        self.preview = preview
        self.body = body
        self.source = source
        self.messageType = messageType
        self.targetURL = targetURL
        self.readTime = readTime
        self.createdAt = createdAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, messageId, snippetId, title, preview, body, source
        case messageType, targetURL, readTime, isRead, createdAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int64.self, forKey: .id)
        snippetId = try container.decodeIfPresent(Int64.self, forKey: .snippetId)
        messageId = try container.decodeIfPresent(String.self, forKey: .messageId) ?? "msg_legacy_\(id)"
        title = try container.decode(String.self, forKey: .title)
        preview = try container.decodeIfPresent(String.self, forKey: .preview)
        body = try container.decodeIfPresent(String.self, forKey: .body)
        source = try container.decode(String.self, forKey: .source)
        messageType = try container.decodeIfPresent(String.self, forKey: .messageType) ?? "snippet"
        targetURL = try container.decodeIfPresent(String.self, forKey: .targetURL)
        createdAt = try container.decode(Int64.self, forKey: .createdAt)
        if let value = try container.decodeIfPresent(Int64.self, forKey: .readTime) {
            readTime = value
        } else {
            readTime = (try container.decodeIfPresent(Bool.self, forKey: .isRead) ?? false) ? max(createdAt, 1) : 0
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(messageId, forKey: .messageId)
        try container.encodeIfPresent(snippetId, forKey: .snippetId)
        try container.encode(title, forKey: .title)
        try container.encodeIfPresent(preview, forKey: .preview)
        try container.encodeIfPresent(body, forKey: .body)
        try container.encode(source, forKey: .source)
        try container.encode(messageType, forKey: .messageType)
        try container.encodeIfPresent(targetURL, forKey: .targetURL)
        try container.encode(readTime, forKey: .readTime)
        try container.encode(isRead, forKey: .isRead)
        try container.encode(createdAt, forKey: .createdAt)
    }
}

public enum DevBarMessageKind: Sendable, Equatable {
    case newsDigest
    case snippet
    case textPush
    case system
    case unknown

    public init(messageType: String) {
        switch messageType.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "news", "news_digest", "daily_news", "weekly_news", "tech_news":
            self = .newsDigest
        case "snippet":
            self = .snippet
        case "push_text", "text_push":
            self = .textPush
        case "system", "system_notice", "account_notice":
            self = .system
        default:
            self = .unknown
        }
    }
}

public struct DevBarMessagePage: Codable, Sendable, Equatable {
    public let items: [DevBarMessage]
    public let nextCursor: Int64?
}

public struct DevBarUnreadCount: Codable, Sendable, Equatable {
    public let count: Int
}

public enum DevBarMessageFilter: String, Sendable {
    case all
    case unread
}

public enum DevBarAccountAPIError: LocalizedError, Sendable, Equatable {
    case invalidServerURL
    case invalidResponse
    case unauthorized(String)
    case conflict(String)
    case server(status: Int, message: String)

    public var errorDescription: String? {
        switch self {
        case .invalidServerURL: "服务地址无效"
        case .invalidResponse: "服务器响应格式错误"
        case .unauthorized(let message), .conflict(let message), .server(_, let message): message
        }
    }
}
