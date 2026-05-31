import Foundation

#if os(iOS) && canImport(ActivityKit)
import ActivityKit

public struct AgentWatcherActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable, Sendable {
        public let waitingCount: Int
        public let activeCount: Int
        public let waitingSource: String?
        public let waitingProject: String?
        public let waitingMessage: String?
        public let waitingSince: Date?
        public let updatedAt: Date

        public init(
            waitingCount: Int,
            activeCount: Int,
            waitingSource: String?,
            waitingProject: String?,
            waitingMessage: String?,
            waitingSince: Date?,
            updatedAt: Date = Date()
        ) {
            self.waitingCount = waitingCount
            self.activeCount = activeCount
            self.waitingSource = waitingSource
            self.waitingProject = waitingProject
            self.waitingMessage = waitingMessage
            self.waitingSince = waitingSince
            self.updatedAt = updatedAt
        }

        public var isWaiting: Bool {
            waitingCount > 0
        }

        public var waitingDuration: TimeInterval? {
            guard let waitingSince = waitingSince else { return nil }
            return Date().timeIntervalSince(waitingSince)
        }

        public var formattedWaitingTime: String? {
            guard let duration = waitingDuration else { return nil }
            let minutes = Int(duration) / 60
            let seconds = Int(duration) % 60
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }

    public let title: String

    public init(title: String = "Agent Watcher") {
        self.title = title
    }
}

// MARK: - Live Activity Manager

public actor AgentWatcherLiveActivityManager {
    public static let shared = AgentWatcherLiveActivityManager()

    private var currentActivityId: String?

    public init() {}

    public func startActivity() async {
        // 结束现有活动
        await endActivity()

        let attributes = AgentWatcherActivityAttributes()
        let state = AgentWatcherActivityAttributes.ContentState(
            waitingCount: 0,
            activeCount: 0,
            waitingSource: nil,
            waitingProject: nil,
            waitingMessage: nil,
            waitingSince: nil
        )

        do {
            let activity = try Activity.request(
                attributes: attributes,
                content: .init(state: state, staleDate: nil),
                pushType: .token
            )
            currentActivityId = activity.id
            print("[AgentWatcherLiveActivity] Activity started: \(activity.id)")
        } catch {
            print("[AgentWatcherLiveActivity] Failed to start activity: \(error)")
        }
    }

    public func updateActivity(
        waitingCount: Int,
        activeCount: Int,
        waitingSource: String? = nil,
        waitingProject: String? = nil,
        waitingMessage: String? = nil,
        waitingSince: Date? = nil
    ) async {
        guard let activityId = currentActivityId,
              let activity = Activity<AgentWatcherActivityAttributes>.activities.first(where: { $0.id == activityId }) else {
            return
        }

        let state = AgentWatcherActivityAttributes.ContentState(
            waitingCount: waitingCount,
            activeCount: activeCount,
            waitingSource: waitingSource,
            waitingProject: waitingProject,
            waitingMessage: waitingMessage,
            waitingSince: waitingSince
        )

        let staleDate = Calendar.current.date(byAdding: .minute, value: 30, to: Date())!
        await activity.update(.init(state: state, staleDate: staleDate))
    }

    public func endActivity() async {
        guard let activityId = currentActivityId,
              let activity = Activity<AgentWatcherActivityAttributes>.activities.first(where: { $0.id == activityId }) else {
            currentActivityId = nil
            return
        }
        currentActivityId = nil

        let finalState = AgentWatcherActivityAttributes.ContentState(
            waitingCount: 0,
            activeCount: 0,
            waitingSource: nil,
            waitingProject: nil,
            waitingMessage: nil,
            waitingSince: nil
        )
        await activity.end(.init(state: finalState, staleDate: nil), dismissalPolicy: .after(.now + 5))
        print("[AgentWatcherLiveActivity] Activity ended")
    }

    public func getPushToken() async -> Data? {
        guard let activityId = currentActivityId,
              let activity = Activity<AgentWatcherActivityAttributes>.activities.first(where: { $0.id == activityId }) else {
            return nil
        }
        return activity.pushToken
    }
}
#endif
