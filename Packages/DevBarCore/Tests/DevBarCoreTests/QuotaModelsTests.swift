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
