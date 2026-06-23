import Foundation

public struct HermesSettings: Equatable, Sendable {
    public var apiBaseURL: String
    public var isStreamingEnabled: Bool

    public init(apiBaseURL: String = "", isStreamingEnabled: Bool = true) {
        self.apiBaseURL = apiBaseURL
        self.isStreamingEnabled = isStreamingEnabled
    }

    public static let defaults = HermesSettings()
}

public enum HermesChatRole: String, Codable, Equatable, Sendable {
    case system
    case user
    case assistant
}

public struct HermesChatRequestMessage: Codable, Equatable, Sendable {
    public var role: HermesChatRole
    public var content: String

    public init(role: HermesChatRole, content: String) {
        self.role = role
        self.content = content
    }
}

public struct HermesChatRequest: Encodable, Sendable {
    public var messages: [HermesChatRequestMessage]
    public var stream: Bool

    public init(messages: [HermesChatRequestMessage], stream: Bool) {
        self.messages = messages
        self.stream = stream
    }
}

public struct HermesChatResponse: Decodable, Equatable, Sendable {
    public struct Choice: Decodable, Equatable, Sendable {
        public struct Message: Decodable, Equatable, Sendable {
            public let role: String?
            public let content: String?
        }

        public let message: Message?
        public let text: String?
    }

    public let choices: [Choice]?
    public let content: String?
    public let message: String?
    public let response: String?

    public var assistantContent: String {
        choices?.compactMap { choice in
            choice.message?.content ?? choice.text
        }.first(where: { !$0.isEmpty }) ?? content ?? message ?? response ?? ""
    }
}

public struct HermesStreamResponse: Decodable, Equatable, Sendable {
    public struct Choice: Decodable, Equatable, Sendable {
        public struct Delta: Decodable, Equatable, Sendable {
            public let content: String?
        }

        public let delta: Delta?
        public let text: String?
    }

    public let choices: [Choice]?
    public let content: String?
    public let message: String?
    public let response: String?

    public var deltaContent: String? {
        choices?.compactMap { choice in
            choice.delta?.content ?? choice.text
        }.first(where: { !$0.isEmpty }) ?? content ?? message ?? response
    }
}
