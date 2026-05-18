import Foundation

public enum LiveActivitySnapshotBuilder {
    public static func providerSnapshots(
        configs: [AccountConfig],
        dataByProvider: [WidgetProvider: WidgetSharedData]
    ) -> [LiveActivityProviderSnapshot] {
        configs
            .filter(\.isEnabled)
            .sorted { $0.order < $1.order }
            .compactMap { config -> LiveActivityProviderSnapshot? in
                guard let widgetProvider = WidgetProvider(rawValue: config.provider.rawValue),
                      let data = dataByProvider[widgetProvider] else {
                    return nil
                }
                return providerSnapshot(provider: config.provider, data: data)
            }
    }

    public static func providerSnapshot(provider: QuotaProvider, data: WidgetSharedData) -> LiveActivityProviderSnapshot? {
        let limits = visibleLimits(from: data.limits)
        guard !limits.isEmpty else { return nil }

        return LiveActivityProviderSnapshot(
            providerRawValue: provider.rawValue,
            providerName: provider.localizedName,
            planName: normalizedPlanName(from: data),
            limits: limits
        )
    }

    public static func visibleLimits(from limits: [WidgetQuotaLimit]) -> [LiveActivityLimitSnapshot] {
        var selected: [LiveActivityLimitKind: LiveActivityLimitSnapshot] = [:]

        for limit in limits {
            guard let kind = kind(for: limit) else { continue }
            if selected[kind] == nil {
                selected[kind] = LiveActivityLimitSnapshot(
                    kind: kind,
                    title: title(for: kind),
                    percentage: limit.percentage,
                    resetText: limit.formattedResetTime
                )
            }
        }

        return [.fiveHour, .weekly, .monthly].compactMap { selected[$0] }
    }

    private static func normalizedPlanName(from data: WidgetSharedData) -> String? {
        let candidates = [data.level, data.subscriptionName]
        return candidates
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
    }

    private static func kind(for limit: WidgetQuotaLimit) -> LiveActivityLimitKind? {
        let value = "\(limit.type) \(limit.displayName)".lowercased()

        if value.contains("5h") || value.contains("5 h") || value.contains("5小时") {
            return .fiveHour
        }
        if value.contains("weekly") || value.contains("week") || value.contains("每周") || value.contains("周") {
            return .weekly
        }
        if value.contains("monthly") || value.contains("month") || value.contains("每月") || value.contains("月") {
            return .monthly
        }
        return nil
    }

    private static func title(for kind: LiveActivityLimitKind) -> String {
        switch kind {
        case .fiveHour:
            return "5h"
        case .weekly:
            return "Weekly"
        case .monthly:
            return "Monthly"
        }
    }
}
