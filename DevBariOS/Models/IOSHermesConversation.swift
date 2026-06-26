import Foundation
import SwiftData

@Model
final class IOSHermesConversation {
    var id: UUID
    var title: String
    var remark: String
    var lastMessagePreview: String
    var messageCount: Int
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
        lastMessagePreview: String = "",
        messageCount: Int = 0,
        isArchived: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        archivedAt: Date? = nil,
        messages: [IOSHermesMessage] = []
    ) {
        self.id = id
        self.title = title
        self.remark = remark
        self.lastMessagePreview = lastMessagePreview
        self.messageCount = messageCount
        self.isArchived = isArchived
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.archivedAt = archivedAt
        self.messages = messages
    }
}

extension IOSHermesConversation {
    var displayTitle: String {
        let trimmedRemark = remark.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedRemark.isEmpty { return trimmedRemark }

        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedTitle.isEmpty { return trimmedTitle }

        return String(localized: "ios_hermes_title")
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
