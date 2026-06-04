import Foundation
import Testing
@testable import DevBar

struct AgentWatcherPolicyTests {
    @Test func quietModeKeepsBadgeButSuppressesNotifications() {
        let settings = makeSettings()
        settings.notificationMode = .quiet

        let decision = settings.shouldNotify(for: makeEvent(), userActivity: UserActivityState(isPhonePaired: true))

        #expect(decision.updateMacBadge)
        #expect(!decision.sendMacNotification)
        #expect(!decision.sendPhoneNotification)
    }

    @Test func macOnlyModeSuppressesPhoneNotification() {
        let settings = makeSettings()
        settings.notificationMode = .macOnly

        let decision = settings.shouldNotify(
            for: makeEvent(),
            userActivity: UserActivityState(isMacLocked: true, isPhonePaired: true, isPhoneOnline: true)
        )

        #expect(decision.sendMacNotification)
        #expect(!decision.sendPhoneNotification)
    }

    @Test func waitingUserInputSendsMacNotification() {
        let settings = makeSettings()

        let decision = settings.shouldNotify(
            for: AgentEvent(
                source: .claudeCode,
                eventType: .waitingUserInput,
                severity: .warning,
                sessionId: "session-1",
                message: "Claude Code 等待你选择处理方式",
                requiresUserAction: true,
                canNotifyPhone: true
            ),
            userActivity: UserActivityState(isPhonePaired: true)
        )

        #expect(decision.updateMacBadge)
        #expect(decision.sendMacNotification)
    }

    @MainActor
    @Test func minimalRelayPayloadDoesNotContainPathOrCommand() {
        let event = AgentEvent(
            source: .codexCLI,
            eventType: .approvalRequired,
            severity: .important,
            projectName: "DevBar",
            cwd: "/Users/xjpz/Projects/DevBar",
            sessionId: "session-1",
            message: "Codex 等待授权运行: rm -rf ./build",
            rawSnippet: "rm -rf ./build",
            requiresUserAction: true,
            canNotifyPhone: true
        )

        let payload = AgentWatcherService.makeRelayPayload(
            for: event,
            showProjectName: true,
            showCommandSummary: false,
            uploadCwd: false,
            uploadRawOutput: false
        )

        #expect(payload["projectName"] == "DevBar")
        #expect(payload["projectPath"] == nil)
        #expect(payload["rawSnippet"] == nil)
        #expect(payload["message"] == "Codex CLI 等待授权")
    }

    private func makeSettings() -> AgentWatcherSettings {
        let suiteName = "AgentWatcherPolicyTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return AgentWatcherSettings(defaults: defaults)
    }

    private func makeEvent() -> AgentEvent {
        AgentEvent(
            source: .codexCLI,
            eventType: .approvalRequired,
            severity: .important,
            sessionId: "session-1",
            message: "Codex 等待授权",
            requiresUserAction: true,
            canNotifyPhone: true
        )
    }
}
