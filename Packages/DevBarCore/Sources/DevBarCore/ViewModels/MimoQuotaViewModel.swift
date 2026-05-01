import Combine
import Foundation
import WidgetKit

@MainActor
public final class MimoQuotaViewModel: ObservableObject {
    @Published public var usageResponse: MimoUsageResponse?
    @Published public var planDetail: MimoPlanDetail?
    @Published public var isLoading = false
    @Published public var isLoadingDetail = false
    @Published public var errorMessage: String?
    @Published public var lastUpdated: Date?
    @Published public var detailLastFetchedAt: Date?

    private let apiClient: MimoAPIClient
    private let cacheStore: QuotaCacheStore
    private var isRefreshing = false
    private var isRefreshingDetail = false
    private let detailRefreshInterval: TimeInterval = 24 * 60 * 60

    public init(
        apiClient: MimoAPIClient = MimoAPIClient(),
        cacheStore: QuotaCacheStore = UserDefaultsQuotaCacheStore()
    ) {
        self.apiClient = apiClient
        self.cacheStore = cacheStore
        restoreCachedState()
    }

    public var planName: String? {
        let value = planDetail?.planName?.trimmingCharacters(in: .whitespacesAndNewlines)
        return value?.isEmpty == false ? value : CoreL10n.text("mimo_token_plan")
    }

    public var currentPeriodEnd: Date? {
        planDetail?.currentPeriodEndDate
    }

    public var quotaRows: [QuotaRowItem] {
        usageResponse?.quotaRows ?? []
    }

    public func fetchUsage(
        storedServiceToken: String? = KeychainService.shared.load(key: DevBarCoreConstants.Keychain.mimoServiceTokenKey),
        silent: Bool = false
    ) async {
        guard let serviceToken = storedServiceToken, !serviceToken.isEmpty else {
            errorMessage = CoreL10n.text("mimo_cookie_required")
            return
        }

        do {
            _ = try await fetchUsage(serviceToken: serviceToken, silent: silent)
        } catch {
            return
        }
    }

    @discardableResult
    public func fetchUsage(serviceToken: String, silent: Bool = false) async throws -> MimoUsageResponse {
        guard !isRefreshing else { throw APIError.invalidResponse }

        isRefreshing = true
        if !silent { isLoading = true }
        errorMessage = nil

        do {
            let response = try await apiClient.fetchUsage(serviceToken: serviceToken)
            usageResponse = response
            lastUpdated = Date()
            persistCache()
            saveWidgetData()
            isLoading = false
            isRefreshing = false
            await fetchPlanDetailIfNeeded(serviceToken: serviceToken)
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

    public func fetchPlanDetailIfNeeded(serviceToken: String, force: Bool = false) async {
        guard force || shouldFetchPlanDetail() else { return }
        await fetchPlanDetail(serviceToken: serviceToken)
    }

    public func shouldFetchPlanDetail(now: Date = Date()) -> Bool {
        guard let detailLastFetchedAt else { return true }
        return now.timeIntervalSince(detailLastFetchedAt) >= detailRefreshInterval
    }

    public func resetForLogout() {
        usageResponse = nil
        planDetail = nil
        isLoading = false
        isLoadingDetail = false
        errorMessage = nil
        lastUpdated = nil
        detailLastFetchedAt = nil
        isRefreshing = false
        isRefreshingDetail = false
        cacheStore.clearMimoSnapshot()
        WidgetDataManager.shared.clearSharedData(for: "mimo")
        WidgetCenter.shared.reloadAllTimelines()
    }

    public func restoreCachedState() {
        guard let snapshot = cacheStore.loadMimoSnapshot() else { return }
        usageResponse = snapshot.usageResponse
        planDetail = snapshot.planDetail
        lastUpdated = snapshot.lastUpdated
        detailLastFetchedAt = snapshot.detailLastFetchedAt
    }

    private func fetchPlanDetail(serviceToken: String) async {
        guard !isRefreshingDetail else { return }
        isRefreshingDetail = true
        isLoadingDetail = true

        defer {
            isRefreshingDetail = false
            isLoadingDetail = false
        }

        do {
            let response = try await apiClient.fetchPlanDetail(serviceToken: serviceToken)
            planDetail = response.data
            detailLastFetchedAt = Date()
            persistCache()
        } catch {
            if errorMessage == nil {
                errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    private func persistCache() {
        let snapshot = MimoQuotaCacheSnapshot(
            usageResponse: usageResponse,
            planDetail: planDetail,
            lastUpdated: lastUpdated,
            detailLastFetchedAt: detailLastFetchedAt
        )
        cacheStore.saveMimoSnapshot(snapshot)
    }

    private func saveWidgetData() {
        guard let response = usageResponse else { return }
        let data = WidgetSharedData(
            provider: .mimo,
            schemaVersion: WidgetSharedData.currentSchemaVersion,
            limits: response.quotaRows.map {
                WidgetQuotaLimit(
                    type: $0.name,
                    displayName: $0.name,
                    percentage: $0.percentage,
                    unitDescription: $0.unitDescription,
                    formattedResetTime: nil
                )
            },
            level: planName,
            subscriptionName: planName,
            subscriptionPrice: nil,
            subscriptionExpireDate: planDetail?.currentPeriodEnd,
            lastUpdated: Date()
        )
        WidgetDataManager.shared.saveAndReload(data, for: "mimo")
    }
}
