import Foundation
import Combine

// MARK: - Agent State

enum AgentState: String, Codable {
    case idle
    case running
    case waitingApproval
    case waitingInput
    case loginRequired
    case stalled
    case completed
    case failed

    var displayName: String {
        switch self {
        case .idle: return "空闲"
        case .running: return "运行中"
        case .waitingApproval: return "等待授权"
        case .waitingInput: return "等待输入"
        case .loginRequired: return "需要登录"
        case .stalled: return "已卡住"
        case .completed: return "已完成"
        case .failed: return "失败"
        }
    }
}

// MARK: - Agent Session

struct AgentSession: Codable, Identifiable {
    let id: String
    let source: AgentSource
    var projectName: String?
    var cwd: String?

    var state: AgentState
    var startedAt: Date
    var updatedAt: Date
    var waitingSince: Date?

    var lastEvent: AgentEvent?
    var recentEvents: [AgentEvent]

    init(
        id: String = UUID().uuidString,
        source: AgentSource,
        projectName: String? = nil,
        cwd: String? = nil,
        state: AgentState = .idle,
        startedAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.source = source
        self.projectName = projectName
        self.cwd = cwd
        self.state = state
        self.startedAt = startedAt
        self.updatedAt = updatedAt
        self.recentEvents = []
    }

    var isWaiting: Bool {
        state == .waitingApproval || state == .waitingInput || state == .loginRequired
    }

    var waitingDuration: TimeInterval? {
        guard let waitingSince = waitingSince else { return nil }
        return Date().timeIntervalSince(waitingSince)
    }

    var formattedWaitingTime: String? {
        guard let duration = waitingDuration else { return nil }
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

// MARK: - Agent Session Store

@MainActor
class AgentSessionStore: ObservableObject {
    @Published var sessions: [String: AgentSession] = [:]

    private let storageKey = "DevBarAgentWatcherSessions"
    private let maxRecentEvents = 50

    init() {
        loadSessions()
    }

    // MARK: - Session Management

    func getOrCreateSession(for source: AgentSource, sessionId: String, cwd: String? = nil) -> AgentSession {
        if var session = sessions[sessionId] {
            session.updatedAt = Date()
            if let cwd = cwd {
                session.cwd = cwd
                session.projectName = extractProjectName(from: cwd)
            }
            sessions[sessionId] = session
            return session
        }

        var newSession = AgentSession(
            id: sessionId,
            source: source,
            projectName: cwd.flatMap { extractProjectName(from: $0) },
            cwd: cwd,
            state: .running
        )
        newSession.updatedAt = Date()
        sessions[sessionId] = newSession
        saveSessions()
        return newSession
    }

    func updateSession(_ sessionId: String, with event: AgentEvent) {
        guard var session = sessions[sessionId] else { return }

        session.lastEvent = event
        session.updatedAt = Date()

        // 更新状态
        let newState = determineState(from: event, currentState: session.state)
        if newState != session.state {
            session.state = newState

            // 如果进入等待状态，记录等待开始时间
            if newState == .waitingApproval || newState == .waitingInput || newState == .loginRequired {
                session.waitingSince = Date()
            } else {
                session.waitingSince = nil
            }
        }

        // 添加到最近事件
        session.recentEvents.insert(event, at: 0)
        if session.recentEvents.count > maxRecentEvents {
            session.recentEvents = Array(session.recentEvents.prefix(maxRecentEvents))
        }

        sessions[sessionId] = session
        saveSessions()
    }

    func resolveSession(_ sessionId: String) {
        guard var session = sessions[sessionId] else { return }
        session.state = .completed
        session.waitingSince = nil
        session.updatedAt = Date()
        sessions[sessionId] = session
        saveSessions()
    }

    func removeSession(_ sessionId: String) {
        sessions.removeValue(forKey: sessionId)
        saveSessions()
    }

    func removeStaleSessions(olderThan interval: TimeInterval = 3600) {
        let cutoff = Date().addingTimeInterval(-interval)
        sessions = sessions.filter { _, session in
            session.updatedAt > cutoff
        }
        saveSessions()
    }

    // MARK: - Queries

    var activeSessions: [AgentSession] {
        sessions.values.filter { $0.state != .completed && $0.state != .idle }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    var waitingSessions: [AgentSession] {
        sessions.values.filter { $0.isWaiting }
            .sorted { ($0.waitingSince ?? $0.updatedAt) > ($1.waitingSince ?? $1.updatedAt) }
    }

    var hasWaitingSessions: Bool {
        sessions.values.contains { $0.isWaiting }
    }

    // MARK: - State Determination

    private func determineState(from event: AgentEvent, currentState: AgentState) -> AgentState {
        switch event.eventType {
        case .permissionRequest, .approvalRequired:
            return .waitingApproval
        case .commandConfirmationRequired, .filePermissionRequired,
             .networkPermissionRequired, .mcpPermissionRequired:
            return .waitingApproval
        case .waitingUserInput:
            return .waitingInput
        case .loginRequired:
            return .loginRequired
        case .taskCompleted:
            return .completed
        case .taskFailed:
            return .failed
        case .sessionStart:
            return .running
        case .stop:
            return currentState == .running ? .completed : currentState
        default:
            return currentState
        }
    }

    // MARK: - Helper

    private func extractProjectName(from path: String) -> String {
        let components = path.split(separator: "/")
        // 尝试找到 .git 目录的父目录
        if let gitIndex = components.lastIndex(of: ".git") {
            let projectIndex = components.index(before: gitIndex)
            if projectIndex >= components.startIndex {
                return String(components[projectIndex])
            }
        }
        // 否则返回最后一级目录名
        return components.last.map(String.init) ?? path
    }

    // MARK: - Persistence

    private func saveSessions() {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(sessions)
            UserDefaults.standard.set(data, forKey: storageKey)
        } catch {
            print("[AgentSessionStore] Failed to save sessions: \(error)")
        }
    }

    private func loadSessions() {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            sessions = try decoder.decode([String: AgentSession].self, from: data)
        } catch {
            print("[AgentSessionStore] Failed to load sessions: \(error)")
        }
    }
}
