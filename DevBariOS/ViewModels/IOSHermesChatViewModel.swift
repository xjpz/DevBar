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
        /// Stream dropped mid-run; the run is still executing server-side and we're polling to
        /// re-attach. Not a failure — the answer will fill in once the run reaches a terminal state.
        case reconnecting
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

    // Runs API re-attach poll tuning.
    private static let runPollBaseDelay: TimeInterval = 1.5
    private static let runPollMaxDelay: TimeInterval = 5
    /// Upper bound on a single continuous poll session; the persisted `activeRunId` means a later
    /// foreground / reopen resumes anyway, so this only caps one loop's lifetime.
    private static let runReconcileBackstop: TimeInterval = 15 * 60

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
        case .sending, .streaming, .reconnecting:
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

        // If a server-side run is in flight, ask it to stop and finalize the live bubble with
        // whatever partial text we already have so it isn't left dangling as "incomplete".
        if let conversation, let runId = conversation.activeRunId?.trimmingCharacters(in: .whitespacesAndNewlines), !runId.isEmpty {
            let baseURL = self.baseURL
            let apiKey = self.apiKey
            let client = self.client
            Task { try? await client.stopRun(baseURL: baseURL, apiKey: apiKey, runId: runId) }

            if let assistant = conversation.messages.first(where: { $0.runId == runId && !$0.isComplete }) {
                assistant.isComplete = true
                assistant.completedAt = Date()
                markMessageComplete(id: assistant.id)
            }
            conversation.activeRunId = nil
            try? conversation.modelContext?.save()
        }

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
            await self.performTurn(
                prompt: prompt,
                conversation: conversation,
                requestMessages: requestMessages,
                hasImageAttachments: !imageAttachments.isEmpty,
                modelContext: modelContext,
                title: title
            )
        }
    }

    private func performTurn(
        prompt: String,
        conversation: IOSHermesConversation,
        requestMessages: [HermesChatRequestMessage],
        hasImageAttachments: Bool,
        modelContext: ModelContext,
        title: String
    ) async {
        // Prefer the Runs API when the server advertises it and the turn has no images
        // (the runs input is a plain string; images stay on the chat/responses path).
        if !hasImageAttachments, await supportsRunsAPI() {
            await performRun(
                prompt: prompt,
                conversation: conversation,
                requestMessages: requestMessages,
                modelContext: modelContext
            )
        } else {
            await performSend(
                prompt: prompt,
                conversationID: conversation.id,
                requestMessages: requestMessages,
                hasImageAttachments: hasImageAttachments,
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

    private func supportsRunsAPI() async -> Bool {
        if let cachedCapabilities {
            return cachedCapabilities.features.runSubmission && cachedCapabilities.features.runEventsSSE
        }
        do {
            let capabilities = try await client.fetchCapabilities(baseURL: baseURL, apiKey: apiKey)
            cachedCapabilities = capabilities
            return capabilities.features.runSubmission && capabilities.features.runEventsSSE
        } catch {
            debugLog("capabilities fallback (no runs api) error=\(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Runs API turn

    /// Runs a turn through the Hermes Runs API: submit a server-side run, stream token deltas into
    /// a live assistant bubble, and reconcile the authoritative final answer via `GET /{run_id}`.
    /// A dropped stream is non-fatal — the run keeps executing server-side and we poll to re-attach.
    private func performRun(
        prompt: String,
        conversation: IOSHermesConversation,
        requestMessages: [HermesChatRequestMessage],
        modelContext: ModelContext
    ) async {
        let backgroundTask = IOSHermesBackgroundTask(name: "Hermes Chat")
        defer {
            backgroundTask.end()
            activeTask = nil
        }

        status = .sending
        // The last requestMessage is the just-appended user turn; send the rest as prior context.
        let priorHistory = requestMessages.count > 1 ? Array(requestMessages.dropLast()) : []
        let assistant = persistAssistantPlaceholder(conversation: conversation, modelContext: modelContext)
        appendAssistantPlaceholderMessage(id: assistant.id, createdAt: assistant.createdAt)

        do {
            let submit = try await client.submitRun(
                baseURL: baseURL,
                apiKey: apiKey,
                request: HermesRunRequest(
                    input: prompt,
                    sessionId: Self.hermesConversationKey(for: conversation.id),
                    conversationHistory: priorHistory.isEmpty ? nil : priorHistory
                )
            )
            guard !Task.isCancelled else { return }
            let runId = submit.runId.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !runId.isEmpty else { throw APIError.invalidResponse }

            conversation.activeRunId = runId
            assistant.runId = runId
            try? modelContext.save()

            await streamRun(
                runId: runId,
                conversation: conversation,
                assistant: assistant,
                modelContext: modelContext,
                fallbackContent: ""
            )
        } catch is CancellationError {
            // Left in place; cancel() handles finalization.
        } catch {
            // Submission itself failed — no run to reconcile. Drop the empty placeholder.
            removeAssistantPlaceholderIfEmpty(id: assistant.id, conversation: conversation, modelContext: modelContext)
            status = .failed(error.localizedDescription)
        }
    }

    /// Streams the run's events into the live bubble, then reconciles the final answer. Any stream
    /// error (network blip / backgrounding) transitions to `.reconnecting` and polls until terminal.
    private func streamRun(
        runId: String,
        conversation: IOSHermesConversation,
        assistant: IOSHermesMessage,
        modelContext: ModelContext,
        fallbackContent: String
    ) async {
        var accumulated = fallbackContent
        status = .streaming
        do {
            for try await event in client.streamRunEvents(baseURL: baseURL, apiKey: apiKey, runId: runId) {
                guard !Task.isCancelled else { return }
                if let delta = event.textDelta, !delta.isEmpty {
                    accumulated += delta
                    updateStreamingMessage(id: assistant.id, content: accumulated)
                }
            }
            guard !Task.isCancelled else { return }
            // Stream ended (normally or after a terminal event) — reconcile once, without a delay.
            await reconcileUntilTerminal(
                runId: runId,
                conversation: conversation,
                assistant: assistant,
                fallbackContent: accumulated,
                modelContext: modelContext,
                showReconnecting: false
            )
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            // The generation is still running server-side; poll to re-attach instead of failing.
            await reconcileUntilTerminal(
                runId: runId,
                conversation: conversation,
                assistant: assistant,
                fallbackContent: accumulated,
                modelContext: modelContext,
                showReconnecting: true
            )
        }
    }

    /// Polls `GET /{run_id}` with backoff until the run reaches a terminal state, then finalizes the
    /// assistant bubble with the authoritative `output`. `URLSession.waitsForConnectivity` lets each
    /// poll wait out an offline window, so this also covers non-backgrounded network drops.
    private func reconcileUntilTerminal(
        runId: String,
        conversation: IOSHermesConversation,
        assistant: IOSHermesMessage,
        fallbackContent: String,
        modelContext: ModelContext,
        showReconnecting: Bool
    ) async {
        if showReconnecting, status != .reconnecting {
            status = .reconnecting
        }
        let deadline = Date().addingTimeInterval(Self.runReconcileBackstop)
        var attempt = 0
        while !Task.isCancelled {
            do {
                let state = try await client.fetchRunStatus(baseURL: baseURL, apiKey: apiKey, runId: runId)
                guard !Task.isCancelled else { return }
                if state.isTerminal {
                    finalizeRun(
                        state: state,
                        conversation: conversation,
                        assistant: assistant,
                        fallbackContent: fallbackContent,
                        modelContext: modelContext
                    )
                    return
                }
                if status != .reconnecting {
                    status = .reconnecting
                }
            } catch is CancellationError {
                return
            } catch {
                // Transient (offline / server hiccup) — keep polling.
                if status != .reconnecting {
                    status = .reconnecting
                }
            }

            if Date() >= deadline {
                // Give up actively polling, but leave activeRunId + the incomplete bubble intact so
                // a later foreground / conversation reopen resumes via resumeActiveRunIfNeeded().
                debugLog("run reconcile backstop reached runId=\(runId)")
                status = .idle
                return
            }
            attempt += 1
            let delay = min(Self.runPollBaseDelay * pow(1.4, Double(attempt - 1)), Self.runPollMaxDelay)
            try? await Task.sleep(for: .seconds(delay))
        }
    }

    private func finalizeRun(
        state: HermesRunStatusResponse,
        conversation: IOSHermesConversation,
        assistant: IOSHermesMessage,
        fallbackContent: String,
        modelContext: ModelContext
    ) {
        let authoritative = state.trimmedOutput
        let content = authoritative.isEmpty
            ? fallbackContent.trimmingCharacters(in: .whitespacesAndNewlines)
            : authoritative
        let now = Date()

        conversation.activeRunId = nil

        if content.isEmpty {
            // Nothing produced (e.g. an empty cancellation) — drop the placeholder bubble.
            removeAssistantPlaceholderIfEmpty(id: assistant.id, conversation: conversation, modelContext: modelContext)
            status = state.isFailed
                ? .failed(state.status ?? String(localized: "ios_hermes_missing_config_detail"))
                : .idle
            try? modelContext.save()
            return
        }

        assistant.content = content
        assistant.contentFormat = IOSHermesMessageContentFormat.detected(for: content)
        assistant.isComplete = true
        assistant.completedAt = now
        if state.isFailed {
            assistant.errorMessage = state.status
        }
        conversation.recordMessage(role: .assistant, content: content, at: now)
        try? modelContext.save()

        updateStreamingMessage(id: assistant.id, content: content, isComplete: true)
        status = state.isFailed ? .failed(content) : .idle
    }

    /// Re-attach to an in-flight run after reopening a conversation or returning to the foreground.
    func resumeActiveRunIfNeeded(modelContext: ModelContext) {
        guard !isBusy else { return }
        guard isConfigured else { return }
        guard let conversation else { return }
        let runId = (conversation.activeRunId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !runId.isEmpty else { return }

        guard let assistant = conversation.messages.first(where: { $0.runId == runId && !$0.isComplete }) else {
            // Stale marker with no incomplete bubble — clear it.
            conversation.activeRunId = nil
            try? modelContext.save()
            return
        }

        // Make sure the live bubble is present in the published transcript.
        if !messages.contains(where: { $0.id == assistant.id }) {
            appendAssistantPlaceholderMessage(id: assistant.id, createdAt: assistant.createdAt, content: assistant.content)
        }

        status = .reconnecting
        activeTask?.cancel()
        activeTask = Task {
            let backgroundTask = IOSHermesBackgroundTask(name: "Hermes Resume")
            defer {
                backgroundTask.end()
                activeTask = nil
            }
            await self.reconcileUntilTerminal(
                runId: runId,
                conversation: conversation,
                assistant: assistant,
                fallbackContent: assistant.content,
                modelContext: modelContext,
                showReconnecting: true
            )
        }
    }

    // MARK: - Live bubble helpers

    private func persistAssistantPlaceholder(
        conversation: IOSHermesConversation,
        modelContext: ModelContext
    ) -> IOSHermesMessage {
        let sortIndex = Self.nextSortIndex(in: conversation)
        let now = Self.nextCreatedAt(in: conversation)
        let placeholder = IOSHermesMessage(
            role: .assistant,
            content: "",
            contentFormat: .markdown,
            isComplete: false,
            sortIndex: sortIndex,
            createdAt: now,
            completedAt: nil,
            conversation: nil
        )
        modelContext.insert(placeholder)
        conversation.messages.append(placeholder)
        try? modelContext.save()
        return placeholder
    }

    private func appendAssistantPlaceholderMessage(id: UUID, createdAt: Date, content: String = "") {
        guard !messages.contains(where: { $0.id == id }) else { return }
        messages.append(
            Message(id: id, role: .assistant, content: content, createdAt: createdAt, isComplete: false)
        )
    }

    private func updateStreamingMessage(id: UUID, content: String, isComplete: Bool = false) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        messages[index].content = content
        messages[index].isComplete = isComplete
    }

    private func markMessageComplete(id: UUID) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        messages[index].isComplete = true
    }

    private func removeAssistantPlaceholderIfEmpty(
        id: UUID,
        conversation: IOSHermesConversation,
        modelContext: ModelContext
    ) {
        messages.removeAll { $0.id == id && $0.content.isEmpty }
        if let persisted = conversation.messages.first(where: { $0.id == id }),
           persisted.content.isEmpty {
            conversation.messages.removeAll { $0.id == id }
            modelContext.delete(persisted)
            try? modelContext.save()
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
