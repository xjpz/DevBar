import Foundation
import Testing
@testable import DevBar

struct AgentWatcherHookPayloadTests {
    @MainActor
    @Test
    func claudePermissionRequestCreatesWaitingApprovalSession() async throws {
        let store = AgentSessionStore()
        store.sessions = [:]
        let handler = ClaudeHookHandler(sessionStore: store)
        let request = HTTPRequest(
            method: "POST",
            path: "/agent/claude/permission-request",
            headers: [:],
            body: Data(
                #"""
                {
                  "session_id": "claude-permission-session",
                  "cwd": "/Users/xjpz/Documents/workspace/ai/xcode/DevBar",
                  "hook_event_name": "PermissionRequest",
                  "tool_name": "Bash",
                  "tool_input": { "command": "git status" },
                  "tool_use_id": "tool-1"
                }
                """#.utf8
            )
        )

        let response = handler.handlePermissionRequest(request: request)
        await Task.yield()

        let session = store.sessions["claude-permission-session"]
        #expect(response.statusCode == 200)
        #expect(session?.source == .claudeCode)
        #expect(session?.state == .waitingApproval)
        #expect(session?.lastEvent?.eventType == .approvalRequired)
        #expect(session?.lastEvent?.severity == .important)
        #expect(session?.lastEvent?.requiresUserAction == true)
        #expect(session?.lastEvent?.canNotifyPhone == true)
    }

    @Test
    func decodesCodexCamelCaseAutomaticReviewer() throws {
        let payload = try JSONDecoder().decode(
            CodexHookPayload.self,
            from: Data(#"{"permissionMode":"default","approvalsReviewer":"auto_review"}"#.utf8)
        )

        #expect(payload.permissionMode == "default")
        #expect(payload.approvalsReviewer == "auto_review")
        #expect(CodexPermissionModePolicy.suppressesNotifications(
            for: payload.permissionMode,
            approvalsReviewer: payload.approvalsReviewer
        ))
    }

    @Test
    func decodesCodexApprovalPolicyAlias() throws {
        let payload = try JSONDecoder().decode(
            CodexHookPayload.self,
            from: Data(#"{"permission_mode":"default","approval_policy":"never"}"#.utf8)
        )

        #expect(payload.approvalsReviewer == "never")
        #expect(CodexPermissionModePolicy.suppressesNotifications(
            for: payload.permissionMode,
            approvalsReviewer: payload.approvalsReviewer
        ))
    }

    @Test
    func claudeIdlePromptRequiresUserInput() {
        let result = ClaudeHookHandler.inferEventType(
            notificationType: "idle_prompt",
            message: "Claude is waiting for your input",
            defaultType: .notification
        )

        #expect(result.0 == .waitingUserInput)
        #expect(result.1 == .warning)
    }

    @Test
    func claudePermissionPromptRequiresApproval() {
        let result = ClaudeHookHandler.inferEventType(
            notificationType: "permission_prompt",
            message: nil,
            defaultType: .notification
        )

        #expect(result.0 == .approvalRequired)
        #expect(result.1 == .important)
    }

    @Test
    func codexDesktopContextUsesThreadReviewerBeforeGlobalMode() throws {
        let data = Data(
            #"""
            {
              "electron-persisted-atom-state": {
                "agent-mode-by-host-id": { "local": "guardian-approvals" },
                "heartbeat-thread-permissions-by-id": {
                  "thread-1": { "approvalsReviewer": "guardian_subagent" }
                }
              }
            }
            """#.utf8
        )

        #expect(CodexDesktopPermissionContext.approvalsReviewer(from: data, sessionId: "thread-1") == "guardian_subagent")
    }

    @Test
    func codexDesktopContextFallsBackToGuardianMode() throws {
        let data = Data(
            #"""
            {
              "electron-persisted-atom-state": {
                "agent-mode-by-host-id": { "local": "guardian-approvals" }
              }
            }
            """#.utf8
        )

        #expect(CodexDesktopPermissionContext.approvalsReviewer(from: data, sessionId: "missing") == "guardian-approvals")
    }
}
