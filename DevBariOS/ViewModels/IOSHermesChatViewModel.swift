import Combine
import DevBarCore
import Foundation
import SwiftData

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
    private var isStreamingEnabled = true
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

    func configure(settings: HermesSettings, apiKey: String) {
        baseURL = settings.apiBaseURL
        self.apiKey = apiKey
        isStreamingEnabled = settings.isStreamingEnabled
    }

    func load(conversation: IOSHermesConversation?) {
        self.conversation = conversation
        guard let conversation else {
            messages = []
            return
        }

        messages = conversation.messages
            .sorted { $0.createdAt < $1.createdAt }
            .map {
                Message(
                    id: $0.id,
                    role: $0.role,
                    content: $0.content,
                    createdAt: $0.createdAt,
                    isComplete: $0.isComplete
                )
            }
    }

    func sendDraft(modelContext: ModelContext, draftRemark: String) -> IOSHermesConversation? {
        let prompt = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return conversation }
        draft = ""
        send(prompt, modelContext: modelContext, draftRemark: draftRemark)
        return conversation
    }

    func retryLastPrompt(modelContext: ModelContext, draftRemark: String) {
        guard let lastPrompt else { return }
        send(lastPrompt, modelContext: modelContext, draftRemark: draftRemark)
    }

    func cancel() {
        activeTask?.cancel()
        activeTask = nil
        status = .idle
    }

    func updateRemark(_ remark: String, modelContext: ModelContext) {
        guard let conversation else { return }
        conversation.remark = remark
        conversation.updatedAt = Date()
        try? modelContext.save()
        objectWillChange.send()
    }

    private func send(_ prompt: String, modelContext: ModelContext, draftRemark: String) {
        guard isConfigured else {
            status = .failed(String(localized: "ios_hermes_missing_config_detail"))
            return
        }

        activeTask?.cancel()
        lastPrompt = prompt
        status = isStreamingEnabled ? .streaming : .sending

        let conversation = ensureConversation(modelContext: modelContext, draftRemark: draftRemark)
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

        activeTask = Task { [weak self] in
            guard let self else { return }
            await self.performSend(requestMessages: requestMessages, modelContext: modelContext)
        }
    }

    private func performSend(requestMessages: [HermesChatRequestMessage], modelContext: ModelContext) async {
        do {
            var assistantContent = ""
            if isStreamingEnabled {
                status = .streaming
                for try await delta in client.streamMessage(
                    baseURL: baseURL,
                    apiKey: apiKey,
                    messages: requestMessages
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

    private func ensureConversation(modelContext: ModelContext, draftRemark: String) -> IOSHermesConversation {
        if let conversation {
            return conversation
        }

        let trimmedRemark = draftRemark.trimmingCharacters(in: .whitespacesAndNewlines)
        let newConversation = IOSHermesConversation(remark: trimmedRemark)
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
        let now = Date()
        let persisted = IOSHermesMessage(
            role: role,
            content: content,
            contentFormat: contentFormat,
            isComplete: true,
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
