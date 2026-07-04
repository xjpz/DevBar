import Combine
import Foundation
import WidgetKit

@MainActor
public final class OpenAIQuotaViewModel: ObservableObject {
    @Published public var usageResponse: OpenAIUsageResponse?
    @Published public var isLoading = false
    @Published public var errorMessage: String?
    @Published public var lastUpdated: Date?

    private let apiClient = OpenAIAPIClient()
    private let cacheStore: QuotaCacheStore
    private var isRefreshing = false

    public init(cacheStore: QuotaCacheStore = UserDefaultsQuotaCacheStore()) {
        self.cacheStore = cacheStore
        restoreCachedState()
    }

    public var planType: String? { usageResponse?.displayPlanType }

    public var availableResetCount: Int? {
        usageResponse?.availableResetCount
    }

    public var quotaRows: [QuotaRowItem] {
        guard let rateLimit = usageResponse?.rateLimit else { return [] }
        var rows: [QuotaRowItem] = []

        if let primary = rateLimit.primaryWindow {
            rows.append(QuotaRowItem(
                name: primary.displayName,
                percentage: primary.usedPercent,
                resetTime: primary.formattedResetTime,
                unitDescription: nil
            ))
        }

        if let secondary = rateLimit.secondaryWindow {
            rows.append(QuotaRowItem(
                name: secondary.displayName,
                percentage: secondary.usedPercent,
                resetTime: secondary.formattedResetTime,
                unitDescription: nil
            ))
        }

        return rows
    }

    public var isLimitReached: Bool {
        usageResponse?.rateLimit?.limitReached == true
    }

    public func fetchUsage(
        storedAccessToken: String? = KeychainService.shared.load(key: DevBarCoreConstants.Keychain.openAIAccessTokenKey),
        storedAccountId: String? = UserDefaults.standard.string(forKey: DevBarCoreConstants.OpenAI.accountIdKey),
        silent: Bool = false
    ) async {
        guard !isRefreshing else { return }
        guard let accessToken = storedAccessToken, !accessToken.isEmpty else {
            errorMessage = String(localized: "openai_token_required")
            return
        }

        do {
            _ = try await fetchUsage(accessToken: accessToken, accountId: storedAccountId, silent: silent)
        } catch {
            return
        }
    }

    @discardableResult
    public func fetchUsage(accessToken: String, accountId: String?, silent: Bool = false) async throws -> OpenAIUsageResponse {
        guard !isRefreshing else { throw APIError.invalidResponse }

        isRefreshing = true
        if !silent { isLoading = true }
        errorMessage = nil

        do {
            let response = try await fetchUsageInBackground(accessToken: accessToken, accountId: accountId)
            usageResponse = response
            lastUpdated = Date()
            persistCache()
            saveWidgetData()
            isLoading = false
            isRefreshing = false
            return response
        } catch let error as APIError {
            errorMessage = error.errorDescription
            isLoading = false
            isRefreshing = false
            throw error
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
            isRefreshing = false
            throw error
        }
    }

    private func fetchUsageInBackground(accessToken: String, accountId: String?) async throws -> OpenAIUsageResponse {
        let apiClient = self.apiClient
        let task = Task.detached(priority: .utility) {
            try Task.checkCancellation()
            return try await apiClient.fetchUsage(accessToken: accessToken, accountId: accountId)
        }

        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }

    public func resetForLogout() {
        usageResponse = nil
        isLoading = false
        errorMessage = nil
        lastUpdated = nil
        isRefreshing = false
        cacheStore.clearOpenAISnapshot()
        WidgetDataManager.shared.clearSharedData(for: "openai")
        WidgetCenter.shared.reloadAllTimelines()
    }

    public func restoreCachedState() {
        guard let snapshot = cacheStore.loadOpenAISnapshot() else { return }
        usageResponse = snapshot.usageResponse
        lastUpdated = snapshot.lastUpdated
        saveWidgetData()
    }

    private func persistCache() {
        let snapshot = OpenAIQuotaCacheSnapshot(
            usageResponse: usageResponse,
            lastUpdated: lastUpdated
        )
        cacheStore.saveOpenAISnapshot(snapshot)
    }

    private func saveWidgetData() {
        guard let response = usageResponse else { return }

        var limits: [WidgetQuotaLimit] = []
        if let rateLimit = response.rateLimit {
            if let primary = rateLimit.primaryWindow {
                limits.append(WidgetQuotaLimit(
                    type: "OPENAI_SESSION",
                    displayName: primary.displayName,
                    percentage: primary.usedPercent,
                    unitDescription: nil,
                    formattedResetTime: primary.formattedResetTime
                ))
            }
            if let secondary = rateLimit.secondaryWindow {
                limits.append(WidgetQuotaLimit(
                    type: "OPENAI_WEEKLY",
                    displayName: secondary.displayName,
                    percentage: secondary.usedPercent,
                    unitDescription: nil,
                    formattedResetTime: secondary.formattedResetTime
                ))
            }
        }

        let data = WidgetSharedData(
            provider: .openai,
            schemaVersion: WidgetSharedData.currentSchemaVersion,
            limits: limits,
            level: response.displayPlanType,
            subscriptionName: nil,
            subscriptionPrice: nil,
            subscriptionExpireDate: nil,
            availableResetCount: response.availableResetCount,
            lastUpdated: Date()
        )
        WidgetDataManager.shared.saveAndReload(data, for: "openai")
    }
}
