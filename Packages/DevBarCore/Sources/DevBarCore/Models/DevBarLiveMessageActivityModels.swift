import Foundation

#if os(iOS) && canImport(ActivityKit)
import AppIntents
import ActivityKit

public struct DevBarLiveMessageActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable, Sendable {
        public let message: String
        public let source: String?
        public let updatedAt: Date

        public init(message: String, source: String?, updatedAt: Date = Date()) {
            self.message = message
            self.source = source
            self.updatedAt = updatedAt
        }
    }

    public let title: String

    public init(title: String = "DevBar") {
        self.title = title
    }
}

public actor DevBarLiveMessageActivityManager {
    public static let shared = DevBarLiveMessageActivityManager()

    private var currentActivityId: String?

    public init() {}

    public func showMessage(
        _ message: String,
        source: String? = nil,
        bundleId: String,
        environment: PushEnvironment,
        startedBy: LiveActivityStartedBy = .local
    ) async -> LiveActivityPushRegistration? {
        let state = DevBarLiveMessageActivityAttributes.ContentState(
            message: message,
            source: source
        )

        let activity: Activity<DevBarLiveMessageActivityAttributes>
        if let activityId = currentActivityId,
           let existing = Activity<DevBarLiveMessageActivityAttributes>.activities.first(where: { $0.id == activityId }) {
            activity = existing
        } else if let existing = Activity<DevBarLiveMessageActivityAttributes>.activities.first {
            currentActivityId = existing.id
            activity = existing
        } else {
            do {
                activity = try Activity.request(
                    attributes: DevBarLiveMessageActivityAttributes(),
                    content: .init(
                        state: state,
                        staleDate: Calendar.current.date(byAdding: .minute, value: 30, to: Date())
                    ),
                    pushType: .token
                )
                currentActivityId = activity.id
                print("[DevBarLiveMessage] Activity started: \(activity.id)")
            } catch {
                print("[DevBarLiveMessage] Failed to start activity: \(error)")
                return nil
            }
        }

        await activity.update(.init(
            state: state,
            staleDate: Calendar.current.date(byAdding: .minute, value: 30, to: Date())
        ))

        guard let pushToken = activity.pushToken else {
            print("[DevBarLiveMessage] Activity has no update token yet")
            return nil
        }

        return LiveActivityPushRegistration(
            activityId: activity.id,
            activityType: .devBarLiveMessage,
            activityPushToken: pushToken.hexString,
            bundleId: bundleId,
            environment: environment,
            startedBy: startedBy
        )
    }

    public func endActivity() async {
        guard let activityId = currentActivityId,
              let activity = Activity<DevBarLiveMessageActivityAttributes>.activities.first(where: { $0.id == activityId }) else {
            currentActivityId = nil
            return
        }
        currentActivityId = nil

        let finalState = DevBarLiveMessageActivityAttributes.ContentState(message: "", source: nil)
        await activity.end(.init(state: finalState, staleDate: nil), dismissalPolicy: .after(.now + 5))
        print("[DevBarLiveMessage] Activity ended")
    }

    public func hasActiveActivity() -> Bool {
        if let activityId = currentActivityId,
           Activity<DevBarLiveMessageActivityAttributes>.activities.contains(where: { $0.id == activityId }) {
            return true
        }
        return !Activity<DevBarLiveMessageActivityAttributes>.activities.isEmpty
    }
}

public struct EndDevBarLiveMessageActivityIntent: LiveActivityIntent {
    public static var title: LocalizedStringResource { "End Live Message" }
    public static var description: IntentDescription { "End the active DevBar live message." }

    @Parameter(title: "Activity ID")
    public var activityID: String

    public init() {
        self.activityID = ""
    }

    public init(activityID: String) {
        self.activityID = activityID
    }

    public func perform() async throws -> some IntentResult {
        let activities = Activity<DevBarLiveMessageActivityAttributes>.activities
        guard let activity = activities.first(where: { $0.id == activityID }) ?? activities.first else {
            return .result()
        }
        let finalState = DevBarLiveMessageActivityAttributes.ContentState(message: "", source: nil)
        await activity.end(ActivityContent(state: finalState, staleDate: nil), dismissalPolicy: .immediate)
        return .result()
    }
}

private extension Data {
    var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}
#endif
