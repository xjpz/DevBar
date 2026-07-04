import Foundation
import UIKit

@MainActor
final class IOSTerminalSessionRegistry {
    static let shared = IOSTerminalSessionRegistry()

    private var sessions: [UUID: IOSTerminalSessionViewModel] = [:]
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid

    private init() {}

    func session(for server: IOSTerminalServer) -> IOSTerminalSessionViewModel {
        if let existing = sessions[server.id] {
            return existing
        }

        let viewModel = IOSTerminalSessionViewModel(server: server)
        sessions[server.id] = viewModel
        return viewModel
    }

    func activeSessions() -> [IOSTerminalSessionViewModel] {
        Array(sessions.values)
    }

    func hasOpenConnection(serverID: UUID) -> Bool {
        sessions[serverID]?.hasOpenConnection ?? false
    }

    func openConnectionIDs() -> Set<UUID> {
        Set(sessions.compactMap { id, session in
            session.hasOpenConnection ? id : nil
        })
    }

    func closeSession(serverID: UUID) {
        sessions[serverID]?.disconnect(shouldRecordOutput: true)
    }

    func updateBackgroundState(isBackgrounded: Bool) {
        for session in sessions.values {
            session.updateLiveActivityForBackgroundState(isBackgrounded: isBackgrounded)
        }

        if isBackgrounded, sessions.values.contains(where: \.isConnected) {
            beginBackgroundTaskIfNeeded()
        } else {
            endBackgroundTaskIfNeeded()
        }
    }

    private func beginBackgroundTaskIfNeeded() {
        guard backgroundTask == .invalid else { return }
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "DevBarTerminalSession") { [weak self] in
            Task { @MainActor in
                self?.endBackgroundTaskIfNeeded()
            }
        }
    }

    private func endBackgroundTaskIfNeeded() {
        guard backgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTask)
        backgroundTask = .invalid
    }
}
