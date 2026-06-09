import AppIntents
import DevBarCore
import SwiftUI
import WidgetKit

private let desktopStyledFamilies: [WidgetFamily] = [.systemSmall, .systemMedium, .systemLarge]

private let desktopStyledWidgetDescription: String = {
    #if os(macOS)
    "添加到桌面后，可编辑并选择 Provider 额度、Agent Watcher、Mac 主题或翻页时钟。"
    #else
    "添加到桌面后，可编辑并选择 Provider 额度、Mac 主题或翻页时钟。"
    #endif
}()

enum DesktopStyledWidgetContentSelection: String, AppEnum {
    case glmQuota
    case openAIQuota
    case mimoQuota
    #if os(macOS)
    case agentWatcher
    #endif
    case macTheme
    case flipClock

    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "小组件内容")
    }

    static var caseDisplayRepresentations: [DesktopStyledWidgetContentSelection: DisplayRepresentation] {
        #if os(macOS)
        [
            .glmQuota: DisplayRepresentation(title: "GLM 额度"),
            .openAIQuota: DisplayRepresentation(title: "OpenAI 额度"),
            .mimoQuota: DisplayRepresentation(title: "MiMo 额度"),
            .agentWatcher: DisplayRepresentation(title: "Agent Watcher"),
            .macTheme: DisplayRepresentation(title: "Mac 主题"),
            .flipClock: DisplayRepresentation(title: "翻页时钟")
        ]
        #else
        [
            .glmQuota: DisplayRepresentation(title: "GLM 额度"),
            .openAIQuota: DisplayRepresentation(title: "OpenAI 额度"),
            .mimoQuota: DisplayRepresentation(title: "MiMo 额度"),
            .macTheme: DisplayRepresentation(title: "Mac 主题"),
            .flipClock: DisplayRepresentation(title: "翻页时钟")
        ]
        #endif
    }
}

struct DesktopStyledWidgetConfigurationIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource { "桌面小组件" }
    static var description: IntentDescription { "选择桌面小组件显示的内容。" }

    @Parameter(title: "小组件内容", default: .glmQuota)
    var content: DesktopStyledWidgetContentSelection
}

struct DesktopStyledWidgetEntry: TimelineEntry {
    let date: Date
    let content: Content

    enum Content {
        case quota(QuotaEntry, dataByProvider: [WidgetProviderSelection: WidgetSharedData])
        #if os(macOS)
        case agentWatcher(AgentWatcherEntry)
        #endif
        case macTheme(MacThemeWidgetEntry)
        case flipClock(FlipClockEntry)
    }
}

struct DesktopStyledWidgetTimelineProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> DesktopStyledWidgetEntry {
        previewQuotaEntry(date: Date(), provider: .glm)
    }

    func snapshot(
        for configuration: DesktopStyledWidgetConfigurationIntent,
        in context: Context
    ) async -> DesktopStyledWidgetEntry {
        let content = configuration.content.enabledContent
        if context.isPreview {
            if let provider = content.quotaProvider {
                return previewQuotaEntry(date: Date(), provider: provider)
            }
            return entry(date: Date(), content: content)
        }
        return entry(for: configuration, date: Date())
    }

    func timeline(
        for configuration: DesktopStyledWidgetConfigurationIntent,
        in context: Context
    ) async -> Timeline<DesktopStyledWidgetEntry> {
        let now = Date()
        let content = configuration.content.enabledContent
        if content == .flipClock {
            return FlipClockTimelineProvider().timeline(
                entriesFrom: now,
                makeEntry: { DesktopStyledWidgetEntry(date: $0, content: .flipClock(FlipClockEntry(date: $0))) }
            )
        }
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 5, to: now)
            ?? now.addingTimeInterval(300)
        return Timeline(entries: [entry(date: now, content: content)], policy: .after(nextUpdate))
    }

    private func entry(
        for configuration: DesktopStyledWidgetConfigurationIntent,
        date: Date
    ) -> DesktopStyledWidgetEntry {
        entry(
            date: date,
            content: configuration.content.enabledContent
        )
    }

    private func entry(
        date: Date,
        content: DesktopStyledWidgetContentSelection
    ) -> DesktopStyledWidgetEntry {
        switch content {
        case .glmQuota, .openAIQuota, .mimoQuota:
            let provider = content.quotaProvider ?? .glm
            let quotaData = QuotaTimelineProvider.loadSharedData(for: provider) ?? .placeholder
            let dataByProvider = Dictionary(
                uniqueKeysWithValues: WidgetProviderSelection.allCases.compactMap { provider in
                    QuotaTimelineProvider.loadSharedData(for: provider).map { (provider, $0) }
                }
            )
            let quota = QuotaEntry(
                data: quotaData,
                selectedProvider: provider,
                isLoggedIn: quotaData.lastUpdated != .distantPast,
                date: date
            )
            return DesktopStyledWidgetEntry(date: date, content: .quota(quota, dataByProvider: dataByProvider))
        #if os(macOS)
        case .agentWatcher:
            let agentWatcher = AgentWatcherTimelineProvider().loadEntry(content: .waiting)
                ?? .placeholder
            return DesktopStyledWidgetEntry(date: date, content: .agentWatcher(agentWatcher))
        #endif
        case .macTheme:
            let provider = WidgetProviderSelection.glm
            let configuration = MacThemeWidgetConfigurationIntent()
            configuration.defaultPage = .quota
            configuration.provider = provider
            let macTheme = MacThemeWidgetProvider().entry(for: configuration, date: date)
            return DesktopStyledWidgetEntry(date: date, content: .macTheme(macTheme))
        case .flipClock:
            return DesktopStyledWidgetEntry(date: date, content: .flipClock(FlipClockEntry(date: date)))
        }
    }

    private func previewQuotaEntry(
        date: Date,
        provider: WidgetProviderSelection
    ) -> DesktopStyledWidgetEntry {
        let dataByProvider = Dictionary(
            uniqueKeysWithValues: WidgetProviderSelection.allCases.map { provider in
                (provider, Self.previewData(for: provider, date: date))
            }
        )
        let quota = QuotaEntry(
            data: dataByProvider[provider] ?? .placeholder,
            selectedProvider: provider,
            isLoggedIn: true,
            date: date
        )
        return DesktopStyledWidgetEntry(date: date, content: .quota(quota, dataByProvider: dataByProvider))
    }

    private static func previewData(
        for provider: WidgetProviderSelection,
        date: Date
    ) -> WidgetSharedData {
        switch provider {
        case .glm:
            return previewData(
                provider: .glm,
                level: "Lite",
                limits: [
                    previewLimit(type: "TIME_LIMIT", name: "5 小时额度", percentage: 26),
                    previewLimit(type: "TOKENS_LIMIT", name: "每月额度", percentage: 65)
                ],
                date: date
            )
        case .openai:
            return previewData(
                provider: .openai,
                level: "Plus",
                limits: [
                    previewLimit(type: "OPENAI_SESSION", name: "5 小时额度", percentage: 38),
                    previewLimit(type: "OPENAI_WEEKLY", name: "每周额度", percentage: 52)
                ],
                date: date
            )
        case .mimo:
            return previewData(
                provider: .mimo,
                level: "Pro",
                limits: [
                    previewLimit(type: "TOKENS_LIMIT", name: "每月额度", percentage: 19)
                ],
                date: date
            )
        }
    }

    private static func previewData(
        provider: WidgetProvider,
        level: String,
        limits: [WidgetQuotaLimit],
        date: Date
    ) -> WidgetSharedData {
        WidgetSharedData(
            provider: provider,
            schemaVersion: WidgetSharedData.currentSchemaVersion,
            limits: limits,
            level: level,
            subscriptionName: nil,
            subscriptionPrice: nil,
            subscriptionExpireDate: nil,
            lastUpdated: date
        )
    }

    private static func previewLimit(
        type: String,
        name: String,
        percentage: Int
    ) -> WidgetQuotaLimit {
        WidgetQuotaLimit(
            type: type,
            displayName: name,
            percentage: percentage,
            unitDescription: nil,
            formattedResetTime: nil
        )
    }
}

private extension DesktopStyledWidgetContentSelection {
    var enabledContent: DesktopStyledWidgetContentSelection {
        switch self {
        #if os(macOS)
        case .agentWatcher where !DevBarCoreConstants.Features.agentWatcherEnabled:
            return .glmQuota
        #endif
        case .flipClock where !DevBarCoreConstants.Features.flipClockWidgetEnabled:
            return .glmQuota
        default:
            return self
        }
    }

    var quotaProvider: WidgetProviderSelection? {
        switch self {
        case .glmQuota: return .glm
        case .openAIQuota: return .openai
        case .mimoQuota: return .mimo
        #if os(macOS)
        case .agentWatcher: return nil
        #endif
        case .macTheme, .flipClock: return nil
        }
    }
}

struct DesktopStyledWidgetEntryView: View {
    let entry: DesktopStyledWidgetEntry
    let visualStyle: WidgetVisualStyle

    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch entry.content {
        case let .quota(quota, dataByProvider):
            if family == .systemLarge {
                DesktopStyledQuotaLargeView(
                    dataByProvider: dataByProvider,
                    visualStyle: visualStyle
                )
            } else {
                DevBarWidgetEntryView(entry: quota, visualStyle: visualStyle)
            }
        #if os(macOS)
        case let .agentWatcher(agentWatcher):
            AgentWatcherWidgetView(entry: agentWatcher, visualStyle: visualStyle)
        #endif
        case let .macTheme(macTheme):
            MacThemeWidgetEntryView(entry: macTheme, visualStyle: visualStyle)
        case let .flipClock(flipClock):
            FlipClockWidgetView(entry: flipClock)
        }
    }
}

private struct DesktopStyledQuotaLargeView: View {
    let dataByProvider: [WidgetProviderSelection: WidgetSharedData]
    let visualStyle: WidgetVisualStyle

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Label("AI 额度", systemImage: "chart.pie.fill")
                    .font(.headline.weight(.bold))
                Spacer()
                Text("DevBar")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(secondaryTextColor)
            }

            VStack(spacing: 8) {
                ForEach(WidgetProviderSelection.allCases, id: \.self) { provider in
                    providerCard(provider)
                }
            }

            Spacer(minLength: 0)

            HStack(spacing: 5) {
                Image(systemName: "arrow.triangle.2.circlepath")
                if let lastUpdated {
                    Text("最近同步 \(lastUpdated, format: .dateTime.hour().minute())")
                } else {
                    Text("等待额度同步")
                }

                Spacer(minLength: 4)

                Text("已同步 \(syncedProviderCount) 个 Provider")
            }
            .font(.caption2.weight(.semibold))
            .foregroundStyle(secondaryTextColor)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity)
            .background(cardBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(cardBorder, lineWidth: 1)
            }
        }
        .foregroundStyle(primaryTextColor)
    }

    private func providerCard(_ provider: WidgetProviderSelection) -> some View {
        let data = dataByProvider[provider]
        let limits = visibleQuotaLimits(in: data)

        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 7) {
                Circle()
                    .fill(providerColor(provider))
                    .frame(width: 7, height: 7)
                Text(provider.displayName)
                    .font(.subheadline.weight(.bold))
                Spacer()
                Text(data?.level?.capitalized ?? "--")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(secondaryTextColor)
            }

            if limits.isEmpty {
                Text("等待额度同步")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(secondaryTextColor)
            } else {
                ForEach(limits) { limit in
                    quotaLine(limit)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(cardBorder, lineWidth: 1)
        }
    }

    private func quotaLine(_ limit: WidgetQuotaLimit) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 7) {
                Text(quotaMarker(for: limit))
                    .font(.caption2.weight(.black))
                    .foregroundStyle(limitColor(limit.percentage))
                    .frame(width: 10, alignment: .leading)

                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(trackColor)
                        Capsule()
                            .fill(limitColor(limit.percentage))
                            .frame(width: proxy.size.width * CGFloat(clampedPercentage(limit.percentage)) / 100)
                    }
                }
                .frame(height: 5)

                Text("\(limit.percentage)%")
                    .font(.caption2.weight(.bold))
                    .monospacedDigit()
                    .frame(width: 34, alignment: .trailing)
            }

            if let detail = quotaDetail(for: limit) {
                Text(detail)
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(secondaryTextColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.leading, 17)
            }
        }
    }

    private var lastUpdated: Date? {
        dataByProvider.values
            .map(\.lastUpdated)
            .filter { $0 != .distantPast }
            .max()
    }

    private var syncedProviderCount: Int {
        dataByProvider.values.filter { $0.lastUpdated != .distantPast }.count
    }

    private var primaryTextColor: Color {
        visualStyle == .transparent ? .primary : .white
    }

    private var secondaryTextColor: Color {
        visualStyle == .transparent ? .secondary : .white.opacity(0.62)
    }

    private var cardBackground: Color {
        visualStyle == .transparent ? .primary.opacity(0.06) : .white.opacity(0.1)
    }

    private var cardBorder: Color {
        visualStyle == .transparent ? .primary.opacity(0.08) : .white.opacity(0.12)
    }

    private var trackColor: Color {
        visualStyle == .transparent ? .primary.opacity(0.1) : .white.opacity(0.13)
    }

    private func providerColor(_ provider: WidgetProviderSelection) -> Color {
        switch provider {
        case .glm: return .green
        case .openai: return .blue
        case .mimo: return .orange
        }
    }

    private func quotaMarker(for limit: WidgetQuotaLimit) -> String {
        let lowercased = "\(limit.type) \(limit.displayName)".lowercased()
        if limit.type == "OPENAI_SESSION"
            || lowercased.contains("5h")
            || lowercased.contains("5 h")
            || lowercased.contains("5小时")
            || lowercased.contains("hour") {
            return "H"
        }
        if lowercased.contains("monthly")
            || lowercased.contains("month")
            || lowercased.contains("每月")
            || lowercased.contains("月") {
            return "M"
        }
        if limit.type == "OPENAI_WEEKLY"
            || lowercased.contains("weekly")
            || lowercased.contains("week")
            || lowercased.contains("每周")
            || lowercased.contains("周") {
            return "W"
        }
        return "Q"
    }

    private func visibleQuotaLimits(in data: WidgetSharedData?) -> [WidgetQuotaLimit] {
        Array((data?.limits ?? [])
            .enumerated()
            .sorted { lhs, rhs in
                let lhsPriority = quotaPriority(for: lhs.element)
                let rhsPriority = quotaPriority(for: rhs.element)
                return lhsPriority == rhsPriority ? lhs.offset < rhs.offset : lhsPriority < rhsPriority
            }
            .prefix(2)
            .map(\.element))
    }

    private func quotaPriority(for limit: WidgetQuotaLimit) -> Int {
        switch quotaMarker(for: limit) {
        case "H": return 0
        case "M": return 1
        case "W": return 2
        default: return 3
        }
    }

    private func quotaDetail(for limit: WidgetQuotaLimit) -> String? {
        if let reset = limit.formattedResetTime, !reset.isEmpty {
            return "\(reset) 重置"
        }
        if let unit = limit.unitDescription, !unit.isEmpty {
            return unit
        }
        return nil
    }

    private func clampedPercentage(_ percentage: Int) -> Int {
        min(max(percentage, 0), 100)
    }

    private func limitColor(_ percentage: Int) -> Color {
        switch percentage {
        case ..<50: return .green
        case 50..<80: return .blue
        default: return .orange
        }
    }
}

// MARK: - Styled Widget Definitions

struct TransparentDesktopWidget: Widget {
    let kind = "DevBarTransparentWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: DesktopStyledWidgetConfigurationIntent.self,
            provider: DesktopStyledWidgetTimelineProvider()
        ) { entry in
            DesktopStyledWidgetEntryView(entry: entry, visualStyle: .transparent)
                .styledWidgetBackground(.transparent)
        }
        .configurationDisplayName("透明小组件")
        .description(desktopStyledWidgetDescription)
        .supportedFamilies(desktopStyledFamilies)
    }
}

struct LiquidGlassDesktopWidget: Widget {
    let kind = "DevBarLiquidGlassWidget"

    var body: some WidgetConfiguration {
        desktopStyledConfiguration(kind: kind, style: .liquidGlass)
    }
}

struct DarkDesktopWidget: Widget {
    let kind = "DevBarDarkWidget"

    var body: some WidgetConfiguration {
        desktopStyledConfiguration(kind: kind, style: .dark)
    }
}

private func desktopStyledConfiguration(kind: String, style: WidgetVisualStyle) -> some WidgetConfiguration {
    AppIntentConfiguration(
        kind: kind,
        intent: DesktopStyledWidgetConfigurationIntent.self,
        provider: DesktopStyledWidgetTimelineProvider()
    ) { entry in
        DesktopStyledWidgetEntryView(entry: entry, visualStyle: style)
            .styledWidgetBackground(style)
    }
    .configurationDisplayName(style.widgetDisplayName)
    .description(desktopStyledWidgetDescription)
    .supportedFamilies(desktopStyledFamilies)
}
