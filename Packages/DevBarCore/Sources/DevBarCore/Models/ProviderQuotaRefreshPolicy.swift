import Foundation

public enum ProviderQuotaRefreshPolicy {
    /// Returns providers whose own latest data is older than the configured
    /// interval. A fresh provider must not hide another provider's stale data.
    public static func providersNeedingRefresh(
        _ providers: [QuotaProvider],
        latestRefreshByProvider: [QuotaProvider: Date],
        interval: TimeInterval,
        now: Date = Date()
    ) -> Set<QuotaProvider> {
        guard interval > 0 else { return [] }

        return Set(providers.filter { provider in
            guard let latestRefresh = latestRefreshByProvider[provider] else {
                return true
            }
            let elapsed = now.timeIntervalSince(latestRefresh)
            return elapsed < 0 || elapsed >= interval
        })
    }

    /// Calculates the next foreground timer delay from each provider's own
    /// successful refresh or most recent attempt. Failed requests therefore
    /// retry after the configured interval instead of spinning immediately.
    public static func nextRefreshDelay(
        _ providers: [QuotaProvider],
        latestRefreshByProvider: [QuotaProvider: Date],
        latestAttemptByProvider: [QuotaProvider: Date],
        interval: TimeInterval,
        minimumDelay: TimeInterval = 1,
        now: Date = Date()
    ) -> TimeInterval? {
        guard interval > 0, !providers.isEmpty else { return nil }
        let clampedMinimumDelay = max(0, minimumDelay)

        return providers.map { provider in
            let referenceDate = [
                latestRefreshByProvider[provider],
                latestAttemptByProvider[provider],
            ]
            .compactMap { $0 }
            .max()

            guard let referenceDate else { return clampedMinimumDelay }
            let elapsed = now.timeIntervalSince(referenceDate)
            guard elapsed >= 0 else { return clampedMinimumDelay }
            return max(clampedMinimumDelay, interval - elapsed)
        }
        .min()
    }
}
