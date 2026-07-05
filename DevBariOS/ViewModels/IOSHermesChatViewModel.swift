import Combine
import DevBarCore
import Foundation
import SwiftData
import UIKit

typealias IOSChatBotProvider = ChatBotProviderKind

struct IOSHermesImageAttachment: Equatable {
    let id: UUID
    var displayName: String
    var dataURL: String

    init(id: UUID = UUID(), displayName: String, dataURL: String) {
        self.id = id
        self.displayName = displayName
        self.dataURL = dataURL
    }

    var persistenceMarker: String {
        "[DevBarHermesImageAttachment: \(Self.encode(displayName)) \(Self.encode(dataURL))]"
    }

    static func content(_ prompt: String, appending attachments: [IOSHermesImageAttachment]) -> String {
        guard !attachments.isEmpty else { return prompt }
        let markers = attachments.map(\.persistenceMarker).joined(separator: "\n")
        return [prompt, markers]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    static func displayContent(from content: String) -> String {
        content
            .components(separatedBy: .newlines)
            .filter { imageAttachmentMarker(from: $0) == nil }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func persistedAttachments(in content: String) -> [IOSHermesImageAttachment] {
        content
            .components(separatedBy: .newlines)
            .compactMap(imageAttachmentMarker)
    }

    private static func imageAttachmentMarker(from line: String) -> IOSHermesImageAttachment? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefix = "[DevBarHermesImageAttachment: "
        guard trimmed.hasPrefix(prefix), trimmed.hasSuffix("]") else { return nil }
        let body = String(trimmed.dropFirst(prefix.count).dropLast())
        let parts = body.split(separator: " ", maxSplits: 1).map(String.init)
        guard parts.count == 2,
              let name = decode(parts[0]),
              let dataURL = decode(parts[1]) else {
            return nil
        }
        return IOSHermesImageAttachment(displayName: name, dataURL: dataURL)
    }

    private static func encode(_ value: String) -> String {
        Data(value.utf8).base64EncodedString()
    }

    private static func decode(_ value: String) -> String? {
        guard let data = Data(base64Encoded: value) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

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
    private var lastImageAttachments: [IOSHermesImageAttachment] = []

    init(
        client: HermesAPIClient = HermesAPIClient(diagnostics: DiagnosticLogger.shared),
        conversation: IOSHermesConversation? = nil,
        prefetchedMessages: [Message]? = nil,
        settings: HermesSettings? = nil,
        apiKey: String? = nil,
        provider: IOSChatBotProvider = .hermes
    ) {
        self.client = client
        if let settings, let apiKey {
            configure(settings: settings, apiKey: apiKey, provider: provider)
        } else {
            self.provider = provider
        }
        if let conversation {
            load(conversation: conversation, prefetchedMessages: prefetchedMessages)
        }
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
        load(conversation: conversation, prefetchedMessages: nil)
    }

    func load(conversation: IOSHermesConversation?, prefetchedMessages: [Message]?) {
        let start = CFAbsoluteTimeGetCurrent()
        self.conversation = conversation
        guard let conversation else {
            messages = []
            debugLog("load empty conversation")
            return
        }

        messages = prefetchedMessages ?? Self.messageSnapshot(in: conversation)
        debugLog(
            "load conversation localId=\(conversation.id.uuidString) remoteSessionId=\(conversation.remoteSessionId ?? "-") localMessages=\(messages.count) prefetched=\(prefetchedMessages != nil) chars=\(messages.reduce(0) { $0 + $1.content.count }) dt=\(elapsedMilliseconds(since: start))ms"
        )
    }

    func sendDraft(
        modelContext: ModelContext,
        title: String,
        imageAttachments: [IOSHermesImageAttachment] = []
    ) -> IOSHermesConversation? {
        let prompt = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return conversation }
        draft = ""
        send(prompt, imageAttachments: imageAttachments, modelContext: modelContext, title: title)
        return conversation
    }

    func retryLastPrompt(modelContext: ModelContext, title: String) {
        guard let lastPrompt else { return }
        send(lastPrompt, imageAttachments: lastImageAttachments, modelContext: modelContext, title: title)
    }

    func cancel() {
        activeTask?.cancel()
        activeTask = nil
        status = .idle
    }

    private func send(
        _ prompt: String,
        imageAttachments: [IOSHermesImageAttachment],
        modelContext: ModelContext,
        title: String
    ) {
        guard isConfigured else {
            status = .failed(String(localized: "ios_hermes_missing_config_detail"))
            return
        }

        activeTask?.cancel()
        lastPrompt = prompt
        lastImageAttachments = imageAttachments
        status = isStreamingEnabled ? .streaming : .sending

        let conversation = ensureConversation(modelContext: modelContext)
        let persistedPrompt = IOSHermesImageAttachment.content(prompt, appending: imageAttachments)
        let userMessage = persistMessage(
            role: .user,
            content: persistedPrompt,
            contentFormat: .plain,
            conversation: conversation,
            modelContext: modelContext
        )
        messages.append(userMessage)
        var requestMessages = messages.compactMap { message -> HermesChatRequestMessage? in
            let visibleContent = IOSHermesImageAttachment.displayContent(from: message.content)
            guard !visibleContent.isEmpty else { return nil }
            return HermesChatRequestMessage(role: message.role, content: visibleContent)
        }
        if !imageAttachments.isEmpty,
           let userMessageIndex = requestMessages.indices.last(where: { requestMessages[$0].role == .user }) {
            requestMessages[userMessageIndex].content = .parts(
                [HermesChatContentPart.text(prompt)] +
                imageAttachments.map { HermesChatContentPart.imageURL($0.dataURL) }
            )
        }

        activeTask = Task {
            await self.performSend(
                prompt: prompt,
                conversationID: conversation.id,
                requestMessages: requestMessages,
                hasImageAttachments: !imageAttachments.isEmpty,
                modelContext: modelContext,
                title: title
            )
        }
    }

    private func performSend(
        prompt: String,
        conversationID: UUID,
        requestMessages: [HermesChatRequestMessage],
        hasImageAttachments: Bool,
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
            if !hasImageAttachments, await supportsResponsesAPI() {
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
        conversation.recordMessage(role: role, content: content, at: now)
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

extension IOSHermesChatViewModel {
    func debugLog(_ message: String) {
        IOSDebugLogger.log("HermesChat", message)
    }

    func elapsedMilliseconds(since start: CFAbsoluteTime) -> Int {
        Int((CFAbsoluteTimeGetCurrent() - start) * 1_000)
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

    static func messageSnapshot(in conversation: IOSHermesConversation) -> [IOSHermesChatViewModel.Message] {
        let start = CFAbsoluteTimeGetCurrent()
        let snapshot = orderedMessages(in: conversation).map {
            Message(
                id: $0.id,
                role: $0.role,
                content: $0.content,
                createdAt: $0.createdAt,
                isComplete: $0.isComplete
            )
        }
        let characterCount = snapshot.reduce(0) { $0 + $1.content.count }
        IOSDebugLogger.log(
            "HermesChat",
            "snapshot localId=\(conversation.id.uuidString) messages=\(snapshot.count) chars=\(characterCount) dt=\(Int((CFAbsoluteTimeGetCurrent() - start) * 1_000))ms"
        )
        return snapshot
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
