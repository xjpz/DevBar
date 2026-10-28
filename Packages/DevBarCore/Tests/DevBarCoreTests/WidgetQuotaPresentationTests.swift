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
    #expect(WidgetQuotaPresentation.shortLabel(for: sorted[1], provider: .glm) == "每周使用限额")
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

@Test
func instrumentPeriodSelectionDoesNotSubstituteMissingPeriods() {
    let session = limit(type: "OPENAI_SESSION", name: "5h Usage Limit")
    let weekly = limit(type: "OPENAI_WEEKLY", name: "Weekly Usage Limit")
    let monthly = limit(type: "TOKENS_LIMIT", name: "月度 Token")
    let limits = [monthly, weekly, session]

    #expect(WidgetQuotaPresentation.selectedLimit(in: limits, provider: .openai, period: .automatic) == session)
    #expect(WidgetQuotaPresentation.selectedLimit(in: limits, provider: .openai, period: .fiveHour) == session)
    #expect(WidgetQuotaPresentation.selectedLimit(in: limits, provider: .openai, period: .weekly) == weekly)
    #expect(WidgetQuotaPresentation.selectedLimit(in: limits, provider: .openai, period: .monthly) == monthly)
    #expect(WidgetQuotaPresentation.selectedLimit(in: [session], provider: .openai, period: .weekly) == nil)
    #expect(WidgetQuotaPresentation.selectedLimit(in: [], provider: .openai, period: .automatic) == nil)
}

@Test
func instrumentProgressKeepsEmptyFullAndSmallUsageDistinct() {
    #expect(WidgetQuotaPresentation.filledSegments(percentage: -10, count: 28) == 0)
    #expect(WidgetQuotaPresentation.filledSegments(percentage: 0, count: 28) == 0)
    #expect(WidgetQuotaPresentation.filledSegments(percentage: 1, count: 28) == 1)
    #expect(WidgetQuotaPresentation.filledSegments(percentage: 13, count: 28) == 4)
    #expect(WidgetQuotaPresentation.filledSegments(percentage: 99, count: 28) == 27)
    #expect(WidgetQuotaPresentation.filledSegments(percentage: 100, count: 28) == 28)
    #expect(WidgetQuotaPresentation.filledSegments(percentage: 120, count: 14) == 14)
    #expect(WidgetQuotaPresentation.filledSegments(percentage: 50, count: 0) == 0)
    #expect(WidgetQuotaPresentation.filledSegments(percentage: 50, count: -1) == 0)
    #expect(WidgetQuotaPresentation.filledSegments(percentage: 1, count: 1) == 1)
    let values = (-1...101).map { WidgetQuotaPresentation.filledSegments(percentage: $0, count: 14) }
    #expect(values == values.sorted())
    #expect(values.allSatisfy { (0...14).contains($0) })
}
