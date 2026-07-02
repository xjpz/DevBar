import Combine
import DevBarCore
import Foundation
import SwiftData
import UIKit

typealias IOSChatBotProvider = ChatBotProviderKind

extension ChatBotProviderKind {
    var title: String {
        "Hermes"
    }

    var toolTitle: String {
        "Hermes Chat"
    }

    var toolSubtitle: String {
        "OpenAI-compatible API"
    }
}

@MainActor
final class IOSHermesChatViewModel: ObservableObject {
    enum Status: Equatable {
        case idle
        case sending
        case streaming
        case failed(String)
    }

    struct Message: Identifiable, Equatable {
        let id: UUID
        var role: HermesChatRole
        var content: String
        var createdAt: Date
        var isComplete: Bool

        init(
            id: UUID = UUID(),
            role: HermesChatRole,
            content: String,
            createdAt: Date = Date(),
            isComplete: Bool = true
        ) {
            self.id = id
            self.role = role
            self.content = content
            self.createdAt = createdAt
            self.isComplete = isComplete
        }
    }

    @Published private(set) var messages: [Message] = []
    @Published private(set) var status: Status = .idle
    @Published private(set) var conversation: IOSHermesConversation?
    @Published var draft = ""

    private let client: HermesAPIClient
    private var baseURL = ""
    private var apiKey = ""
    private var hermesModel = ""
    private var isStreamingEnabled = true
    private var provider: IOSChatBotProvider = .hermes
    private var cachedCapabilities: HermesAPIServerCapabilities?
    private var activeTask: Task<Void, Never>?
    private var lastPrompt: String?

    init(client: HermesAPIClient = HermesAPIClient()) {
        self.client = client
    }

    var isConfigured: Bool {
        HermesAPIClient.chatURL(from: baseURL) != nil && !apiKey.isEmpty
    }

    var canSend: Bool {
        isConfigured && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isBusy
    }

    var isBusy: Bool {
        switch status {
        case .sending, .streaming:
            return true
        case .idle, .failed:
            return false
        }
    }

    func configure(
        settings: HermesSettings,
        apiKey: String,
        provider: IOSChatBotProvider
    ) {
        if baseURL != settings.apiBaseURL || self.apiKey != apiKey {
            cachedCapabilities = nil
        }
        baseURL = settings.apiBaseURL
        self.apiKey = apiKey
        hermesModel = settings.hermesModel
        isStreamingEnabled = settings.isStreamingEnabled
        self.provider = provider
    }

    func load(conversation: IOSHermesConversation?) {
        self.conversation = conversation
        guard let conversation else {
            messages = []
            debugLog("load empty conversation")
            return
        }

        messages = Self.orderedMessages(in: conversation).map {
            Message(
                id: $0.id,
                role: $0.role,
                content: $0.content,
                createdAt: $0.createdAt,
                isComplete: $0.isComplete
            )
        }
        debugLog("load conversation localId=\(conversation.id.uuidString) remoteSessionId=\(conversation.remoteSessionId ?? "-") localMessages=\(messages.count)")
    }

    func sendDraft(modelContext: ModelContext, title: String) -> IOSHermesConversation? {
        let prompt = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return conversation }
        draft = ""
        send(prompt, modelContext: modelContext, title: title)
        return conversation
    }

    func retryLastPrompt(modelContext: ModelContext, title: String) {
        guard let lastPrompt else { return }
        send(lastPrompt, modelContext: modelContext, title: title)
    }

    func cancel() {
        activeTask?.cancel()
        activeTask = nil
        status = .idle
    }

    private func send(_ prompt: String, modelContext: ModelContext, title: String) {
        guard isConfigured else {
            status = .failed(String(localized: "ios_hermes_missing_config_detail"))
            return
        }

        activeTask?.cancel()
        lastPrompt = prompt
        status = isStreamingEnabled ? .streaming : .sending

        let conversation = ensureConversation(modelContext: modelContext)
        let userMessage = persistMessage(
            role: .user,
            content: prompt,
            contentFormat: .plain,
            conversation: conversation,
            modelContext: modelContext
        )
        messages.append(userMessage)
        let requestMessages = messages
            .filter { !$0.content.isEmpty }
            .map { HermesChatRequestMessage(role: $0.role, content: $0.content) }

        activeTask = Task {
            await self.performSend(
                prompt: prompt,
                conversationID: conversation.id,
                requestMessages: requestMessages,
                modelContext: modelContext,
                title: title
            )
        }
    }

    private func performSend(
        prompt: String,
        conversationID: UUID,
        requestMessages: [HermesChatRequestMessage],
        modelContext: ModelContext,
        title: String
    ) async {
        let backgroundTask = IOSHermesBackgroundTask(name: "Hermes Chat")
        defer {
            backgroundTask.end()
            activeTask = nil
        }

        do {
            var assistantContent = ""
            if await supportsResponsesAPI() {
                status = .sending
                assistantContent = try await client.sendResponse(
                    baseURL: baseURL,
                    apiKey: apiKey,
                    input: prompt,
                    model: hermesModel,
                    conversation: Self.hermesConversationKey(for: conversationID)
                )
            } else if isStreamingEnabled {
                status = .streaming
                for try await delta in client.streamMessage(
                    baseURL: baseURL,
                    apiKey: apiKey,
                    messages: requestMessages,
                    model: hermesModel
                ) {
                    guard !Task.isCancelled else { return }
                    assistantContent += delta
                }
            } else {
                status = .sending
                assistantContent = try await client.sendMessage(
                    baseURL: baseURL,
                    apiKey: apiKey,
                    messages: requestMessages,
                    model: hermesModel,
                    stream: false
                )
            }

            let trimmedContent = assistantContent.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedContent.isEmpty {
                guard let conversation else {
                    status = .idle
                    return
                }
                let assistantMessage = persistMessage(
                    role: .assistant,
                    content: trimmedContent,
                    contentFormat: IOSHermesMessageContentFormat.detected(for: trimmedContent),
                    conversation: conversation,
                    modelContext: modelContext
                )
                messages.append(assistantMessage)
            }
            status = .idle
        } catch is CancellationError {
            status = .idle
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    private func supportsResponsesAPI() async -> Bool {
        if let cachedCapabilities {
            return cachedCapabilities.features.responsesAPI
        }
        do {
            let capabilities = try await client.fetchCapabilities(baseURL: baseURL, apiKey: apiKey)
            cachedCapabilities = capabilities
            return capabilities.features.responsesAPI
        } catch {
            debugLog("capabilities fallback to chat_completions error=\(error.localizedDescription)")
            return false
        }
    }

    private func ensureConversation(modelContext: ModelContext) -> IOSHermesConversation {
        if let conversation {
            if conversation.providerRawValue == nil {
                conversation.chatProvider = provider
                try? modelContext.save()
            }
            return conversation
        }

        let newConversation = IOSHermesConversation(provider: provider)
        modelContext.insert(newConversation)
        conversation = newConversation
        try? modelContext.save()
        return newConversation
    }

    private func persistMessage(
        role: HermesChatRole,
        content: String,
        contentFormat: IOSHermesMessageContentFormat,
        conversation: IOSHermesConversation,
        modelContext: ModelContext
    ) -> Message {
        let sortIndex = Self.nextSortIndex(in: conversation)
        let now = Self.nextCreatedAt(in: conversation)
        let persisted = IOSHermesMessage(
            role: role,
            content: content,
            contentFormat: contentFormat,
            isComplete: true,
            sortIndex: sortIndex,
            createdAt: now,
            completedAt: now,
            conversation: nil
        )
        modelContext.insert(persisted)
        conversation.messages.append(persisted)
        conversation.recordMessage(content: content, at: now)
        try? modelContext.save()

        return Message(
            id: persisted.id,
            role: role,
            content: content,
            createdAt: now,
            isComplete: true
        )
    }
}

private extension IOSHermesChatViewModel {
    func debugLog(_ message: String) {
        print("[DevBar:iOS:HermesChat] \(message)")
    }

    func redacted(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "nil" }
        return "set(...\(trimmed.suffix(6)))"
    }

    static func orderedMessages(in conversation: IOSHermesConversation) -> [IOSHermesMessage] {
        conversation.messages.sorted { lhs, rhs in
            let lhsSortIndex = lhs.sortIndex ?? Int.max
            let rhsSortIndex = rhs.sortIndex ?? Int.max
            if lhsSortIndex != rhsSortIndex {
                return lhsSortIndex < rhsSortIndex
            }
            if lhs.createdAt != rhs.createdAt {
                return lhs.createdAt < rhs.createdAt
            }
            if lhs.completedAt != rhs.completedAt {
                return (lhs.completedAt ?? .distantFuture) < (rhs.completedAt ?? .distantFuture)
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    static func nextSortIndex(in conversation: IOSHermesConversation) -> Int {
        let maxSortIndex = conversation.messages.compactMap(\.sortIndex).max()
        return maxSortIndex.map { $0 + 1 } ?? conversation.messages.count
    }

    static func nextCreatedAt(in conversation: IOSHermesConversation) -> Date {
        let now = Date()
        guard let latest = conversation.messages.map(\.createdAt).max(),
              latest >= now else {
            return now
        }
        return latest.addingTimeInterval(0.001)
    }

    static func hermesConversationKey(for id: UUID) -> String {
        "devbar-ios-\(id.uuidString.lowercased())"
    }
}

private final class IOSHermesBackgroundTask {
    private var identifier: UIBackgroundTaskIdentifier = .invalid

    init(name: String) {
        identifier = UIApplication.shared.beginBackgroundTask(withName: name) { [weak self] in
            self?.end()
        }
    }

    func end() {
        guard identifier != .invalid else { return }
        UIApplication.shared.endBackgroundTask(identifier)
        identifier = .invalid
    }

    deinit {
        end()
    }
}
