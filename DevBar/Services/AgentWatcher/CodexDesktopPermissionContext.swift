import Foundation

struct CodexDesktopPermissionContext {
    static let shared = CodexDesktopPermissionContext()

    private let stateFileURL: URL

    init(stateFileURL: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".codex/.codex-global-state.json")) {
        self.stateFileURL = stateFileURL
    }

    func approvalsReviewer(for sessionId: String?) -> String? {
        guard let data = try? Data(contentsOf: stateFileURL) else { return nil }
        return Self.approvalsReviewer(from: data, sessionId: sessionId)
    }

    static func approvalsReviewer(from data: Data, sessionId: String?) -> String? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let atomState = root["electron-persisted-atom-state"] as? [String: Any] else {
            return nil
        }

        if let sessionId,
           let permissionsByThread = atomState["heartbeat-thread-permissions-by-id"] as? [String: Any],
           let permissions = permissionsByThread[sessionId] as? [String: Any],
           let approvalsReviewer = permissions["approvalsReviewer"] as? String {
            return approvalsReviewer
        }

        guard let agentModesByHost = atomState["agent-mode-by-host-id"] as? [String: Any],
              let localAgentMode = agentModesByHost["local"] as? String,
              localAgentMode == "guardian-approvals" else {
            return nil
        }
        return localAgentMode
    }
}
