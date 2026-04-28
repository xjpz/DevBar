// WeChatConversationStore.swift
// DevBar

import Foundation

actor WeChatConversationStore {

    struct ChatMessage: Sendable {
        let role: Role
        let content: String
        let timestamp: Date

        enum Role: String, Sendable {
            case user
            case assistant
        }
    }

    struct Session: Sendable {
        var acpSessionID: String?
        var cliSessionID: String?
        var httpHistory: [ChatMessage]
        var lastActivity: Date
    }

    private var sessions: [String: Session] = [:]
    private let maxHistory: Int
    private let sessionTTL: TimeInterval = 3600 // 1 hour

    init(maxHistory: Int = 100) {
        self.maxHistory = maxHistory
    }

    // MARK: - Access

    func getOrCreateSession(userID: String, agentName: String) -> Session {
        let key = key(userID: userID, agentName: agentName)
        cleanupExpired()
        if var existing = sessions[key] {
            existing.lastActivity = Date()
            sessions[key] = existing
            return existing
        }
        let session = Session(
            acpSessionID: nil,
            cliSessionID: nil,
            httpHistory: [],
            lastActivity: Date()
        )
        sessions[key] = session
        return session
    }

    func updateSession(userID: String, agentName: String, _ update: (inout Session) -> Void) {
        let key = key(userID: userID, agentName: agentName)
        guard var session = sessions[key] else { return }
        update(&session)
        session.lastActivity = Date()
        sessions[key] = session
    }

    func clearSession(userID: String, agentName: String) {
        sessions.removeValue(forKey: key(userID: userID, agentName: agentName))
    }

    func clearAllSessions(userID: String) {
        let prefix = "\(userID):"
        sessions = sessions.filter { !$0.key.hasPrefix(prefix) }
    }

    // MARK: - HTTP History Helpers

    func appendHTTPHistory(userID: String, agentName: String, user: String, assistant: String) {
        updateSession(userID: userID, agentName: agentName) { s in
            s.httpHistory.append(ChatMessage(role: .user, content: user, timestamp: Date()))
            s.httpHistory.append(ChatMessage(role: .assistant, content: assistant, timestamp: Date()))
            if s.httpHistory.count > maxHistory * 2 {
                s.httpHistory.removeFirst(s.httpHistory.count - maxHistory * 2)
            }
        }
    }

    // MARK: - Private

    private func key(userID: String, agentName: String) -> String {
        "\(userID):\(agentName)"
    }

    private func cleanupExpired() {
        let cutoff = Date().addingTimeInterval(-sessionTTL)
        sessions = sessions.filter { $0.value.lastActivity > cutoff }
    }
}
