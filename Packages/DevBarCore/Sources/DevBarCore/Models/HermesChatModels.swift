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

// MARK: - Runs API

/// Body for `POST /v1/runs`. The Runs API runs the agent server-side, decoupled
/// from the HTTP connection, so a dropped stream can be re-attached instead of losing
/// the generation. See the Hermes API Server docs (Runs API section).
public struct HermesRunRequest: Encodable, Sendable {
    public var input: String
    public var sessionId: String?
    public var instructions: String?
    public var conversationHistory: [HermesChatRequestMessage]?
    public var previousResponseId: String?

    public init(
        input: String,
        sessionId: String? = nil,
        instructions: String? = nil,
        conversationHistory: [HermesChatRequestMessage]? = nil,
        previousResponseId: String? = nil
    ) {
        self.input = input
        self.sessionId = sessionId?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.instructions = instructions?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.conversationHistory = (conversationHistory?.isEmpty ?? true) ? nil : conversationHistory
        self.previousResponseId = previousResponseId?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }

    private enum CodingKeys: String, CodingKey {
        case input
        case sessionId = "session_id"
        case instructions
        case conversationHistory = "conversation_history"
        case previousResponseId = "previous_response_id"
    }
}

/// Response from `POST /v1/runs`.
public struct HermesRunSubmitResponse: Decodable, Equatable, Sendable {
    public let runId: String
    public let status: String?

    public init(runId: String, status: String? = nil) {
        self.runId = runId
        self.status = status
    }

    private enum CodingKeys: String, CodingKey {
        case runId = "run_id"
        case status
    }
}

/// Response from `GET /v1/runs/{run_id}` — the authoritative run state used to reconcile
/// the final answer after any stream drop.
public struct HermesRunStatusResponse: Decodable, Equatable, Sendable {
    public let runId: String?
    public let status: String?
    public let output: String?
    public let sessionId: String?

    public init(runId: String? = nil, status: String? = nil, output: String? = nil, sessionId: String? = nil) {
        self.runId = runId
        self.status = status
        self.output = output
        self.sessionId = sessionId
    }

    private enum CodingKeys: String, CodingKey {
        case runId = "run_id"
        case status
        case output
        case sessionId = "session_id"
    }

    public var normalizedStatus: String {
        (status ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    public var isTerminal: Bool {
        ["completed", "failed", "cancelled", "canceled", "error"].contains(normalizedStatus)
    }

    public var isFailed: Bool {
        normalizedStatus == "failed" || normalizedStatus == "error"
    }

    public var trimmedOutput: String {
        (output ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// A single parsed event from the `GET /v1/runs/{run_id}/events` SSE stream.
///
/// The exact event JSON is not fully specified by the docs, so parsing is best-effort
/// (correctness is guaranteed by reconciling the final text via `GET /{run_id}`).
public struct HermesRunEvent: Equatable, Sendable {
    public let textDelta: String?
    public let terminalStatus: String?

    public init(textDelta: String?, terminalStatus: String?) {
        self.textDelta = textDelta
        self.terminalStatus = terminalStatus
    }

    public var isEmpty: Bool {
        textDelta == nil && terminalStatus == nil
    }

    /// Parse one raw SSE line. Returns nil for lines carrying no usable delta or lifecycle
    /// signal (e.g. `event:` type lines, comments, empty keep-alives).
    public static func parse(fromLine line: String) -> HermesRunEvent? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        // SSE `event:` lines carry only the type; the payload arrives on the paired `data:` line.
        guard !trimmed.hasPrefix("event:"), !trimmed.hasPrefix(":") else { return nil }

        let payload: String
        if trimmed.hasPrefix("data:") {
            payload = String(trimmed.dropFirst(5)).trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            payload = trimmed
        }
        guard !payload.isEmpty else { return nil }
        if payload == "[DONE]" {
            return HermesRunEvent(textDelta: nil, terminalStatus: "completed")
        }

        guard let data = payload.data(using: .utf8),
              let raw = try? JSONDecoder().decode(RawRunEvent.self, from: data) else {
            return nil
        }
        let delta = raw.extractedTextDelta
        let terminal = raw.extractedTerminalStatus
        guard delta != nil || terminal != nil else { return nil }
        return HermesRunEvent(textDelta: delta, terminalStatus: terminal)
    }

    private struct RawRunEvent: Decodable {
        let type: String?
        let status: String?
        let delta: FlexibleText?
        let text: String?
        let content: FlexibleText?
        let output: FlexibleText?
        let choices: [Choice]?

        struct Choice: Decodable {
            struct Delta: Decodable { let content: String? }
            let delta: Delta?
            let text: String?
            let finishReason: String?

            enum CodingKeys: String, CodingKey {
                case delta
                case text
                case finishReason = "finish_reason"
            }
        }

        var extractedTextDelta: String? {
            if let value = delta?.value, !value.isEmpty { return value }
            if let choiceDelta = choices?
                .compactMap({ $0.delta?.content ?? $0.text })
                .first(where: { !$0.isEmpty }) {
                return choiceDelta
            }
            // Only treat top-level text/content as an incremental delta when the event type
            // looks like a delta, so a terminal aggregate isn't double-counted as a delta.
            if let type = type?.lowercased(), type.contains("delta") {
                if let text, !text.isEmpty { return text }
                if let value = content?.value, !value.isEmpty { return value }
            }
            return nil
        }

        var extractedTerminalStatus: String? {
            if let status = status?.lowercased(),
               ["completed", "failed", "cancelled", "canceled", "error"].contains(status) {
                return status == "canceled" ? "cancelled" : status
            }
            if let type = type?.lowercased() {
                if type.contains("completed") { return "completed" }
                if type.contains("failed") || type.contains("error") { return "failed" }
                if type.contains("cancel") { return "cancelled" }
            }
            if choices?.contains(where: { ($0.finishReason?.isEmpty == false) }) == true {
                return "completed"
            }
            return nil
        }
    }

    /// Decodes a value that the server may express either as a plain string or as an object
    /// wrapping the text under `content`/`text`.
    private struct FlexibleText: Decodable {
        let value: String?

        init(from decoder: Decoder) throws {
            if let single = try? decoder.singleValueContainer(), let string = try? single.decode(String.self) {
                value = string
            } else if let container = try? decoder.container(keyedBy: CodingKeys.self) {
                if let content = try? container.decodeIfPresent(String.self, forKey: .content) {
                    value = content
                } else if let text = try? container.decodeIfPresent(String.self, forKey: .text) {
                    value = text
                } else {
                    value = nil
                }
            } else {
                value = nil
            }
        }

        private enum CodingKeys: String, CodingKey {
            case content
            case text
        }
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
