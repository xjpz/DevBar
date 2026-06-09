import Foundation
import Combine
import CoreGraphics
import Network
import UserNotifications
import DevBarCore

// MARK: - Agent Watcher Service

@MainActor
class AgentWatcherService: ObservableObject {
    static let shared = AgentWatcherService()

    // MARK: - Properties

    let sessionStore = AgentSessionStore()
    private var httpServer: LocalHTTPServer?
    private var claudeHandler: ClaudeHookHandler?
    private var codexHandler: CodexHookHandler?
    private var claudeTranscriptMonitor: ClaudeTranscriptMonitor?
    private let settings = AgentWatcherSettings.shared

    // Relay 集成，用于 iPhone 推送
    weak var relayManager: DeviceRelayManager?

    private var hookManagedSessionIds: Set<String> = []

    @Published var isServerRunning = false
    @Published var lastError: String?
    @Published var waitingCount: Int = 0

    private let serverPort: UInt16 = 49321
    private var cancellables = Set<AnyCancellable>()

    // 通知节流：记录每个 session 上次通知时间
    private var lastNotificationTime: [String: Date] = [:]
    private var relayNotificationLimiter = AgentWatcherNotificationLimiter()
    private var escalationTasks: [String: Task<Void, Never>] = [:]

    var isEnabled: Bool {
        DevBarCoreConstants.Features.agentWatcherEnabled && settings.isEnabled
    }

    // MARK: - Initialization

    private init() {
        guard DevBarCoreConstants.Features.agentWatcherEnabled else {
            settings.isEnabled = false
            return
        }
        setupHandlers()
        setupNotifications()
        requestNotificationPermission()
    }

    private func setupHandlers() {
        claudeHandler = ClaudeHookHandler(sessionStore: sessionStore)
        claudeHandler?.onSessionTracked = { [weak self] sessionId in
            Task { @MainActor [weak self] in
                self?.hookManagedSessionIds.insert(sessionId)
            }
        }
        codexHandler = CodexHookHandler(sessionStore: sessionStore)
        claudeTranscriptMonitor = ClaudeTranscriptMonitor(
            hookManagedSessionIds: { [weak self] in self?.hookManagedSessionIds ?? [] }
        ) { [weak self] event in
            Task { @MainActor [weak self] in
                guard let self, self.settings.claudeEnabled else { return }
                let sessionId = event.sessionId ?? event.id
                _ = self.sessionStore.getOrCreateSession(
                    for: .claudeCode,
                    sessionId: sessionId,
                    cwd: event.cwd
                )
                self.sessionStore.updateSession(sessionId, with: event)
            }
        }
    }

    private func setupNotifications() {
        // 监听会话变化，发送通知和更新 badge
        sessionStore.$sessions
            .receive(on: DispatchQueue.main)
            .sink { [weak self] sessions in
                self?.handleSessionChanges(sessions)
            }
            .store(in: &cancellables)

        settings.$isEnabled
            .removeDuplicates()
            .sink { [weak self] isEnabled in
                guard let self else { return }
                if isEnabled {
                    self.startServer()
                } else {
                    self.stopServer()
                }
            }
            .store(in: &cancellables)
    }

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error = error {
                print("[AgentWatcherService] Notification permission error: \(error)")
            }
            print("[AgentWatcherService] Notification permission granted: \(granted)")
        }
    }

    // MARK: - Server Management

    func startServer() {
        guard DevBarCoreConstants.Features.agentWatcherEnabled, settings.isEnabled, httpServer == nil else { return }

        httpServer = LocalHTTPServer(port: serverPort)
        httpServer?.onStateChange = { [weak self] state in
            Task { @MainActor [weak self] in
                switch state {
                case .ready:
                    self?.isServerRunning = true
                    self?.lastError = nil
                case .failed(let error):
                    self?.isServerRunning = false
                    self?.lastError = "Failed to start server: \(error.localizedDescription)"
                    self?.httpServer = nil
                case .cancelled:
                    self?.isServerRunning = false
                default:
                    break
                }
            }
        }
        registerRoutes()

        do {
            try httpServer?.start()
            claudeTranscriptMonitor?.start()
            lastError = nil
            print("[AgentWatcherService] Starting server on port \(serverPort)")
        } catch {
            lastError = "Failed to start server: \(error.localizedDescription)"
            httpServer = nil
            print("[AgentWatcherService] \(lastError!)")
        }
    }

    func stopServer() {
        claudeTranscriptMonitor?.stop()
        httpServer?.stop()
        httpServer = nil
        isServerRunning = false
        print("[AgentWatcherService] Server stopped")
    }

    // MARK: - Route Registration

    private func registerRoutes() {
        guard let httpServer = httpServer else { return }

        // Claude Code hooks
        httpServer.registerRoute("POST", "/agent/claude/permission-request") { [weak self] request in
            guard self?.settings.claudeEnabled == true else { return HTTPResponse(statusCode: 204) }
            return self?.claudeHandler?.handlePermissionRequest(request: request) ??
                HTTPResponse(statusCode: 503, json: ["error": "Service unavailable"])
        }

        httpServer.registerRoute("POST", "/agent/claude/notification") { [weak self] request in
            guard self?.settings.claudeEnabled == true else { return HTTPResponse(statusCode: 204) }
            return self?.claudeHandler?.handleNotification(request: request) ??
                HTTPResponse(statusCode: 503, json: ["error": "Service unavailable"])
        }

        httpServer.registerRoute("POST", "/agent/claude/stop") { [weak self] request in
            guard self?.settings.claudeEnabled == true else { return HTTPResponse(statusCode: 204) }
            return self?.claudeHandler?.handleStop(request: request) ??
                HTTPResponse(statusCode: 503, json: ["error": "Service unavailable"])
        }

        httpServer.registerRoute("POST", "/agent/claude/error") { [weak self] request in
            guard self?.settings.claudeEnabled == true else { return HTTPResponse(statusCode: 204) }
            return self?.claudeHandler?.handleError(request: request) ??
                HTTPResponse(statusCode: 503, json: ["error": "Service unavailable"])
        }

        httpServer.registerRoute("POST", "/agent/claude/pre-tool-use") { [weak self] request in
            guard self?.settings.claudeEnabled == true else { return HTTPResponse(statusCode: 204) }
            return self?.claudeHandler?.handlePreToolUse(request: request) ??
                HTTPResponse(statusCode: 503, json: ["error": "Service unavailable"])
        }

        // Codex hooks
        httpServer.registerRoute("POST", "/agent/codex/permission-request") { [weak self] request in
            guard self?.settings.codexEnabled == true else { return HTTPResponse(statusCode: 204) }
            return self?.codexHandler?.handlePermissionRequest(request: request) ??
                HTTPResponse(statusCode: 503, json: ["error": "Service unavailable"])
        }

        httpServer.registerRoute("POST", "/agent/codex/session-start") { [weak self] request in
            guard self?.settings.codexEnabled == true else { return HTTPResponse(statusCode: 204) }
            return self?.codexHandler?.handleSessionStart(request: request) ??
                HTTPResponse(statusCode: 503, json: ["error": "Service unavailable"])
        }

        httpServer.registerRoute("POST", "/agent/codex/stop") { [weak self] request in
            guard self?.settings.codexEnabled == true else { return HTTPResponse(statusCode: 204) }
            return self?.codexHandler?.handleStop(request: request) ??
                HTTPResponse(statusCode: 503, json: ["error": "Service unavailable"])
        }

        httpServer.registerRoute("POST", "/agent/codex/pre-tool-use") { [weak self] request in
            guard self?.settings.codexEnabled == true else { return HTTPResponse(statusCode: 204) }
            return self?.codexHandler?.handlePreToolUse(request: request) ??
                HTTPResponse(statusCode: 503, json: ["error": "Service unavailable"])
        }

        httpServer.registerRoute("POST", "/agent/codex/post-tool-use") { [weak self] request in
            guard self?.settings.codexEnabled == true else { return HTTPResponse(statusCode: 204) }
            return self?.codexHandler?.handlePostToolUse(request: request) ??
                HTTPResponse(statusCode: 503, json: ["error": "Service unavailable"])
        }

        // 通用接口
        httpServer.registerRoute("GET", "/agent/health") { [weak self] request in
            return self?.handleHealthCheck(request: request) ??
                HTTPResponse(statusCode: 503, json: ["error": "Service unavailable"])
        }

        httpServer.registerRoute("GET", "/agent/sessions") { [weak self] request in
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

        // 更新等待数量
        waitingCount = waitingSessions.count

        // 对新进入等待状态的 session 发送通知（带节流）
        for session in waitingSessions {
            guard let event = session.lastEvent else { continue }
            guard !sessionStore.isMuted(session.id) else { continue }
            let decision = settings.shouldNotify(for: event, userActivity: currentUserActivityState())

            if decision.sendMacNotification, shouldNotify(for: session.id, timestamps: lastNotificationTime) {
                sendLocalNotification(for: session)
                lastNotificationTime[session.id] = Date()
            }
            if decision.sendPhoneNotification {
                sendRelayNotification(for: event)
            } else if let delay = decision.delayPhoneNotificationSeconds {
                scheduleRelayEscalation(for: event, delay: delay)
            }
        }

        // 清理已不再等待的 session 的通知记录
        let waitingIds = Set(waitingSessions.map { $0.id })
        lastNotificationTime = lastNotificationTime.filter { waitingIds.contains($0.key) }
        escalationTasks = escalationTasks.filter { sessionId, task in
            guard waitingIds.contains(sessionId) else {
                task.cancel()
                return false
            }
            return true
        }

        // 更新菜单栏状态
        updateMenuBarStatus()

        // 更新 Widget 数据
        updateWidgetData()
    }

    private func shouldNotify(for sessionId: String, timestamps: [String: Date]) -> Bool {
        guard let lastTime = timestamps[sessionId] else {
            return true // 从未通知过
        }
        return Date().timeIntervalSince(lastTime) > TimeInterval(settings.repeatIntervalMinutes * 60)
    }

    private func sendLocalNotification(for session: AgentSession) {
        let content = UNMutableNotificationContent()
        content.title = "\(session.source.displayName) 需要处理"
        content.body = localNotificationMessage(for: session.lastEvent)
        content.sound = .default
        content.categoryIdentifier = "AGENT_WATCHER"

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

    // MARK: - iPhone Push via Relay

    func sendRelayNotification(for event: AgentEvent) {
        guard DevBarCoreConstants.Features.agentWatcherEnabled else { return }
        guard let relayManager = relayManager else { return }
        guard event.canNotifyUser else { return }
        guard event.canNotifyPhone else { return }
        guard currentUserActivityState().isPhonePaired else { return }

        let sessionId = event.sessionId ?? "unknown"
        let summary = makeNotificationSummary()
        let result = relayNotificationLimiter.evaluate(
            sessionId: sessionId,
            eventType: event.eventType,
            summary: summary
        )
        guard result != .suppress else { return }

        let iPhonePeers = relayManager.peers.filter { $0.deviceType == .iPhone }
        guard let targetDeviceId = iPhonePeers.first(where: { relayManager.isPeerReachable($0) })?.deviceId
            ?? iPhonePeers.first?.deviceId
        else { return }

        let payload: [String: String]
        switch result {
        case .allow:
            payload = Self.makeRelayPayload(
                for: event,
                showProjectName: settings.showProjectName,
                showCommandSummary: settings.showCommandSummary,
                uploadCwd: settings.uploadCwd,
                uploadRawOutput: settings.uploadRawOutput
            )
        case .summary(let summary):
            payload = Self.makeRelaySummaryPayload(summary)
        case .suppress:
            return
        }

        Task {
            do {
                try await relayManager.send(DeviceRelayMessage(
                    type: .approvalRequest,
                    requestId: event.id,
                    fromDeviceId: relayManager.localDeviceID,
                    targetDeviceId: targetDeviceId,
                    payload: payload
                ))
                print("[AgentWatcherService] Relay notification sent for session \(sessionId)")
            } catch {
                print("[AgentWatcherService] Failed to send relay notification: \(error)")
            }
        }
    }

    static func makeRelayPayload(
        for event: AgentEvent,
        showProjectName: Bool,
        showCommandSummary: Bool,
        uploadCwd: Bool,
        uploadRawOutput: Bool
    ) -> [String: String] {
        var payload: [String: String] = [
            "status": "waiting",
            "source": event.source.rawValue,
            "eventType": event.eventType.rawValue,
            "severity": event.severity.rawValue,
            "message": showCommandSummary ? event.message : "\(event.source.displayName) \(event.eventType.displayName)",
            "waitingSince": ISO8601DateFormatter().string(from: event.createdAt)
        ]
        if showProjectName, let projectName = event.projectName {
            payload["projectName"] = projectName
        }
        if uploadCwd, let cwd = event.cwd {
            payload["projectPath"] = cwd
        }
        if uploadRawOutput, let rawSnippet = event.rawSnippet {
            payload["rawSnippet"] = String(rawSnippet.prefix(500))
        }
        return payload
    }

    static func makeRelaySummaryPayload(_ summary: AgentWatcherNotificationSummary) -> [String: String] {
        [
            "status": "summary",
            "eventType": "agent.summary",
            "severity": summary.stalledCount > 0 ? AgentSeverity.critical.rawValue : AgentSeverity.important.rawValue,
            "message": "\(summary.taskCount) 个任务需要处理，其中 \(summary.approvalCount) 个等待授权",
            "taskCount": String(summary.taskCount),
            "approvalCount": String(summary.approvalCount),
            "stalledCount": String(summary.stalledCount)
        ]
    }

    private func makeNotificationSummary() -> AgentWatcherNotificationSummary {
        let waitingSessions = sessionStore.waitingSessions
        return AgentWatcherNotificationSummary(
            taskCount: waitingSessions.count,
            approvalCount: waitingSessions.filter { $0.state == .waitingApproval }.count,
            stalledCount: waitingSessions.filter { $0.state == .stalled }.count
        )
    }

    private func scheduleRelayEscalation(for event: AgentEvent, delay: Int) {
        guard event.canNotifyUser,
              event.canNotifyPhone,
              let sessionId = event.sessionId,
              escalationTasks[sessionId] == nil
        else { return }
        escalationTasks[sessionId] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.sendEscalatedRelayNotification(for: event, sessionId: sessionId)
        }
    }

    private func sendEscalatedRelayNotification(for event: AgentEvent, sessionId: String) {
        defer { escalationTasks[sessionId] = nil }
        guard sessionStore.sessions[sessionId]?.isWaiting == true else { return }
        let activity = currentUserActivityState()
        guard activity.isMacLocked || activity.idleMinutes >= settings.idleMinutesForPhone else { return }
        sendRelayNotification(for: event)
    }

    private func currentUserActivityState() -> UserActivityState {
        let iPhonePeers = relayManager?.peers.filter { $0.deviceType == .iPhone } ?? []
        let idleSeconds = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .null)
        return UserActivityState(
            isMacLocked: MacScreenLockStateProvider.isScreenLocked(),
            idleMinutes: Int(idleSeconds / 60),
            isPhonePaired: !iPhonePeers.isEmpty,
            isPhoneOnline: iPhonePeers.contains { relayManager?.isPeerReachable($0) == true }
        )
    }

    private func localNotificationMessage(for event: AgentEvent?) -> String {
        guard let event else { return "任务等待处理" }
        return settings.showCommandSummary ? event.message : "\(event.source.displayName) \(event.eventType.displayName)"
    }

    private func updateMenuBarStatus() {
        NotificationCenter.default.post(
            name: .agentWatcherStatusChanged,
            object: nil,
            userInfo: [
                "hasWaiting": sessionStore.hasWaitingSessions,
                "waitingCount": waitingCount
            ]
        )
    }

    private func updateWidgetData() {
        guard DevBarCoreConstants.Features.agentWatcherEnabled else { return }
        let waitingSessions = sessionStore.waitingSessions
        let sessionInfos = waitingSessions.map { session in
            AgentWatcherSessionInfo(
                id: session.id,
                source: session.source.displayName,
                projectName: session.projectName ?? "Unknown",
                state: session.state.rawValue,
                waitingSince: session.waitingSince,
                message: session.lastEvent?.message ?? ""
            )
        }

        let widgetData = AgentWatcherWidgetData(
            waitingCount: waitingSessions.count,
            activeCount: sessionStore.activeSessions.count,
            lastUpdated: Date(),
            waitingSessions: sessionInfos
        )

        WidgetDataManager.shared.saveAndReloadAgentWatcher(widgetData)

        // 更新 Live Activity (iOS)
        #if os(iOS)
        Task {
            await updateLiveActivity(waitingSessions: waitingSessions)
        }
        #endif
    }

    #if os(iOS)
    private func updateLiveActivity(waitingSessions: [AgentSession]) async {
        guard DevBarCoreConstants.Features.agentWatcherEnabled else { return }
        let manager = AgentWatcherLiveActivityManager.shared

        if waitingSessions.isEmpty {
            await manager.endActivity()
        } else {
            let firstSession = waitingSessions.first
            await manager.updateActivity(
                waitingCount: waitingSessions.count,
                activeCount: sessionStore.activeSessions.count,
                waitingSource: firstSession?.source.displayName,
                waitingProject: firstSession?.projectName,
                waitingMessage: firstSession?.lastEvent?.message,
                waitingSince: firstSession?.waitingSince
            )
        }
    }
    #endif

    // MARK: - Session Management

    func resolveSession(_ sessionId: String) {
        sessionStore.resolveSession(sessionId)
    }

    func muteSession(_ sessionId: String, duration: TimeInterval) {
        sessionStore.muteSession(sessionId, until: Date().addingTimeInterval(duration))
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
