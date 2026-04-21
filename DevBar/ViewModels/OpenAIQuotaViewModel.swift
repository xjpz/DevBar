// OpenAIQuotaViewModel.swift
// DevBar

import Foundation
import Combine
import WidgetKit

@MainActor
final class OpenAIQuotaViewModel: ObservableObject {
    @Published var usageResponse: OpenAIUsageResponse?
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var lastUpdated: Date?

    private let apiClient = OpenAIAPIClient()
    private var isRefreshing = false

    var planType: String? { usageResponse?.planType }

    var quotaRows: [QuotaRowItem] {
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

    var isLimitReached: Bool {
        usageResponse?.rateLimit?.limitReached == true
    }

    // MARK: - Data Fetching

    func fetchUsage(silent: Bool = false) async {
        guard !isRefreshing else { return }

        let keychain = KeychainService.shared
        guard let accessToken = keychain.load(key: Constants.Keychain.openAIAccessTokenKey),
              !accessToken.isEmpty else {
            errorMessage = String(localized: "openai_token_required")
            return
        }

        let accountId = UserDefaults.standard.string(forKey: Constants.OpenAI.accountIdKey)

        do {
            _ = try await fetchUsage(accessToken: accessToken, accountId: accountId, silent: silent)
        } catch {
            return
        }
    }

    @discardableResult
    func fetchUsage(accessToken: String, accountId: String?, silent: Bool = false) async throws -> OpenAIUsageResponse {
        guard !isRefreshing else { throw APIError.invalidResponse }

        isRefreshing = true
        if !silent { isLoading = true }
        errorMessage = nil

        do {
            let response = try await apiClient.fetchUsage(
                accessToken: accessToken,
                accountId: accountId
            )
            usageResponse = response
            lastUpdated = Date()
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

    func resetForLogout() {
        usageResponse = nil
        isLoading = false
        errorMessage = nil
        lastUpdated = nil
        isRefreshing = false
        WidgetDataManager.shared.clearSharedData(for: "openai")
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: - Widget Data

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
            level: response.planType,
            subscriptionName: nil,
            subscriptionPrice: nil,
            subscriptionExpireDate: nil,
            lastUpdated: Date()
        )
        WidgetDataManager.shared.saveAndReload(data, for: "openai")
    }
}
