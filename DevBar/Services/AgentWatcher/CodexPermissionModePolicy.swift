import Foundation

enum CodexPermissionModePolicy {
    private static let noConfirmationModes: Set<String> = [
        "auto",
        "autoreview",
        "never",
        "fullauto",
        "bypasspermissions",
        "guardianapprovals",
        "guardiansubagent"
    ]

    static func suppressesNotifications(
        for permissionMode: String?,
        approvalsReviewer: String? = nil
    ) -> Bool {
        [permissionMode, approvalsReviewer]
            .compactMap { $0 }
            .contains { noConfirmationModes.contains(normalized($0)) }
    }

    private static func normalized(_ value: String) -> String {
        value
            .lowercased()
            .filter { !$0.isWhitespace && $0 != "-" && $0 != "_" }
    }
}
