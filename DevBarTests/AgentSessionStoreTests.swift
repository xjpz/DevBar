import Foundation
import Testing
@testable import DevBar

@MainActor
struct AgentSessionStoreTests {
    @Test func runningSessionBecomesStalledAfterThreshold() {
        let store = AgentSessionStore()
        let now = Date()
        store.sessions = [
            "session-1": AgentSession(
                id: "session-1",
                source: .codexCLI,
                state: .running,
                updatedAt: now.addingTimeInterval(-601)
            ),
        ]

        store.detectStalledSessions(now: now, threshold: 600)

        let session = store.sessions["session-1"]
        #expect(session?.state == .stalled)
        #expect(session?.lastEvent?.eventType == .taskStalled)
        #expect(session?.lastEvent?.severity == .critical)
    }

    @Test func stalledDetectionEmitsOnlyOneSyntheticEvent() {
        let store = AgentSessionStore()
        let now = Date()
        store.sessions = [
            "session-1": AgentSession(
                id: "session-1",
                source: .codexCLI,
                state: .running,
                updatedAt: now.addingTimeInterval(-601)
            ),
        ]

        store.detectStalledSessions(now: now, threshold: 600)
        store.detectStalledSessions(now: now.addingTimeInterval(60), threshold: 600)

        #expect(store.sessions["session-1"]?.recentEvents.filter { $0.eventType == .taskStalled }.count == 1)
    }

    @Test func recentRunningSessionRemainsRunning() {
        let store = AgentSessionStore()
        let now = Date()
        store.sessions = [
            "session-1": AgentSession(
                id: "session-1",
                source: .claudeCode,
                state: .running,
                updatedAt: now.addingTimeInterval(-599)
            ),
        ]

        store.detectStalledSessions(now: now, threshold: 600)

        #expect(store.sessions["session-1"]?.state == .running)
    }

    @Test func muteExpiresLazily() {
        let store = AgentSessionStore()
        let now = Date()
        store.sessions = [
            "session-1": AgentSession(id: "session-1", source: .codexCLI, state: .waitingApproval),
        ]

        store.muteSession("session-1", until: now.addingTimeInterval(60))

        #expect(store.isMuted("session-1", now: now))
        #expect(!store.isMuted("session-1", now: now.addingTimeInterval(61)))
        #expect(store.sessions["session-1"]?.isWaiting == true)
    }

    @Test func automaticReviewPermissionEventKeepsSessionRunning() {
        let store = AgentSessionStore()
        store.sessions = [
            "session-1": AgentSession(id: "session-1", source: .codexCLI, state: .waitingApproval),
        ]
        let event = AgentEvent(
            source: .codexCLI,
            eventType: .approvalRequired,
            severity: .info,
            sessionId: "session-1",
            message: "Codex 自动审查运行 exec_command",
            requiresUserAction: false,
            canNotifyPhone: false,
            canNotifyUser: false
        )

        store.updateSession("session-1", with: event)

        #expect(store.sessions["session-1"]?.state == .running)
        #expect(store.sessions["session-1"]?.waitingSince == nil)
    }
}
