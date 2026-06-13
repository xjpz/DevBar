import Combine
import Foundation
import WidgetKit

@MainActor
public final class DeepSeekQuotaViewModel: ObservableObject {
    @Published public var usageResponse: DeepSeekUsageResponse?
    @Published public var isLoading = false
    @Published public var errorMessage: String?
    @Published public var lastUpdated: Date?

    private let apiClient: DeepSeekAPIClient
    private let cacheStore: QuotaCacheStore
    private var isRefreshing = false

    public init(
        apiClient: DeepSeekAPIClient = DeepSeekAPIClient(),
        cacheStore: QuotaCacheStore = UserDefaultsQuotaCacheStore()
    ) {
        self.apiClient = apiClient
        self.cacheStore = cacheStore
        restoreCachedState()
    }

    public var usageData: DeepSeekUsageData? {
        usageResponse?.data?.bizData
    }

    public var quotaRows: [QuotaRowItem] {
        usageData?.quotaRows ?? []
    }

    public var balanceText: String? {
        guard let data = usageData else { return nil }
        return String(format: "\u{00a5}%.4f", data.totalBalanceCNY)
    }

    public func fetchUsage(
        token: String,
        cookieString: String,
        silent: Bool = false
    ) async {
        guard !isRefreshing else { return }

        isRefreshing = true
        if !silent { isLoading = true }
        errorMessage = nil

        do {
            let response = try await apiClient.fetchUsage(token: token, cookieString: cookieString)
            usageResponse = response
            lastUpdated = Date()
            persistCache()
            saveWidgetData()
            isLoading = false
            isRefreshing = false
        } catch let error as APIError {
            errorMessage = error.errorDescription
            isLoading = false
            isRefreshing = false
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
            isRefreshing = false
        }
    }

    public func resetForLogout() {
        usageResponse = nil
        isLoading = false
        errorMessage = nil
        lastUpdated = nil
        isRefreshing = false
        cacheStore.clearDeepSeekSnapshot()
        WidgetDataManager.shared.clearSharedData(for: "deepseek")
        WidgetCenter.shared.reloadAllTimelines()
    }

    public func restoreCachedState() {
        guard let snapshot = cacheStore.loadDeepSeekSnapshot() else { return }
        usageResponse = snapshot.usageResponse
        lastUpdated = snapshot.lastUpdated
    }

    private func persistCache() {
        let snapshot = DeepSeekQuotaCacheSnapshot(
            usageResponse: usageResponse,
            lastUpdated: lastUpdated
        )
        cacheStore.saveDeepSeekSnapshot(snapshot)
    }

    private func saveWidgetData() {
        guard let data = usageData else { return }
        let widgetData = WidgetSharedData(
            provider: .deepseek,
            schemaVersion: WidgetSharedData.currentSchemaVersion,
            limits: data.quotaRows.map {
                WidgetQuotaLimit(
                    type: $0.name,
                    displayName: $0.name,
                    percentage: $0.percentage,
                    unitDescription: $0.unitDescription,
                    formattedResetTime: nil
                )
            },
            level: nil,
            subscriptionName: nil,
            subscriptionPrice: String(format: "\u{00a5}%.4f", data.totalBalanceCNY),
            subscriptionExpireDate: nil,
            lastUpdated: Date()
        )
        WidgetDataManager.shared.saveAndReload(widgetData, for: "deepseek")
    }
}
