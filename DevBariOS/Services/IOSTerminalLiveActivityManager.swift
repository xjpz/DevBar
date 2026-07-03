#if canImport(ActivityKit)
import ActivityKit
import DevBarCore
import Foundation

@MainActor
final class IOSTerminalLiveActivityManager {
    static let shared = IOSTerminalLiveActivityManager()

    private var sessions: [UUID: TerminalActivitySessionSnapshot] = [:]

    private init() {}

    func update(
        serverID: UUID,
        serverName: String,
        address: String,
        remoteOSFamily: TerminalRemoteOSFamily,
        status: TerminalActivityStatus,
        statusText: String? = nil
    ) async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        sessions[serverID] = TerminalActivitySessionSnapshot(
            id: serverID.uuidString,
            serverName: serverName,
            address: address,
            remoteOSFamilyRawValue: remoteOSFamily.rawValue,
            status: status,
            statusText: statusText ?? status.title
        )
        let state = makeState(selectedPage: Self.currentActivity?.content.state.selectedPage ?? 0)

        if let activity = Self.currentActivity {
            await activity.update(ActivityContent(state: state, staleDate: Calendar.current.date(byAdding: .minute, value: 30, to: .now)))
            return
        }

        guard status == .connecting || status == .connected || status == .suspended else { return }

        do {
            _ = try Activity.request(
                attributes: TerminalActivityAttributes(),
                content: ActivityContent(state: state, staleDate: Calendar.current.date(byAdding: .minute, value: 30, to: .now)),
                pushType: nil
            )
        } catch {
            print("[DevBar:TerminalLiveActivity] failed to start: \(error)")
        }
    }

    func end(serverID: UUID) async {
        sessions.removeValue(forKey: serverID)

        guard let activity = Self.currentActivity else { return }
        guard !sessions.isEmpty else {
            let state = TerminalActivityAttributes.ContentState(
                status: .disconnected,
                statusText: TerminalActivityStatus.disconnected.title
            )
            await activity.end(ActivityContent(state: state, staleDate: nil), dismissalPolicy: .after(.now + 5))
            return
        }

        let state = makeState(selectedPage: activity.content.state.selectedPage)
        await activity.update(ActivityContent(state: state, staleDate: Calendar.current.date(byAdding: .minute, value: 30, to: .now)))
    }

    private func makeState(selectedPage: Int) -> TerminalActivityAttributes.ContentState {
        let orderedSessions = sessions.values.sorted {
            if $0.updatedAt == $1.updatedAt {
                return $0.serverName.localizedStandardCompare($1.serverName) == .orderedAscending
            }
            return $0.updatedAt > $1.updatedAt
        }
        let primaryStatus = aggregateStatus(for: orderedSessions)
        let statusText = orderedSessions.count > 1
            ? "\(orderedSessions.count) SSH Sessions"
            : (orderedSessions.first?.statusText ?? primaryStatus.title)

        return TerminalActivityAttributes.ContentState(
            status: primaryStatus,
            statusText: statusText,
            sessions: orderedSessions,
            selectedPage: selectedPage
        )
    }

    private func aggregateStatus(for sessions: [TerminalActivitySessionSnapshot]) -> TerminalActivityStatus {
        if sessions.contains(where: { $0.status == .failed }) {
            return .failed
        }
        if sessions.contains(where: { $0.status == .connecting }) {
            return .connecting
        }
        if sessions.contains(where: { $0.status == .connected }) {
            return .connected
        }
        if sessions.contains(where: { $0.status == .suspended }) {
            return .suspended
        }
        return .disconnected
    }

    private static var currentActivity: Activity<TerminalActivityAttributes>? {
        Activity<TerminalActivityAttributes>.activities.first
    }
}
#endif
