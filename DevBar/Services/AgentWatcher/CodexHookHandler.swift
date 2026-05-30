import Foundation

// MARK: - Codex Hook Handler

class CodexHookHandler {
    private weak var sessionStore: AgentSessionStore?

    init(sessionStore: AgentSessionStore) {
        self.sessionStore = sessionStore
    }

    // MARK: - Handle PermissionRequest Hook

    func handlePermissionRequest(request: HTTPRequest) -> HTTPResponse {
        guard let body = request.body else {
            return HTTPResponse(statusCode: 400, json: ["error": "Missing body"])
        }

        do {
            let payload = try JSONDecoder().decode(CodexHookPayload.self, from: body)
            let event = createPermissionEvent(from: payload)

            if let sessionId = payload.sessionId {
                Task { @MainActor in
                    sessionStore?.getOrCreateSession(
                        for: .codexCLI,
                        sessionId: sessionId,
                        cwd: payload.cwd
                    )
                    sessionStore?.updateSession(sessionId, with: event)
                }
            }

            return HTTPResponse(statusCode: 200, json: ["status": "ok"])
        } catch {
            print("[CodexHookHandler] Failed to parse permission request: \(error)")
            return HTTPResponse(statusCode: 400, json: ["error": "Invalid payload"])
        }
    }

    // MARK: - Handle SessionStart Hook

    func handleSessionStart(request: HTTPRequest) -> HTTPResponse {
        guard let body = request.body else {
            return HTTPResponse(statusCode: 400, json: ["error": "Missing body"])
        }

        do {
            let payload = try JSONDecoder().decode(CodexHookPayload.self, from: body)
            let event = createEvent(from: payload, eventType: .sessionStart, severity: .info)

            if let sessionId = payload.sessionId {
                Task { @MainActor in
                    sessionStore?.getOrCreateSession(
                        for: .codexCLI,
                        sessionId: sessionId,
                        cwd: payload.cwd
                    )
                    sessionStore?.updateSession(sessionId, with: event)
                }
            }

            return HTTPResponse(statusCode: 200, json: ["status": "ok"])
        } catch {
            print("[CodexHookHandler] Failed to parse session start: \(error)")
            return HTTPResponse(statusCode: 400, json: ["error": "Invalid payload"])
        }
    }

    // MARK: - Handle Stop Hook

    func handleStop(request: HTTPRequest) -> HTTPResponse {
        guard let body = request.body else {
            return HTTPResponse(statusCode: 400, json: ["error": "Missing body"])
        }

        do {
            let payload = try JSONDecoder().decode(CodexHookPayload.self, from: body)
            let event = createEvent(from: payload, eventType: .taskCompleted, severity: .info)

            if let sessionId = payload.sessionId {
                Task { @MainActor in
                    sessionStore?.updateSession(sessionId, with: event)
                }
            }

            return HTTPResponse(statusCode: 200, json: ["status": "ok"])
        } catch {
            print("[CodexHookHandler] Failed to parse stop: \(error)")
            return HTTPResponse(statusCode: 400, json: ["error": "Invalid payload"])
        }
    }

    // MARK: - Handle PreToolUse Hook

    func handlePreToolUse(request: HTTPRequest) -> HTTPResponse {
        guard let body = request.body else {
            return HTTPResponse(statusCode: 400, json: ["error": "Missing body"])
        }

        do {
            let payload = try JSONDecoder().decode(CodexHookPayload.self, from: body)
            let event = createEvent(from: payload, eventType: .preToolUse, severity: .info)

            if let sessionId = payload.sessionId {
                Task { @MainActor in
                    sessionStore?.updateSession(sessionId, with: event)
                }
            }

            return HTTPResponse(statusCode: 200, json: ["status": "ok"])
        } catch {
            print("[CodexHookHandler] Failed to parse pre tool use: \(error)")
            return HTTPResponse(statusCode: 400, json: ["error": "Invalid payload"])
        }
    }

    // MARK: - Handle PostToolUse Hook

    func handlePostToolUse(request: HTTPRequest) -> HTTPResponse {
        guard let body = request.body else {
            return HTTPResponse(statusCode: 400, json: ["error": "Missing body"])
        }

        do {
            let payload = try JSONDecoder().decode(CodexHookPayload.self, from: body)
            let event = createEvent(from: payload, eventType: .postToolUse, severity: .info)

            if let sessionId = payload.sessionId {
                Task { @MainActor in
                    sessionStore?.updateSession(sessionId, with: event)
                }
            }

            return HTTPResponse(statusCode: 200, json: ["status": "ok"])
        } catch {
            print("[CodexHookHandler] Failed to parse post tool use: \(error)")
            return HTTPResponse(statusCode: 400, json: ["error": "Invalid payload"])
        }
    }

    // MARK: - Event Creation

    private func createPermissionEvent(from payload: CodexHookPayload) -> AgentEvent {
        let toolName = payload.toolName ?? "Unknown"
        let command = payload.toolInput?.command ?? "unknown command"
        let message = "Codex 等待授权运行: \(command)"

        return AgentEvent(
            source: .codexCLI,
            eventType: .approvalRequired,
            severity: .important,
            projectName: payload.cwd.flatMap { extractProjectName(from: $0) },
            cwd: payload.cwd,
            sessionId: payload.sessionId,
            taskTitle: "\(toolName) command",
            message: message,
            rawSnippet: command,
            requiresUserAction: true,
            canResolveOnMac: true,
            canNotifyPhone: true
        )
    }

    private func createEvent(from payload: CodexHookPayload, eventType: AgentEventType, severity: AgentSeverity) -> AgentEvent {
        let toolName = payload.toolName.map { " (\($0))" } ?? ""

        return AgentEvent(
            source: .codexCLI,
            eventType: eventType,
            severity: severity,
            projectName: payload.cwd.flatMap { extractProjectName(from: $0) },
            cwd: payload.cwd,
            sessionId: payload.sessionId,
            taskTitle: eventType.displayName + toolName,
            message: "Codex \(eventType.displayName)",
            rawSnippet: payload.toolInput?.command,
            requiresUserAction: eventType.requiresUserAction,
            canResolveOnMac: true,
            canNotifyPhone: eventType.requiresUserAction
        )
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
