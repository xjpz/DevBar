import Foundation
import Combine
import UserNotifications

// MARK: - Agent Watcher Service

@MainActor
class AgentWatcherService: ObservableObject {
    static let shared = AgentWatcherService()

    // MARK: - Properties

    let sessionStore = AgentSessionStore()
    private var httpServer: LocalHTTPServer?
    private var claudeHandler: ClaudeHookHandler?
    private var codexHandler: CodexHookHandler?

    @Published var isEnabled = true
    @Published var isServerRunning = false
    @Published var lastError: String?

    private let serverPort: UInt16 = 49321
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    private init() {
        setupHandlers()
        setupNotifications()
    }

    private func setupHandlers() {
        claudeHandler = ClaudeHookHandler(sessionStore: sessionStore)
        codexHandler = CodexHookHandler(sessionStore: sessionStore)
    }

    private func setupNotifications() {
        // 监听会话变化，发送通知
        sessionStore.$sessions
            .receive(on: DispatchQueue.main)
            .sink { [weak self] sessions in
                self?.handleSessionChanges(sessions)
            }
            .store(in: &cancellables)
    }

    // MARK: - Server Management

    func startServer() {
        guard !isServerRunning else { return }

        httpServer = LocalHTTPServer(port: serverPort)
        registerRoutes()

        do {
            try httpServer?.start()
            isServerRunning = true
            lastError = nil
            print("[AgentWatcherService] Server started on port \(serverPort)")
        } catch {
            lastError = "Failed to start server: \(error.localizedDescription)"
            print("[AgentWatcherService] \(lastError!)")
        }
    }

    func stopServer() {
        httpServer?.stop()
        httpServer = nil
        isServerRunning = false
        print("[AgentWatcherService] Server stopped")
    }

    // MARK: - Route Registration

    private func registerRoutes() {
        guard let httpServer = httpServer else { return }

        // Claude Code hooks
        httpServer.registerRoute("/agent/claude/notification") { [weak self] request in
            self?.claudeHandler?.handleNotification(request: request) ??
                HTTPResponse(statusCode: 503, json: ["error": "Service unavailable"])
        }

        httpServer.registerRoute("/agent/claude/stop") { [weak self] request in
            self?.claudeHandler?.handleStop(request: request) ??
                HTTPResponse(statusCode: 503, json: ["error": "Service unavailable"])
        }

        httpServer.registerRoute("/agent/claude/error") { [weak self] request in
            self?.claudeHandler?.handleError(request: request) ??
                HTTPResponse(statusCode: 503, json: ["error": "Service unavailable"])
        }

        // Codex hooks
        httpServer.registerRoute("/agent/codex/permission-request") { [weak self] request in
            self?.codexHandler?.handlePermissionRequest(request: request) ??
                HTTPResponse(statusCode: 503, json: ["error": "Service unavailable"])
        }

        httpServer.registerRoute("/agent/codex/session-start") { [weak self] request in
            self?.codexHandler?.handleSessionStart(request: request) ??
                HTTPResponse(statusCode: 503, json: ["error": "Service unavailable"])
        }

        httpServer.registerRoute("/agent/codex/stop") { [weak self] request in
            self?.codexHandler?.handleStop(request: request) ??
                HTTPResponse(statusCode: 503, json: ["error": "Service unavailable"])
        }

        httpServer.registerRoute("/agent/codex/pre-tool-use") { [weak self] request in
            self?.codexHandler?.handlePreToolUse(request: request) ??
                HTTPResponse(statusCode: 503, json: ["error": "Service unavailable"])
        }

        httpServer.registerRoute("/agent/codex/post-tool-use") { [weak self] request in
            self?.codexHandler?.handlePostToolUse(request: request) ??
                HTTPResponse(statusCode: 503, json: ["error": "Service unavailable"])
        }

        // 通用接口
        httpServer.registerRoute("/agent/health") { [weak self] request in
            return self?.handleHealthCheck(request: request) ??
                HTTPResponse(statusCode: 503, json: ["error": "Service unavailable"])
        }

        httpServer.registerRoute("/agent/sessions") { [weak self] request in
            return self?.handleGetSessions(request: request) ??
                HTTPResponse(statusCode: 503, json: ["error": "Service unavailable"])
        }
    }

    // MARK: - Health Check

    private func handleHealthCheck(request: HTTPRequest) -> HTTPResponse {
        let activeSessions = sessionStore.activeSessions.count
        let waitingSessions = sessionStore.waitingSessions.count

        return HTTPResponse(statusCode: 200, json: [
            "status": "ok",
            "isRunning": isServerRunning,
            "activeSessions": activeSessions,
            "waitingSessions": waitingSessions,
            "serverPort": serverPort
        ])
    }

    // MARK: - Get Sessions

    private func handleGetSessions(request: HTTPRequest) -> HTTPResponse {
        let sessions = Array(sessionStore.sessions.values)
            .sorted { $0.updatedAt > $1.updatedAt }
            .map { session -> [String: Any] in
                [
                    "id": session.id,
                    "source": session.source.rawValue,
                    "state": session.state.rawValue,
                    "projectName": session.projectName ?? "",
                    "cwd": session.cwd ?? "",
                    "updatedAt": ISO8601DateFormatter().string(from: session.updatedAt)
                ]
            }

        return HTTPResponse(statusCode: 200, json: ["sessions": sessions])
    }

    // MARK: - Notification Handling

    private func handleSessionChanges(_ sessions: [String: AgentSession]) {
        let waitingSessions = sessions.values.filter { $0.isWaiting }

        for session in waitingSessions {
            sendLocalNotification(for: session)
        }

        // 更新菜单栏状态
        updateMenuBarStatus()
    }

    private func sendLocalNotification(for session: AgentSession) {
        let content = UNMutableNotificationContent()
        content.title = "\(session.source.displayName) 需要处理"
        content.body = session.lastEvent?.message ?? "任务等待处理"
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "agent-watcher-\(session.id)",
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("[AgentWatcherService] Failed to send notification: \(error)")
            }
        }
    }

    private func updateMenuBarStatus() {
        // 这里会通过 NotificationCenter 通知 MenuBarView 更新状态
        NotificationCenter.default.post(
            name: .agentWatcherStatusChanged,
            object: nil,
            userInfo: [
                "hasWaiting": sessionStore.hasWaitingSessions,
                "waitingCount": sessionStore.waitingSessions.count
            ]
        )
    }

    // MARK: - Session Management

    func resolveSession(_ sessionId: String) {
        sessionStore.resolveSession(sessionId)
    }

    func muteSession(_ sessionId: String, duration: TimeInterval) {
        // TODO: 实现静音功能
    }

    // MARK: - Cleanup

    func cleanup() {
        sessionStore.removeStaleSessions(olderThan: 3600) // 1小时后清理
    }
}

// MARK: - Notification Name Extension

extension Notification.Name {
    static let agentWatcherStatusChanged = Notification.Name("agentWatcherStatusChanged")
}
