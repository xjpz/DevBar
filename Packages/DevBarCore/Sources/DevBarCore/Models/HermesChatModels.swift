import Foundation

public enum ChatBotProviderKind: String, Codable, CaseIterable, Identifiable, Equatable, Sendable {
    case hermes

    public var id: String { rawValue }
}

public struct HermesSettings: Equatable, Sendable {
    public var apiBaseURL: String
    public var hermesModel: String
    public var hermesProvider: String
    public var isStreamingEnabled: Bool
    public var chatTabProvider: ChatBotProviderKind
    public var hermesChatRemark: String
    public var hermesChatTag: String

    public init(
        apiBaseURL: String = "",
        hermesModel: String = "",
        hermesProvider: String = "",
        isStreamingEnabled: Bool = true,
        chatTabProvider: ChatBotProviderKind = .hermes,
        hermesChatRemark: String = "",
        hermesChatTag: String = ""
    ) {
        self.apiBaseURL = apiBaseURL
        self.hermesModel = hermesModel
        self.hermesProvider = hermesProvider
        self.isStreamingEnabled = isStreamingEnabled
        self.chatTabProvider = chatTabProvider
        self.hermesChatRemark = hermesChatRemark
        self.hermesChatTag = hermesChatTag
    }

    public static let defaults = HermesSettings()

    public var enabledChatProviders: [ChatBotProviderKind] {
        [.hermes]
    }

    public var normalizedChatTabProvider: ChatBotProviderKind {
        .hermes
    }

    public var toolsChatProviders: [ChatBotProviderKind] {
        []
    }

    public func isChatProviderEnabled(_ provider: ChatBotProviderKind) -> Bool {
        provider == .hermes
    }

    public func chatRemark(for provider: ChatBotProviderKind) -> String {
        hermesChatRemark
    }

    public func chatTag(for provider: ChatBotProviderKind) -> String {
        hermesChatTag
    }
}

public enum HermesChatRole: String, Codable, Equatable, Sendable {
    case system
    case user
    case assistant
}

public struct HermesChatImageURL: Codable, Equatable, Sendable {
    public var url: String
    public var detail: String?

    public init(url: String, detail: String? = nil) {
        self.url = url
        self.detail = detail?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }
}

public enum HermesChatContentPart: Codable, Equatable, Sendable {
    case text(String)
    case imageURL(String)

    private enum CodingKeys: String, CodingKey {
        case type
        case text
        case imageURL = "image_url"
    }

    private enum ContentType: String, Codable {
        case text
        case imageURL = "image_url"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(ContentType.self, forKey: .type)
        switch type {
        case .text:
            self = .text(try container.decode(String.self, forKey: .text))
        case .imageURL:
            let imageURL = try container.decode(HermesChatImageURL.self, forKey: .imageURL)
            self = .imageURL(imageURL.url)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .text(let text):
            try container.encode(ContentType.text, forKey: .type)
            try container.encode(text, forKey: .text)
        case .imageURL(let url):
            try container.encode(ContentType.imageURL, forKey: .type)
            try container.encode(HermesChatImageURL(url: url), forKey: .imageURL)
        }
    }
}

public enum HermesChatMessageContent: Codable, Equatable, Sendable {
    case text(String)
    case parts([HermesChatContentPart])

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let text = try? container.decode(String.self) {
            self = .text(text)
        } else {
            self = .parts(try container.decode([HermesChatContentPart].self))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .text(let text):
            try container.encode(text)
        case .parts(let parts):
            try container.encode(parts)
        }
    }
}

public struct HermesChatRequestMessage: Codable, Equatable, Sendable {
    public var role: HermesChatRole
    public var content: HermesChatMessageContent

    public init(role: HermesChatRole, content: String) {
        self.role = role
        self.content = .text(content)
    }

    public init(role: HermesChatRole, content: HermesChatMessageContent) {
        self.role = role
        self.content = content
    }
}

public struct HermesChatRequest: Encodable, Sendable {
    public var messages: [HermesChatRequestMessage]
    public var model: String?
    public var stream: Bool

    public init(messages: [HermesChatRequestMessage], model: String? = nil, stream: Bool) {
        self.messages = messages
        self.model = model?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.stream = stream
    }
}

public struct HermesModel: Decodable, Equatable, Identifiable, Sendable {
    public let id: String
    public let object: String?
}

public struct HermesModelsResponse: Decodable, Equatable, Sendable {
    public let object: String?
    public let data: [HermesModel]
}

public struct HermesAPIServerCapabilities: Decodable, Equatable, Sendable {
    public struct Auth: Decodable, Equatable, Sendable {
        public let type: String?
        public let required: Bool
    }

    public struct Features: Decodable, Equatable, Sendable {
        public let chatCompletions: Bool
        public let responsesAPI: Bool
        public let runSubmission: Bool
        public let runEventsSSE: Bool
        public let runStop: Bool

        private enum CodingKeys: String, CodingKey {
            case chatCompletions = "chat_completions"
            case responsesAPI = "responses_api"
            case runSubmission = "run_submission"
            case runEventsSSE = "run_events_sse"
            case runStop = "run_stop"
        }
    }

    public let object: String?
    public let platform: String?
    public let model: String?
    public let auth: Auth
    public let features: Features
}

public struct HermesResponsesRequest: Encodable, Sendable {
    public var model: String?
    public var input: String
    public var conversation: String
    public var store: Bool

    public init(model: String? = nil, input: String, conversation: String, store: Bool = true) {
        self.model = model?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.input = input
        self.conversation = conversation.trimmingCharacters(in: .whitespacesAndNewlines)
        self.store = store
    }
}

public struct HermesResponsesResponse: Decodable, Equatable, Sendable {
    public struct OutputItem: Decodable, Equatable, Sendable {
        public struct ContentItem: Decodable, Equatable, Sendable {
            public let type: String?
            public let text: String?
        }

        public let type: String?
        public let role: String?
        public let content: [ContentItem]?
    }

    public let id: String?
    public let object: String?
    public let status: String?
    public let model: String?
    public let output: [OutputItem]?

    public var assistantContent: String {
        output?
            .filter { $0.type == nil || $0.type == "message" }
            .filter { $0.role == nil || $0.role == "assistant" }
            .compactMap { item in
                item.content?
                    .compactMap(\.text)
                    .filter { !$0.isEmpty }
                    .joined()
            }
            .first(where: { !$0.isEmpty }) ?? ""
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

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
