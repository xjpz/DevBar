import Foundation

// MARK: - Claude Hook Handler

class ClaudeHookHandler {
    private weak var sessionStore: AgentSessionStore?

    init(sessionStore: AgentSessionStore) {
        self.sessionStore = sessionStore
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
                Task { @MainActor in
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
                Task { @MainActor in
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

    private func createEvent(from payload: ClaudeHookPayload, eventType: AgentEventType) -> AgentEvent {
        let (inferredType, severity) = inferEventType(from: payload.message, defaultType: eventType)

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

    private func inferEventType(from message: String?, defaultType: AgentEventType) -> (AgentEventType, AgentSeverity) {
        guard let message = message?.lowercased() else {
            return (defaultType, .info)
        }

        if message.contains("permission") || message.contains("approval") || message.contains("authorize") {
            return (.approvalRequired, .important)
        }

        if message.contains("login") || message.contains("auth") || message.contains("expired") {
            return (.loginRequired, .critical)
        }

        if message.contains("waiting") || message.contains("input") {
            return (.waitingUserInput, .warning)
        }

        if message.contains("error") || message.contains("failed") {
            return (.taskFailed, .warning)
        }

        if message.contains("complete") || message.contains("finish") {
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
