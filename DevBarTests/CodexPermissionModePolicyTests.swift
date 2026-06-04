import Testing
@testable import DevBar

struct CodexPermissionModePolicyTests {
    @Test(arguments: [
        "auto",
        "auto-review",
        "auto_review",
        "never",
        "full-auto",
        "FULL_AUTO",
        "bypassPermissions",
        "bypass_permissions",
        "guardian-approvals",
        "guardian_subagent"
    ])
    func suppressesNoConfirmationModes(_ permissionMode: String) {
        #expect(CodexPermissionModePolicy.suppressesNotifications(for: permissionMode))
    }

    @Test(arguments: [
        "default",
        "ask",
        "on-request"
    ])
    func keepsHumanApprovalModes(_ permissionMode: String) {
        #expect(!CodexPermissionModePolicy.suppressesNotifications(for: permissionMode))
    }

    @Test
    func keepsMissingMode() {
        #expect(!CodexPermissionModePolicy.suppressesNotifications(for: nil))
    }

    @Test
    func suppressesAutomaticReviewerWhenPermissionModeStillRequiresReview() {
        #expect(CodexPermissionModePolicy.suppressesNotifications(
            for: "default",
            approvalsReviewer: "auto_review"
        ))
    }
}
