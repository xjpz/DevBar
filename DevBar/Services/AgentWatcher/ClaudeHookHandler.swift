import Foundation

// MARK: - Claude Hook Handler

class ClaudeHookHandler {
    private weak var sessionStore: AgentSessionStore?
    var onSessionTracked: ((String) -> Void)?

    init(sessionStore: AgentSessionStore) {
        self.sessionStore = sessionStore
    }

    // MARK: - Handle PermissionRequest Hook

    func handlePermissionRequest(request: HTTPRequest) -> HTTPResponse {
        guard let body = request.body else {
            return HTTPResponse(statusCode: 400, json: ["error": "Missing body"])
        }

        do {
            let payload = try JSONDecoder().decode(ClaudeHookPayload.self, from: body)
            let event = createPermissionEvent(from: payload)

            if let sessionId = payload.sessionId {
                onSessionTracked?(sessionId)
                Task { @MainActor in
                    sessionStore?.getOrCreateSession(
                        for: .claudeCode,
                        sessionId: sessionId,
                        cwd: payload.cwd
                    )
                    sessionStore?.updateSession(sessionId, with: event)
                }
            }

            return HTTPResponse(statusCode: 200, json: ["status": "ok"])
        } catch {
            print("[ClaudeHookHandler] Failed to parse permission request: \(error)")
            return HTTPResponse(statusCode: 400, json: ["error": "Invalid payload"])
        }
    }

    // MARK: - Handle PreToolUse Hook

    func handlePreToolUse(request: HTTPRequest) -> HTTPResponse {
        guard let body = request.body else {
            return HTTPResponse(statusCode: 400, json: ["error": "Missing body"])
        }

        do {
            let payload = try JSONDecoder().decode(ClaudeHookPayload.self, from: body)

            if let sessionId = payload.sessionId {
                onSessionTracked?(sessionId)
                let event = AgentEvent(
                    source: .claudeCode,
                    eventType: .preToolUse,
                    severity: .info,
                    projectName: payload.cwd.flatMap { extractProjectName(from: $0) },
                    cwd: payload.cwd,
                    sessionId: sessionId,
                    taskTitle: payload.toolName.map { String(format: String(localized: "工具: %@"), $0) },
                    message: String(
                        format: String(localized: "正在执行 %@"),
                        payload.toolName ?? String(localized: "工具")
                    ),
                    rawSnippet: payload.toolInput?.command,
                    requiresUserAction: false,
                    canResolveOnMac: false,
                    canNotifyPhone: false,
                    canNotifyUser: false
                )
                Task { @MainActor in
                    sessionStore?.getOrCreateSession(
                        for: .claudeCode,
                        sessionId: sessionId,
                        cwd: payload.cwd
                    )
                    sessionStore?.updateSession(sessionId, with: event)
                }
            }

            return HTTPResponse(statusCode: 200, json: ["status": "ok"])
        } catch {
            print("[ClaudeHookHandler] Failed to parse pre-tool-use: \(error)")
            return HTTPResponse(statusCode: 400, json: ["error": "Invalid payload"])
        }
    }

    // MARK: - Handle Notification Hook

    func handleNotification(request: HTTPRequest) -> HTTPResponse {
        guard let body = request.body else {
            return HTTPResponse(statusCode: 400, json: ["error": "Missing body"])
        }

        do {
            let payload = try JSONDecoder().decode(ClaudeHookPayload.self, from: body)
            let event = createEvent(from: payload, eventType: .notification)

            if let sessionId = payload.sessionId {
                onSessionTracked?(sessionId)
                Task { @MainActor in
                    sessionStore?.getOrCreateSession(
                        for: .claudeCode,
                        sessionId: sessionId,
                        cwd: payload.cwd
                    )
                    sessionStore?.updateSession(sessionId, with: event)
                }
            }

            return HTTPResponse(statusCode: 200, json: ["status": "ok"])
        } catch {
            print("[ClaudeHookHandler] Failed to parse notification: \(error)")
            return HTTPResponse(statusCode: 400, json: ["error": "Invalid payload"])
        }
    }

    // MARK: - Handle Stop Hook

    func handleStop(request: HTTPRequest) -> HTTPResponse {
        guard let body = request.body else {
            return HTTPResponse(statusCode: 400, json: ["error": "Missing body"])
        }

        do {
            let payload = try JSONDecoder().decode(ClaudeHookPayload.self, from: body)
            let event = createEvent(from: payload, eventType: .taskCompleted)

            if let sessionId = payload.sessionId {
                onSessionTracked?(sessionId)
                Task { @MainActor in
                    sessionStore?.getOrCreateSession(
                        for: .claudeCode,
                        sessionId: sessionId,
                        cwd: payload.cwd
                    )
                    sessionStore?.updateSession(sessionId, with: event)
                }
            }

            return HTTPResponse(statusCode: 200, json: ["status": "ok"])
        } catch {
            print("[ClaudeHookHandler] Failed to parse stop: \(error)")
            return HTTPResponse(statusCode: 400, json: ["error": "Invalid payload"])
        }
    }

    // MARK: - Handle Error Hook

    func handleError(request: HTTPRequest) -> HTTPResponse {
        guard let body = request.body else {
            return HTTPResponse(statusCode: 400, json: ["error": "Missing body"])
        }

        do {
            let payload = try JSONDecoder().decode(ClaudeHookPayload.self, from: body)
            let event = createEvent(from: payload, eventType: .taskFailed)

            if let sessionId = payload.sessionId {
                onSessionTracked?(sessionId)
                Task { @MainActor in
                    sessionStore?.getOrCreateSession(
                        for: .claudeCode,
                        sessionId: sessionId,
                        cwd: payload.cwd
                    )
                    sessionStore?.updateSession(sessionId, with: event)
                }
            }

            return HTTPResponse(statusCode: 200, json: ["status": "ok"])
        } catch {
            print("[ClaudeHookHandler] Failed to parse error: \(error)")
            return HTTPResponse(statusCode: 400, json: ["error": "Invalid payload"])
        }
    }

    // MARK: - Event Creation

    private func createPermissionEvent(from payload: ClaudeHookPayload) -> AgentEvent {
        let toolName = payload.toolName ?? "Unknown"
        let command = payload.toolInput?.command ?? "unknown command"

        return AgentEvent(
            source: .claudeCode,
            eventType: .approvalRequired,
            severity: .important,
            projectName: payload.cwd.flatMap { extractProjectName(from: $0) },
            cwd: payload.cwd,
            sessionId: payload.sessionId,
            taskTitle: "\(toolName) permission",
            message: String(format: String(localized: "Claude Code 等待授权运行 %@"), toolName),
            rawSnippet: command,
            requiresUserAction: true,
            canResolveOnMac: true,
            canNotifyPhone: true
        )
    }

    private func createEvent(from payload: ClaudeHookPayload, eventType: AgentEventType) -> AgentEvent {
        let (inferredType, severity) = Self.inferEventType(
            notificationType: payload.notificationType,
            message: payload.message,
            defaultType: eventType
        )

        return AgentEvent(
            source: .claudeCode,
            eventType: inferredType,
            severity: severity,
            projectName: payload.cwd.flatMap { extractProjectName(from: $0) },
            cwd: payload.cwd,
            sessionId: payload.sessionId,
            taskTitle: payload.title,
            message: payload.message ?? "Claude Code event",
            rawSnippet: payload.message,
            requiresUserAction: inferredType.requiresUserAction,
            canResolveOnMac: true,
            canNotifyPhone: inferredType.requiresUserAction
        )
    }

    static func inferEventType(
        notificationType: String?,
        message: String?,
        defaultType: AgentEventType
    ) -> (AgentEventType, AgentSeverity) {
        switch notificationType?.lowercased() {
        case "permission_prompt":
            return (.approvalRequired, .important)
        case "idle_prompt", "elicitation_dialog":
            return (.waitingUserInput, .warning)
        default:
            break
        }

        guard let message = message?.lowercased() else {
            return (defaultType, .info)
        }

        if message.contains("permission") || message.contains("approval") || message.contains("authorize") ||
            message.contains("授权") || message.contains("权限") {
            return (.approvalRequired, .important)
        }

        if message.contains("login") || message.contains("auth") || message.contains("expired") ||
            message.contains("登录") || message.contains("过期") {
            return (.loginRequired, .critical)
        }

        if message.contains("waiting") || message.contains("input") ||
            message.contains("等待") || message.contains("输入") || message.contains("确认") {
            return (.waitingUserInput, .warning)
        }

        if message.contains("error") || message.contains("failed") ||
            message.contains("失败") || message.contains("错误") {
            return (.taskFailed, .warning)
        }

        if message.contains("complete") || message.contains("finish") ||
            message.contains("完成") {
            return (.taskCompleted, .info)
        }

        return (defaultType, .info)
    }

    private func extractProjectName(from path: String) -> String {
        let components = path.split(separator: "/")
        if let gitIndex = components.lastIndex(of: ".git") {
            let projectIndex = components.index(before: gitIndex)
            if projectIndex >= components.startIndex {
                return String(components[projectIndex])
            }
        }
        return components.last.map(String.init) ?? path
    }
}
