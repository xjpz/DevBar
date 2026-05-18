import ActivityKit
import DevBarCore
import Foundation

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
    ) async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled,
              settings.isWithinDisplayWindow(now: now, calendar: calendar),
              let window = settings.displayWindow(containing: now, calendar: calendar) else {
            await endAll()
            return
        }

        let providers = LiveActivitySnapshotBuilder.providerSnapshots(
            configs: configs,
            dataByProvider: dataByProvider
        )

        guard !providers.isEmpty else {
            await endAll()
            return
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
        } else {
            await start(state: state)
        }
    }

    func endAll() async {
        for activity in Activity<DevBarQuotaActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    private func start(state: DevBarQuotaActivityAttributes.ContentState) async {
        await endAll()

        do {
            _ = try Activity.request(
                attributes: DevBarQuotaActivityAttributes(),
                content: ActivityContent(state: state, staleDate: state.displayEndAt),
                pushType: nil
            )
        } catch {
            print("[DevBar:LiveActivity] failed to start: \(error)")
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

    static func cycleProviderFromIntent() async {
        guard let activity = currentActivity else { return }
        let nextState = activity.content.state.cyclingProvider()
        await activity.update(ActivityContent(state: nextState, staleDate: nextState.displayEndAt))
    }
}
