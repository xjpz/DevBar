import Foundation

public enum LiveActivityLimitKind: String, Codable, Hashable, Sendable {
    case fiveHour = "H"
    case weekly = "W"
    case monthly = "M"
}

public struct LiveActivityLimitSnapshot: Codable, Hashable, Identifiable, Sendable {
    public var id: String { kind.rawValue }

    public let kind: LiveActivityLimitKind
    public let title: String
    public let percentage: Int
    public let resetText: String?

    public init(kind: LiveActivityLimitKind, title: String, percentage: Int, resetText: String?) {
        self.kind = kind
        self.title = title
        self.percentage = min(max(percentage, 0), 100)
        self.resetText = resetText
    }
}

public struct LiveActivityProviderSnapshot: Codable, Hashable, Identifiable, Sendable {
    public var id: String { providerRawValue }

    public let providerRawValue: String
    public let providerName: String
    public let planName: String?
    public let limits: [LiveActivityLimitSnapshot]

    public init(
        providerRawValue: String,
        providerName: String,
        planName: String?,
        limits: [LiveActivityLimitSnapshot]
    ) {
        self.providerRawValue = providerRawValue
        self.providerName = providerName
        self.planName = planName
        self.limits = limits
    }
}

#if os(iOS) && canImport(ActivityKit)
import ActivityKit
import AppIntents

public struct DevBarQuotaActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable, Sendable {
        public var providers: [LiveActivityProviderSnapshot]
        public var selectedIndex: Int
        public var updatedAt: Date
        public var displayEndAt: Date

        public init(
            providers: [LiveActivityProviderSnapshot],
            selectedIndex: Int,
            updatedAt: Date,
            displayEndAt: Date
        ) {
            self.providers = providers
            self.selectedIndex = selectedIndex
            self.updatedAt = updatedAt
            self.displayEndAt = displayEndAt
        }

        public var selectedProvider: LiveActivityProviderSnapshot? {
            guard providers.indices.contains(selectedIndex) else {
                return providers.first
            }
            return providers[selectedIndex]
        }

        public var hasMultipleProviders: Bool {
            providers.count > 1
        }

        public func cyclingProvider() -> Self {
            guard providers.count > 1 else { return self }
            var copy = self
            copy.selectedIndex = (selectedIndex + 1) % providers.count
            copy.updatedAt = Date()
            return copy
        }
    }

    public let title: String

    public init(title: String = "DevBar") {
        self.title = title
    }
}

public struct CycleLiveActivityProviderIntent: LiveActivityIntent {
    public static var title: LocalizedStringResource { "Next Provider" }
    public static var description: IntentDescription { "Show the next enabled Provider in DevBar live activity." }

    @Parameter(title: "Activity ID")
    public var activityID: String

    public init() {
        self.activityID = ""
    }

    public init(activityID: String) {
        self.activityID = activityID
    }

    public func perform() async throws -> some IntentResult {
        let activities = Activity<DevBarQuotaActivityAttributes>.activities
        guard let activity = activities.first(where: { $0.id == activityID }) ?? activities.first else {
            return .result()
        }
        let nextState = activity.content.state.cyclingProvider()
        await activity.update(ActivityContent(state: nextState, staleDate: nextState.displayEndAt))
        return .result()
    }
}
#endif
