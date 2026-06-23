import Combine
import DevBarCore
import Foundation

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

    func sendDraft() {
        let prompt = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return }
        draft = ""
        send(prompt)
    }

    func retryLastPrompt() {
        guard let lastPrompt else { return }
        send(lastPrompt)
    }

    func cancel() {
        activeTask?.cancel()
        activeTask = nil
        if let index = messages.lastIndex(where: { $0.role == .assistant && !$0.isComplete }) {
            messages[index].isComplete = true
        }
        status = .idle
    }

    private func send(_ prompt: String) {
        guard isConfigured else {
            status = .failed(String(localized: "ios_hermes_missing_config_detail"))
            return
        }

        activeTask?.cancel()
        lastPrompt = prompt

        let userMessage = Message(role: .user, content: prompt)
        let assistantMessage = Message(role: .assistant, content: "", isComplete: false)
        messages.append(userMessage)
        messages.append(assistantMessage)
        let assistantID = assistantMessage.id

        activeTask = Task { [weak self] in
            guard let self else { return }
            await self.performSend(assistantID: assistantID)
        }
    }

    private func performSend(assistantID: UUID) async {
        let requestMessages = messages
            .filter { $0.id != assistantID && !$0.content.isEmpty }
            .map { HermesChatRequestMessage(role: $0.role, content: $0.content) }

        do {
            if isStreamingEnabled {
                status = .streaming
                for try await delta in client.streamMessage(
                    baseURL: baseURL,
                    apiKey: apiKey,
                    messages: requestMessages
                ) {
                    guard !Task.isCancelled else { return }
                    append(delta, toAssistantMessage: assistantID)
                }
            } else {
                status = .sending
                let content = try await client.sendMessage(
                    baseURL: baseURL,
                    apiKey: apiKey,
                    messages: requestMessages,
                    stream: false
                )
                replaceAssistantMessage(assistantID, content: content)
            }

            completeAssistantMessage(assistantID)
            status = .idle
        } catch is CancellationError {
            completeAssistantMessage(assistantID)
            status = .idle
        } catch {
            replaceAssistantMessage(assistantID, content: error.localizedDescription)
            completeAssistantMessage(assistantID)
            status = .failed(error.localizedDescription)
        }
    }

    private func append(_ delta: String, toAssistantMessage id: UUID) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        messages[index].content += delta
    }

    private func replaceAssistantMessage(_ id: UUID, content: String) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        messages[index].content = content
    }

    private func completeAssistantMessage(_ id: UUID) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        messages[index].isComplete = true
    }
}
