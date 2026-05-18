import Foundation
import Testing
@testable import DevBarCore

@Test
func liveActivitySnapshotBuilderMapsProvidersInAccountOrder() {
    let configs = [
        AccountConfig(provider: .mimo, isEnabled: true, order: 2),
        AccountConfig(provider: .openai, isEnabled: true, order: 0),
        AccountConfig(provider: .glm, isEnabled: true, order: 1),
    ]
    let data: [WidgetProvider: WidgetSharedData] = [
        .openai: widgetData(provider: .openai, level: "Plus", limits: [
            limit(type: "OPENAI_SESSION", name: "5h Usage Limit", percentage: 22),
            limit(type: "OPENAI_WEEKLY", name: "Weekly Usage Limit", percentage: 71),
        ]),
        .glm: widgetData(provider: .glm, level: "Lite", limits: [
            limit(type: "TIME_LIMIT", name: "5h Usage Limit", percentage: 8),
            limit(type: "MCP_MONTHLY", name: "MCP Monthly Quota", percentage: 41),
        ]),
        .mimo: widgetData(provider: .mimo, level: "Token", limits: [
            limit(type: "month_total_token", name: "Monthly Token", percentage: 27),
        ]),
    ]

    let snapshots = LiveActivitySnapshotBuilder.providerSnapshots(configs: configs, dataByProvider: data)

    #expect(snapshots.map(\.providerRawValue) == ["openai", "glm", "mimo"])
    #expect(snapshots[0].limits.map(\.kind) == [.fiveHour, .weekly])
    #expect(snapshots[1].limits.map(\.kind) == [.fiveHour, .monthly])
    #expect(snapshots[2].limits.map(\.kind) == [.monthly])
}

@Test
func liveActivitySnapshotBuilderSkipsMissingQuotaKinds() {
    let snapshots = LiveActivitySnapshotBuilder.visibleLimits(from: [
        limit(type: "foo", name: "Other quota", percentage: 11),
        limit(type: "OPENAI_WEEKLY", name: "Weekly Usage Limit", percentage: 71),
    ])

    #expect(snapshots.count == 1)
    #expect(snapshots.first?.kind == .weekly)
    #expect(snapshots.first?.percentage == 71)
}

private func widgetData(provider: WidgetProvider, level: String, limits: [WidgetQuotaLimit]) -> WidgetSharedData {
    WidgetSharedData(
        provider: provider,
        schemaVersion: WidgetSharedData.currentSchemaVersion,
        limits: limits,
        level: level,
        subscriptionName: nil,
        subscriptionPrice: nil,
        subscriptionExpireDate: nil,
        lastUpdated: Date()
    )
}

private func limit(type: String, name: String, percentage: Int) -> WidgetQuotaLimit {
    WidgetQuotaLimit(
        type: type,
        displayName: name,
        percentage: percentage,
        unitDescription: nil,
        formattedResetTime: nil
    )
}
