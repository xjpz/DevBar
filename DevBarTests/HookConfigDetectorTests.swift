import Testing
@testable import DevBar

struct HookConfigDetectorTests {
    @Test func claudeMergePreservesExistingHooksAndAppendsDevBarOnce() {
        let existing: [String: Any] = [
            "theme": "dark",
            "hooks": [
                "Notification": [
                    ["matcher": "custom", "hooks": [["type": "command", "command": "echo existing"]]]
                ],
                "PreToolUse": [
                    ["matcher": "", "hooks": [["type": "command", "command": "echo audit"]]]
                ],
            ],
        ]

        let merged = HookConfigDetector.mergingClaudeHooks(into: existing)
        let mergedAgain = HookConfigDetector.mergingClaudeHooks(into: merged)
        let hooks = mergedAgain["hooks"] as? [String: Any]
        let notifications = hooks?["Notification"] as? [[String: Any]]
        let permissionRequests = hooks?["PermissionRequest"] as? [[String: Any]]

        #expect(mergedAgain["theme"] as? String == "dark")
        #expect((hooks?["PreToolUse"] as? [[String: Any]])?.count == 2)
        #expect(notifications?.count == 2)
        #expect(permissionRequests?.count == 1)
    }

    @Test func codexMergePreservesExistingPermissionHooksAndAppendsDevBarOnce() {
        let existing: [String: Any] = [
            "hooks": [
                "PermissionRequest": [
                    ["matcher": "custom", "hooks": [["type": "command", "command": "echo existing"]]]
                ],
            ],
        ]

        let merged = HookConfigDetector.mergingCodexHooks(into: existing)
        let mergedAgain = HookConfigDetector.mergingCodexHooks(into: merged)
        let hooks = mergedAgain["hooks"] as? [String: Any]
        let permissionRequests = hooks?["PermissionRequest"] as? [[String: Any]]

        #expect(permissionRequests?.count == 2)
    }

    @Test func codexMergeDoesNotInstallSessionStartHook() {
        let merged = HookConfigDetector.mergingCodexHooks(into: [:])
        let hooks = merged["hooks"] as? [String: Any]

        #expect(hooks?["PermissionRequest"] != nil)
        #expect(hooks?["Stop"] != nil)
        #expect(hooks?["SessionStart"] == nil)
    }
}
