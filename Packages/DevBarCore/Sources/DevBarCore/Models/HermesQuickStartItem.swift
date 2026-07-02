import Foundation

public struct HermesQuickStartItem: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var title: String
    public var subtitle: String
    public var systemImage: String
    public var prompt: String

    public init(
        id: UUID = UUID(),
        title: String,
        subtitle: String,
        systemImage: String,
        prompt: String
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.prompt = prompt
    }

    public var normalized: HermesQuickStartItem? {
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedTitle.isEmpty, !normalizedPrompt.isEmpty else {
            return nil
        }
        let normalizedImage = systemImage.trimmingCharacters(in: .whitespacesAndNewlines)
        return HermesQuickStartItem(
            id: id,
            title: normalizedTitle,
            subtitle: subtitle.trimmingCharacters(in: .whitespacesAndNewlines),
            systemImage: normalizedImage.isEmpty ? "sparkles" : normalizedImage,
            prompt: normalizedPrompt
        )
    }
}
