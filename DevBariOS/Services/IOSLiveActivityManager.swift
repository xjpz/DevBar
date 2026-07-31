import ActivityKit
import DevBarCore
import Foundation

struct IOSLiveActivitySyncOutcome {
    let registration: LiveActivityPushRegistration?
    let endedActivityIDs: [String]
}

@MainActor
final class IOSLiveActivityManager {
    static let shared = IOSLiveActivityManager()

    private init() {}

    func sync(
        settings: LiveActivitySettings,
        configs: [AccountConfig],
        dataByProvider: [WidgetProvider: WidgetSharedData],
        now: Date = Date(),
        calendar: Calendar = .current
    ) async -> IOSLiveActivitySyncOutcome {
        guard ActivityAuthorizationInfo().areActivitiesEnabled,
              settings.isWithinDisplayWindow(now: now, calendar: calendar),
              let window = settings.displayWindow(containing: now, calendar: calendar) else {
            return IOSLiveActivitySyncOutcome(
                registration: nil,
                endedActivityIDs: await endAll()
            )
        }

        let providers = LiveActivitySnapshotBuilder.providerSnapshots(
            configs: configs,
            dataByProvider: dataByProvider
        )

        guard !providers.isEmpty else {
            return IOSLiveActivitySyncOutcome(
                registration: nil,
                endedActivityIDs: await endAll()
            )
        }

        let selectedIndex = normalizedSelectedIndex(
            providers: providers,
            currentState: Self.currentActivity?.content.state
        )
        let state = DevBarQuotaActivityAttributes.ContentState(
            providers: providers,
            selectedIndex: selectedIndex,
            updatedAt: now,
            displayEndAt: window.end
        )

        if let activity = Self.currentActivity {
            await activity.update(ActivityContent(state: state, staleDate: state.displayEndAt))
            return IOSLiveActivitySyncOutcome(
                registration: Self.registration(for: activity, state: state),
                endedActivityIDs: []
            )
        } else {
            let result = await start(state: state)
            return IOSLiveActivitySyncOutcome(
                registration: result.activity.flatMap {
                    Self.registration(for: $0, state: state)
                },
                endedActivityIDs: result.endedActivityIDs
            )
        }
    }

    func endAll() async -> [String] {
        let activities = Activity<DevBarQuotaActivityAttributes>.activities
        for activity in activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        return activities.map(\.id)
    }

    private func start(
        state: DevBarQuotaActivityAttributes.ContentState
    ) async -> (activity: Activity<DevBarQuotaActivityAttributes>?, endedActivityIDs: [String]) {
        let endedActivityIDs = await endAll()

        do {
            let activity = try Activity.request(
                attributes: DevBarQuotaActivityAttributes(),
                content: ActivityContent(state: state, staleDate: state.displayEndAt),
                pushType: .token
            )
            return (activity, endedActivityIDs)
        } catch {
            print("[DevBar:LiveActivity] failed to start: \(error)")
            return (nil, endedActivityIDs)
        }
    }

    private func normalizedSelectedIndex(
        providers: [LiveActivityProviderSnapshot],
        currentState: DevBarQuotaActivityAttributes.ContentState?
    ) -> Int {
        guard let currentProvider = currentState?.selectedProvider else { return 0 }
        return providers.firstIndex(where: { $0.providerRawValue == currentProvider.providerRawValue }) ?? 0
    }

    static var currentActivity: Activity<DevBarQuotaActivityAttributes>? {
        Activity<DevBarQuotaActivityAttributes>.activities.first
    }

    static func registration(
        for activity: Activity<DevBarQuotaActivityAttributes>,
        state: DevBarQuotaActivityAttributes.ContentState? = nil
    ) -> LiveActivityPushRegistration? {
        guard let pushToken = activity.pushToken else { return nil }
        let contentState = state ?? activity.content.state
        return LiveActivityPushRegistration(
            activityId: activity.id,
            activityType: .devBarQuota,
            activityPushToken: pushToken.map { String(format: "%02x", $0) }.joined(),
            bundleId: Bundle.main.bundleIdentifier ?? "cc.xjpz.DevBariOS",
            environment: pushEnvironment,
            startedBy: .local,
            scheduledEndAtEpochSeconds: Int64(contentState.displayEndAt.timeIntervalSince1970),
            contentState: contentState
        )
    }

    static func cycleProviderFromIntent() async {
        guard let activity = currentActivity else { return }
        let nextState = activity.content.state.cyclingProvider()
        await activity.update(ActivityContent(state: nextState, staleDate: nextState.displayEndAt))
    }

    private static var pushEnvironment: PushEnvironment {
        #if DEBUG
        .development
        #else
        .production
        #endif
    }
}
