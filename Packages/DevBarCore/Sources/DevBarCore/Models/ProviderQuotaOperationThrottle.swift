import Foundation

/// Debounces quota refreshes and quota snapshot synchronization.
///
/// Refreshes share one global window because every refresh updates all enabled
/// providers. Snapshot synchronization is scoped by peer and account so a
/// second iPhone or account is not delayed by an unrelated transfer.
public struct ProviderQuotaOperationThrottle: Sendable {
    public static let minimumSupportedInterval: TimeInterval = 30

    public let minimumInterval: TimeInterval

    private var lastRefreshStartedAt: Date?
    private var lastSyncStartedAt: [SyncKey: Date] = [:]

    public init(minimumInterval: TimeInterval = Self.minimumSupportedInterval) {
        self.minimumInterval = max(Self.minimumSupportedInterval, minimumInterval)
    }

    public mutating func shouldStartRefresh(at now: Date = Date()) -> Bool {
        guard shouldAllow(previous: lastRefreshStartedAt, now: now) else {
            return false
        }
        lastRefreshStartedAt = now
        return true
    }

    public mutating func shouldStartSync(
        peerDeviceID: String,
        accountID: String,
        at now: Date = Date()
    ) -> Bool {
        let key = SyncKey(peerDeviceID: peerDeviceID, accountID: accountID)
        guard shouldAllow(previous: lastSyncStartedAt[key], now: now) else {
            return false
        }
        lastSyncStartedAt[key] = now
        return true
    }

    private func shouldAllow(previous: Date?, now: Date) -> Bool {
        guard let previous else { return true }
        let elapsed = now.timeIntervalSince(previous)
        return elapsed < 0 || elapsed >= minimumInterval
    }

    private struct SyncKey: Hashable, Sendable {
        let peerDeviceID: String
        let accountID: String
    }
}
