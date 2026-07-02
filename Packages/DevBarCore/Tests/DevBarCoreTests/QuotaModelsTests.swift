import Foundation
import Testing
@testable import DevBarCore

@Test
func quotaDataConvertsToWidgetData() {
    let data = QuotaData(
        limits: [
            QuotaLimit(
                type: "TOKENS_LIMIT",
                unit: 3,
                number: 5,
                usage: 2,
                currentValue: 2,
                remaining: 3,
                percentage: 40,
                nextResetTime: 1_710_000_000_000,
                usageDetails: []
            ),
        ],
        level: "pro"
    )

    let widgetData = data.toWidgetData(
        subscriptionName: "Pro",
        subscriptionPrice: "¥99",
        subscriptionExpireDate: "2026-12-31"
    )

    #expect(widgetData.provider == .glm)
    #expect(widgetData.level == "pro")
    #expect(widgetData.limits.count == 1)
    #expect(widgetData.subscriptionName == "Pro")
}

@Test
func openAIWindowDisplayNameUsesWindowLength() {
    let weekly = OpenAIUsageWindow(
        usedPercent: 25,
        limitWindowSeconds: 7 * 24 * 3600,
        resetAfterSeconds: nil,
        resetAt: nil
    )
    let daily = OpenAIUsageWindow(
        usedPercent: 50,
        limitWindowSeconds: 24 * 3600,
        resetAfterSeconds: nil,
        resetAt: nil
    )

    #expect(!weekly.displayName.isEmpty)
    #expect(!daily.displayName.isEmpty)
    #expect(weekly.displayName != daily.displayName)
}

@Test
func providerQuotaSnapshotDoesNotReplaceNewerLocalData() {
    let localUpdatedAt = Date(timeIntervalSince1970: 200)
    let staleRelaySnapshot = ProviderQuotaSnapshot(
        accountID: "openai",
        provider: .openai,
        displayName: "OpenAI",
        limits: [
            WidgetQuotaLimit(
                type: "OPENAI_SESSION",
                displayName: "Session",
                percentage: 20,
                unitDescription: nil,
                formattedResetTime: nil
            ),
        ],
        level: "Pro",
        subscriptionName: nil,
        subscriptionExpireDate: nil,
        fetchedAt: Date(timeIntervalSince1970: 100)
    )
    let freshRelaySnapshot = ProviderQuotaSnapshot(
        accountID: "openai",
        provider: .openai,
        displayName: "OpenAI",
        limits: staleRelaySnapshot.limits,
        level: "Pro",
        subscriptionName: nil,
        subscriptionExpireDate: nil,
        fetchedAt: localUpdatedAt
    )

    #expect(staleRelaySnapshot.shouldReplace(existing: nil as ProviderQuotaSnapshot?, localLastUpdated: localUpdatedAt) == false)
    #expect(freshRelaySnapshot.shouldReplace(existing: nil as ProviderQuotaSnapshot?, localLastUpdated: localUpdatedAt) == true)
}
