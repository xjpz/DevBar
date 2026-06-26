import DevBarCore
import Foundation
import SwiftData

enum IOSHermesMessageContentFormat: String, Codable, CaseIterable {
    case plain
    case markdown
    case html
}

@Model
final class IOSHermesMessage {
    var id: UUID
    var roleRawValue: String
    var content: String
    var contentFormatRawValue: String
    var isComplete: Bool
    var createdAt: Date
    var completedAt: Date?
    var errorMessage: String?
    var conversation: IOSHermesConversation?

    init(
        id: UUID = UUID(),
        role: HermesChatRole,
        content: String,
        contentFormat: IOSHermesMessageContentFormat,
        isComplete: Bool = true,
        createdAt: Date = Date(),
        completedAt: Date? = nil,
        errorMessage: String? = nil,
        conversation: IOSHermesConversation? = nil
    ) {
        self.id = id
        self.roleRawValue = role.rawValue
        self.content = content
        self.contentFormatRawValue = contentFormat.rawValue
        self.isComplete = isComplete
        self.createdAt = createdAt
        self.completedAt = completedAt
        self.errorMessage = errorMessage
        self.conversation = conversation
    }
}

extension IOSHermesMessage {
    var role: HermesChatRole {
        get { HermesChatRole(rawValue: roleRawValue) ?? .assistant }
        set { roleRawValue = newValue.rawValue }
    }

    var contentFormat: IOSHermesMessageContentFormat {
        get { IOSHermesMessageContentFormat(rawValue: contentFormatRawValue) ?? .markdown }
        set { contentFormatRawValue = newValue.rawValue }
    }
}

extension IOSHermesMessageContentFormat {
    static func detected(for content: String) -> IOSHermesMessageContentFormat {
        let lowercased = content.lowercased()
        let htmlMarkers = ["<html", "<body", "<div", "<section", "<article", "<p", "<h1", "<h2", "<ul", "<ol", "<table", "<button", "<style"]
        return htmlMarkers.contains { lowercased.contains($0) } ? .html : .markdown
    }
}
