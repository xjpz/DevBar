import Combine
import Foundation
import WidgetKit

@MainActor
public final class QuotaViewModel: ObservableObject {
    @Published public var quotaData: QuotaData?
    @Published public var subscription: Subscription?
    @Published public var isLoading = false
    @Published public var errorMessage: String?
    @Published public var lastUpdated: Date?

    private let apiClient = BigModelAPIClient()
    private let cacheStore: QuotaCacheStore
    private var isRefreshing = false
    private var refreshTimer: Timer?
    private var initialDataLoaded = false

    public init(cacheStore: QuotaCacheStore = UserDefaultsQuotaCacheStore()) {
        self.cacheStore = cacheStore
        restoreCachedState()
    }

    public var hasValidSubscription: Bool {
        if let subscription {
            return subscription.isValid
        }
        return quotaData != nil
    }

    public var statusText: String {
        if let subscription, !subscription.isValid { return "DevBar" }
        guard let data = quotaData, let limits = data.limits, !limits.isEmpty else {
            return "DevBar"
        }
        let maxPercentage = limits.map(\.percentage).max() ?? 0
        return "\(maxPercentage)%"
    }

    public func loadInitialData(credentials: AuthCredentials?) async {
        guard let credentials else {
            errorMessage = String(localized: "not_logged_in")
            return
        }

        if quotaData == nil && subscription == nil {
            isLoading = true
        }
        errorMessage = nil

        if credentials.cookieString.isEmpty {
            subscription = nil
            await fetchQuota(credentials: credentials)
            initialDataLoaded = true
            return
        }

        do {
            let subscriptions = try await apiClient.fetchSubscriptionList(credentials: credentials)
            subscription = subscriptions.first(where: { $0.isValid })
            persistCache()
        } catch {
            isLoading = false
            errorMessage = error.localizedDescription
            return
        }

        guard hasValidSubscription else {
            quotaData = nil
            lastUpdated = nil
            persistCache()
            isLoading = false
            initialDataLoaded = true
            return
        }

        await fetchQuota(credentials: credentials)
        initialDataLoaded = true
    }

    public func resetForLogout() {
        stopAutoRefresh()
        quotaData = nil
        subscription = nil
        isLoading = false
        errorMessage = nil
        lastUpdated = nil
        initialDataLoaded = false
        isRefreshing = false
        cacheStore.clearGLMSnapshot()
        WidgetDataManager.shared.clearSharedData()
        WidgetCenter.shared.reloadAllTimelines()
    }

    public func fetchQuota(credentials: AuthCredentials?, silent: Bool = false) async {
        guard !isRefreshing else { return }
        guard let credentials else {
            errorMessage = String(localized: "not_logged_in")
            return
        }

        isRefreshing = true
        if !silent && !isLoading {
            isLoading = true
        }
        errorMessage = nil

        do {
            quotaData = try await apiClient.fetchQuotaLimit(credentials: credentials)
            lastUpdated = Date()
            persistCache()
            let widgetData = quotaData?.toWidgetData(
                subscriptionName: subscription?.productName,
                subscriptionPrice: subscription?.formattedRenewPrice,
                subscriptionExpireDate: subscription?.formattedNextRenewDate
            )
            if let widgetData {
                WidgetDataManager.shared.saveAndReload(widgetData, for: "glm")
            }
        } catch let error as APIError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
        isRefreshing = false
    }

    public func startAutoRefresh(
        credentials: AuthCredentials?,
        interval: TimeInterval,
        onFetchComplete: (@Sendable @MainActor () -> Void)? = nil
    ) {
        guard refreshTimer == nil else { return }

        if !initialDataLoaded {
            Task {
                await loadInitialData(credentials: credentials)
                onFetchComplete?()
            }
        }

        refreshTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                guard self.hasValidSubscription else { return }
                await self.fetchQuota(credentials: credentials, silent: true)
                onFetchComplete?()
            }
        }
    }

    public func stopAutoRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    public func restoreCachedState() {
        guard let snapshot = cacheStore.loadGLMSnapshot() else { return }
        quotaData = snapshot.quotaData
        subscription = snapshot.subscription
        lastUpdated = snapshot.lastUpdated
    }

    private func persistCache() {
        let snapshot = GLMQuotaCacheSnapshot(
            quotaData: quotaData,
            subscription: subscription,
            lastUpdated: lastUpdated
        )
        cacheStore.saveGLMSnapshot(snapshot)
    }
}
