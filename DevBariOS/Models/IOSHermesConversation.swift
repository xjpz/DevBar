import Foundation
import DevBarCore
import SwiftData

@Model
final class IOSHermesConversation {
    var id: UUID
    var title: String
    var remark: String?
    var tag: String?
    var lastMessagePreview: String
    var messageCount: Int
    var providerRawValue: String?
    var remoteSessionId: String?
    var remoteSource: String?
    var lastSyncedAt: Date?
    var syncStateRawValue: String?
    var isArchived: Bool
    var createdAt: Date
    var updatedAt: Date
    var archivedAt: Date?

    @Relationship(deleteRule: .cascade, inverse: \IOSHermesMessage.conversation)
    var messages: [IOSHermesMessage]

    init(
        id: UUID = UUID(),
        title: String = String(localized: "ios_hermes_title"),
        remark: String = "",
        tag: String = "",
        lastMessagePreview: String = "",
        messageCount: Int = 0,
        provider: ChatBotProviderKind = .hermes,
        remoteSessionId: String? = nil,
        remoteSource: String? = nil,
        lastSyncedAt: Date? = nil,
        syncStateRawValue: String = "local",
        isArchived: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        archivedAt: Date? = nil,
        messages: [IOSHermesMessage] = []
    ) {
        self.id = id
        self.title = title
        self.remark = remark
        self.tag = tag
        self.lastMessagePreview = lastMessagePreview
        self.messageCount = messageCount
        self.providerRawValue = provider.rawValue
        self.remoteSessionId = remoteSessionId
        self.remoteSource = remoteSource
        self.lastSyncedAt = lastSyncedAt
        self.syncStateRawValue = syncStateRawValue
        self.isArchived = isArchived
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.archivedAt = archivedAt
        self.messages = messages
    }
}

extension IOSHermesConversation {
    var chatProvider: ChatBotProviderKind {
        get { ChatBotProviderKind(rawValue: providerRawValue ?? "") ?? .hermes }
        set { providerRawValue = newValue.rawValue }
    }

    var displayTitle: String {
        let trimmedRemark = (remark ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedRemark.isEmpty { return trimmedRemark }

        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedTitle.isEmpty { return trimmedTitle }

        return String(localized: "ios_hermes_title")
    }

    var displayTag: String {
        let trimmedTag = (tag ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedTag.isEmpty { return trimmedTag }
        return chatProvider.title
    }

    func recordMessage(content: String, at date: Date = Date()) {
        lastMessagePreview = Self.preview(from: content)
        messageCount = messages.count
        updatedAt = date
    }

    static func preview(from content: String, limit: Int = 80) -> String {
        let collapsed = content
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard collapsed.count > limit else { return collapsed }
        return String(collapsed.prefix(limit)) + "..."
    }
}
