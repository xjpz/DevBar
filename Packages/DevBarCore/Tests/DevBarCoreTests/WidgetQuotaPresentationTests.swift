import Testing
@testable import DevBarCore

@Test
func widgetQuotaPresentationSortsGLMByFiveHourWeeklyThenMonthly() {
    let limits = [
        limit(type: "MCP_MONTHLY", name: "月度额度"),
        limit(type: "TIME_LIMIT", name: "5小时额度"),
        limit(type: "WEEKLY_LIMIT", name: "周额度"),
    ]

    let sorted = WidgetQuotaPresentation.sortedLimits(limits, provider: .glm)

    #expect(sorted.map(\.displayName) == ["5小时额度", "周额度", "月度额度"])
}

@Test
func widgetQuotaPresentationSortsOpenAIByFiveHourAndWeekly() {
    let limits = [
        limit(type: "TOKENS_LIMIT", name: "月度 Token"),
        limit(type: "OPENAI_WEEKLY", name: "Weekly Usage Limit"),
        limit(type: "OPENAI_SESSION", name: "5h Usage Limit"),
    ]

    let sorted = WidgetQuotaPresentation.sortedLimits(limits, provider: .openai)

    #expect(sorted.prefix(2).map(\.displayName) == ["5h Usage Limit", "Weekly Usage Limit"])
}

@Test
func widgetQuotaPresentationSortsMiMoMonthlyTokenFirst() {
    let limits = [
        limit(type: "OTHER_LIMIT", name: "Other"),
        limit(type: "month_total_token", name: "Monthly Token"),
    ]

    let sorted = WidgetQuotaPresentation.sortedLimits(limits, provider: .mimo)

    #expect(sorted.first?.displayName == "Monthly Token")
    #expect(WidgetQuotaPresentation.marker(for: sorted[0], provider: .mimo) == "M")
}

@Test
func widgetQuotaPresentationSortsDeepSeekCostBeforeToken() {
    let limits = [
        limit(type: "DEEPSEEK_TOKENS", name: "Token 预估额度"),
        limit(type: "DEEPSEEK_COST", name: "费用额度"),
    ]

    let sorted = WidgetQuotaPresentation.sortedLimits(limits, provider: .deepseek)

    #expect(sorted.map(\.displayName) == ["费用额度", "Token 预估额度"])
    #expect(WidgetQuotaPresentation.marker(for: sorted[0], provider: .deepseek) == "¥")
    #expect(WidgetQuotaPresentation.marker(for: sorted[1], provider: .deepseek) == "T")
}

private func limit(type: String, name: String) -> WidgetQuotaLimit {
    WidgetQuotaLimit(
        type: type,
        displayName: name,
        percentage: 42,
        unitDescription: nil,
        formattedResetTime: nil
    )
}
