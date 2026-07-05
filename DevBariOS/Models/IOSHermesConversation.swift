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

    var firstUserMessageTitle: String? {
        let firstUserMessage = messages
            .filter { $0.role == .user }
            .sorted { lhs, rhs in
                let lhsSortIndex = lhs.sortIndex ?? Int.max
                let rhsSortIndex = rhs.sortIndex ?? Int.max
                if lhsSortIndex != rhsSortIndex {
                    return lhsSortIndex < rhsSortIndex
                }
                if lhs.createdAt != rhs.createdAt {
                    return lhs.createdAt < rhs.createdAt
                }
                return lhs.id.uuidString < rhs.id.uuidString
            }
            .first

        guard let content = firstUserMessage?.content else { return nil }
        return Self.title(fromFirstUserMessage: content)
    }

    func recordMessage(content: String, at date: Date = Date()) {
        lastMessagePreview = Self.preview(from: IOSHermesImageAttachment.displayContent(from: content))
        messageCount = messages.count
        updatedAt = date
    }

    func recordMessage(role: HermesChatRole, content: String, at date: Date = Date()) {
        lastMessagePreview = Self.preview(from: IOSHermesImageAttachment.displayContent(from: content))
        if role == .user {
            updateTitleFromFirstUserMessageIfNeeded(content)
        }
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

    static func title(fromFirstUserMessage content: String, limit: Int = 40) -> String? {
        let visibleContent = IOSHermesImageAttachment.displayContent(from: content)
        let lines = visibleContent.components(separatedBy: .newlines)
        let attachmentTitle = lines.compactMap(attachmentReferenceTitle).first
        let collapsed = lines
            .filter { attachmentReferenceTitle(from: $0) == nil }
            .joined(separator: " ")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !collapsed.isEmpty else { return attachmentTitle }

        let terminators = CharacterSet(charactersIn: "。！？!?")
        let firstSentenceEnd = collapsed.rangeOfCharacter(from: terminators)?.lowerBound
        let sentence = firstSentenceEnd.map { String(collapsed[..<$0]) } ?? collapsed
        let trimmed = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard trimmed.count > limit else { return trimmed }
        return String(trimmed.prefix(limit)) + "..."
    }

    private func updateTitleFromFirstUserMessageIfNeeded(_ content: String) {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let defaultTitles: Set<String> = [
            String(localized: "ios_hermes_title"),
            ChatBotProviderKind.hermes.title,
            ChatBotProviderKind.hermes.toolSubtitle,
            "ChatBot"
        ]
        guard trimmedTitle.isEmpty || defaultTitles.contains(trimmedTitle) else { return }
        guard let firstUserTitle = Self.title(fromFirstUserMessage: content) else { return }
        title = firstUserTitle
    }

    private static func attachmentReferenceTitle(from line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("["), trimmed.hasSuffix("]") else { return nil }
        let body = String(trimmed.dropFirst().dropLast())
        guard body.hasPrefix("Attachment: ") || body.hasPrefix("附件：") else { return nil }
        let payload = body
            .replacingOccurrences(of: "Attachment: ", with: "")
            .replacingOccurrences(of: "附件：", with: "")
        let parts = payload.components(separatedBy: " - ")
        guard parts.count >= 2 else { return nil }
        let type = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
        let name = parts.dropFirst().joined(separator: " - ").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        let imageTokens = ["photo", "image", "camera", "图片", "照片", "拍照"]
        let prefix = imageTokens.contains { type.localizedCaseInsensitiveContains($0) || name.localizedCaseInsensitiveContains($0) }
            ? "图片"
            : "文件"
        return "\(prefix) - \(name)"
    }
}
