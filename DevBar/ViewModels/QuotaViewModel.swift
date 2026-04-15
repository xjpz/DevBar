// QuotaViewModel.swift
// DevBar

import Foundation
import Combine

@MainActor
final class QuotaViewModel: ObservableObject {
    @Published var quotaData: QuotaData?
    @Published var subscription: Subscription?
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var lastUpdated: Date?

    private let apiClient = BigModelAPIClient()
    private var isRefreshing = false
    private var refreshTimer: Timer?

    /// Whether the user has a valid active subscription
    var hasValidSubscription: Bool {
        subscription?.isValid == true
    }

    /// The highest usage percentage across all limits for menu bar display
    var statusText: String {
        guard hasValidSubscription else { return "DevBar" }
        guard let data = quotaData, let limits = data.limits, !limits.isEmpty else {
            return "DevBar"
        }
        let maxPercentage = limits.map(\.percentage).max() ?? 0
        return "\(maxPercentage)%"
    }

    // MARK: - Initial Load (subscription first, then quota)

    func loadInitialData(credentials: AuthCredentials?) async {
        guard let credentials else {
            errorMessage = "未登录"
            return
        }

        isLoading = true
        errorMessage = nil
        quotaData = nil
        subscription = nil

        // Step 1: Fetch subscription list
        do {
            let subscriptions = try await apiClient.fetchSubscriptionList(credentials: credentials)
            subscription = subscriptions.first(where: { $0.isValid })
            print("[DevBar] Subscription check: valid=\(hasValidSubscription), name=\(subscription?.productName ?? "nil")")
        } catch {
            print("[DevBar] Subscription fetch error: \(error.localizedDescription)")
            isLoading = false
            errorMessage = error.localizedDescription
            return
        }

        // Step 2: Only fetch quota if subscription is valid
        guard hasValidSubscription else {
            isLoading = false
            print("[DevBar] No valid subscription, skipping quota fetch")
            return
        }

        await fetchQuota(credentials: credentials)
    }

    // MARK: - Fetch Quota

    func fetchQuota(credentials: AuthCredentials?) async {
        guard !isRefreshing else { return }
        guard let credentials else {
            errorMessage = "未登录"
            return
        }

        isRefreshing = true
        if isLoading { /* already true from loadInitialData */ } else {
            isLoading = true
        }
        errorMessage = nil

        do {
            quotaData = try await apiClient.fetchQuotaLimit(credentials: credentials)
            lastUpdated = Date()
        } catch let error as APIError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
        isRefreshing = false
    }

    // MARK: - Auto Refresh

    func startAutoRefresh(credentials: AuthCredentials?, interval: TimeInterval, onFetchComplete: (@Sendable @MainActor () -> Void)? = nil) {
        guard refreshTimer == nil else { return }

        // Initial load: subscription check + quota
        Task {
            await loadInitialData(credentials: credentials)
            onFetchComplete?()
        }

        // Periodic refresh: quota only (subscription doesn't change often)
        refreshTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task {
                guard self.hasValidSubscription else { return }
                await self.fetchQuota(credentials: credentials)
                onFetchComplete?()
            }
        }
    }

    func stopAutoRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }
}
