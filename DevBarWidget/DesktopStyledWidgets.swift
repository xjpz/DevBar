import AppIntents
import DevBarCore
import SwiftUI
import WidgetKit

private let desktopStyledFamilies: [WidgetFamily] = [.systemSmall, .systemMedium, .systemLarge]

private let desktopStyledWidgetDescription: String = {
    "添加到桌面后，可编辑并选择 Provider 额度、Mac 主题、翻页时钟或时间样式。"
}()

enum DesktopStyledWidgetContentSelection: String, AppEnum {
    case glmQuota
    case openAIQuota
    case mimoQuota
    case deepSeekQuota
    case macTheme
    case flipClock
    case compactTimeA
    case compactTimeB
    case compactTimeC

    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "小组件内容")
    }

    static var caseDisplayRepresentations: [DesktopStyledWidgetContentSelection: DisplayRepresentation] {
        [
            .glmQuota: DisplayRepresentation(title: "GLM 额度"),
            .openAIQuota: DisplayRepresentation(title: "OpenAI 额度"),
            .mimoQuota: DisplayRepresentation(title: "MiMo 额度"),
            .deepSeekQuota: DisplayRepresentation(title: "DeepSeek 额度"),
            .macTheme: DisplayRepresentation(title: "Mac 主题"),
            .flipClock: DisplayRepresentation(title: "翻页时钟"),
            .compactTimeA: DisplayRepresentation(title: "时间A"),
            .compactTimeB: DisplayRepresentation(title: "时间B"),
            .compactTimeC: DisplayRepresentation(title: "时间C")
        ]
    }
}

struct DesktopStyledWidgetConfigurationIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource { "桌面小组件" }
    static var description: IntentDescription { "选择桌面小组件显示的内容。" }

    @Parameter(title: "小组件内容", default: .glmQuota)
    var content: DesktopStyledWidgetContentSelection

    @Parameter(title: "文字颜色", default: .automatic)
    var compactTimeTextColor: CompactTimeTextColorSelection?

    @Parameter(title: "强调色", default: .automatic)
    var compactTimeAccentColor: CompactTimeAccentColorSelection?

    static var parameterSummary: some ParameterSummary {
        Switch(\.$content) {
            Case([.compactTimeA, .compactTimeB, .compactTimeC]) {
                Summary("显示 \(\.$content)") {
                    \.$compactTimeTextColor
                    \.$compactTimeAccentColor
                }
            }
            DefaultCase {
                Summary("显示 \(\.$content)")
            }
        }
    }
}

struct DesktopStyledWidgetEntry: TimelineEntry {
    let date: Date
    let content: Content

    enum Content {
        case quota(QuotaEntry, dataByProvider: [WidgetProviderSelection: WidgetSharedData])
        case macTheme(MacThemeWidgetEntry)
        case flipClock(FlipClockEntry)
        case compactTime(
            CompactTimeEntry,
            variant: CompactTimeWidgetVariant,
            appearance: CompactTimeAppearance
        )
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
            return entry(for: configuration, date: Date())
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
        if content.compactTimeVariant != nil {
            return compactTimeTimeline(for: configuration, from: now)
        }
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 5, to: now)
            ?? now.addingTimeInterval(300)
        let currentEntry = entry(for: configuration, date: now)
        let limits: [WidgetQuotaLimit]
        switch currentEntry.content {
        case let .quota(_, dataByProvider):
            limits = dataByProvider.values.flatMap(\.limits)
        case let .macTheme(macTheme):
            limits = macTheme.quotaDataByProvider.values.flatMap(\.limits)
        default:
            limits = []
        }
        let dates = QuotaWidgetResetPresentation.timelineDates(
            from: now,
            through: nextUpdate,
            limits: limits
        )
        let entries = dates.map { entry(for: configuration, date: $0) }
        return Timeline(entries: entries, policy: .after(nextUpdate))
    }

    private func compactTimeTimeline(
        for configuration: DesktopStyledWidgetConfigurationIntent,
        from now: Date
    ) -> Timeline<DesktopStyledWidgetEntry> {
        let calendar = Calendar.current
        let startOfMinute = calendar.dateInterval(of: .minute, for: now)?.start ?? now
        let refreshDate = calendar.date(byAdding: .hour, value: 1, to: startOfMinute)
            ?? startOfMinute.addingTimeInterval(60 * 60)
        let endDate = calendar.date(byAdding: .hour, value: 2, to: startOfMinute)
            ?? startOfMinute.addingTimeInterval(2 * 60 * 60)
        var dates = [now]
        var nextDate = calendar.date(byAdding: .minute, value: 1, to: startOfMinute)
            ?? now.addingTimeInterval(60)

        while nextDate <= endDate {
            dates.append(nextDate)
            nextDate = calendar.date(byAdding: .minute, value: 1, to: nextDate)
                ?? nextDate.addingTimeInterval(60)
        }

        return Timeline(
            entries: dates.map { entry(for: configuration, date: $0) },
            policy: .after(refreshDate)
        )
    }

    private func entry(
        for configuration: DesktopStyledWidgetConfigurationIntent,
        date: Date
    ) -> DesktopStyledWidgetEntry {
        entry(
            date: date,
            content: configuration.content.enabledContent,
            compactTimeAppearance: CompactTimeAppearance(
                textColorSelection: configuration.compactTimeTextColor ?? .automatic,
                accentColorSelection: configuration.compactTimeAccentColor ?? .automatic
            )
        )
    }

    private func entry(
        date: Date,
        content: DesktopStyledWidgetContentSelection,
        compactTimeAppearance: CompactTimeAppearance = .automatic
    ) -> DesktopStyledWidgetEntry {
        switch content {
        case .glmQuota, .openAIQuota, .mimoQuota, .deepSeekQuota:
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
        case .macTheme:
            let provider = WidgetProviderSelection.glm
            let configuration = MacThemeWidgetConfigurationIntent()
            configuration.defaultPage = .quota
            configuration.provider = provider
            let macTheme = MacThemeWidgetProvider().entry(for: configuration, date: date)
            return DesktopStyledWidgetEntry(date: date, content: .macTheme(macTheme))
        case .flipClock:
            return DesktopStyledWidgetEntry(date: date, content: .flipClock(FlipClockEntry(date: date)))
        case .compactTimeA, .compactTimeB, .compactTimeC:
            let variant = content.compactTimeVariant ?? .timeA
            return DesktopStyledWidgetEntry(
                date: date,
                content: .compactTime(
                    CompactTimeEntry(date: date),
                    variant: variant,
                    appearance: compactTimeAppearance
                )
            )
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
        case .deepseek:
            return previewData(
                provider: .deepseek,
                level: nil,
                limits: [
                    previewLimit(type: "DEEPSEEK_COST", name: "费用额度", percentage: 31),
                    previewLimit(type: "DEEPSEEK_TOKENS", name: "Token 用量", percentage: 44)
                ],
                date: date
            )
        }
    }

    private static func previewData(
        provider: WidgetProvider,
        level: String?,
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
        case .deepSeekQuota: return .deepseek
        case .macTheme, .flipClock, .compactTimeA, .compactTimeB, .compactTimeC: return nil
        }
    }

    var compactTimeVariant: CompactTimeWidgetVariant? {
        switch self {
        case .compactTimeA: return .timeA
        case .compactTimeB: return .timeB
        case .compactTimeC: return .timeC
        default: return nil
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
                    visualStyle: visualStyle,
                    referenceDate: entry.date
                )
            } else {
                DevBarWidgetEntryView(entry: quota, visualStyle: visualStyle)
            }
        case let .macTheme(macTheme):
            MacThemeWidgetEntryView(entry: macTheme, visualStyle: visualStyle)
        case let .flipClock(flipClock):
            FlipClockWidgetView(entry: flipClock)
        case let .compactTime(compactTime, variant, appearance):
            CompactTimeWidgetView(
                entry: compactTime,
                variant: variant,
                visualStyle: visualStyle,
                appearance: appearance
            )
        }
    }
}

private struct DesktopStyledWidgetRootView: View {
    let entry: DesktopStyledWidgetEntry
    let visualStyle: WidgetVisualStyle

    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetContentMargins) private var systemContentMargins

    var body: some View {
        DesktopStyledWidgetEntryView(entry: entry, visualStyle: visualStyle)
            .padding(contentMargins)
            .styledWidgetBackground(visualStyle)
    }

    private var contentMargins: EdgeInsets {
        guard family == .systemSmall else {
            return systemContentMargins
        }

        return EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8)
    }
}

private struct DesktopStyledQuotaLargeView: View {
    let dataByProvider: [WidgetProviderSelection: WidgetSharedData]
    let visualStyle: WidgetVisualStyle
    let referenceDate: Date

    var body: some View {
        let providers = visibleProviders
        let pageState = providerPageState(providerCount: providers.count)
        let pageProviders = pagedProviders(from: providers, pageState: pageState)
        let density = quotaDensity(for: pageProviders.count)

        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Label("AI 额度", systemImage: "chart.pie.fill")
                    .font(.headline.weight(.bold))
                Spacer()
                if pageState.pageCount > 1 {
                    quotaPageControls(pageState: pageState)
                } else {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(secondaryTextColor)
                }
            }

            VStack(spacing: density.cardSpacing) {
                ForEach(Array(pageProviders.enumerated()), id: \.offset) { _, provider in
                    providerCard(provider, density: density)
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

                if pageState.pageCount > 1 {
                    Text("\(pageProviders.count) / \(providers.count) Provider")
                } else {
                    Text("已同步 \(syncedProviderCount) 个 Provider")
                }
            }
            .font(.caption2.weight(.semibold))
            .foregroundStyle(secondaryTextColor)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .background(cardBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(cardBorder, lineWidth: 1)
            }
        }
        .foregroundStyle(primaryTextColor)
    }

    private var visibleProviders: [WidgetProviderSelection] {
        let enabledSelections = WidgetProviderSelection.enabledSelectionsFromAppGroup
        if !enabledSelections.isEmpty {
            let enabledWithData = enabledSelections.filter { provider in
                guard let data = dataByProvider[provider] else { return false }
                return data.lastUpdated != .distantPast
            }
            return enabledWithData.isEmpty ? enabledSelections : enabledWithData
        }

        let providersWithData = WidgetProviderSelection.allCases.filter { provider in
            guard let data = dataByProvider[provider] else { return false }
            return data.lastUpdated != .distantPast
        }
        let candidates = providersWithData.isEmpty ? WidgetProviderSelection.allCases : providersWithData
        return candidates
    }

    private func providerPageState(providerCount: Int) -> ProviderPageState {
        let page = WidgetProviderPageStore.currentPage(
            for: DevBarCoreConstants.AppGroup.desktopQuotaWidgetProviderPageKey,
            providerCount: providerCount
        )
        let pageCount = WidgetProviderPageStore.pageCount(for: providerCount)
        let visibleRange = WidgetProviderPageStore.pageRange(page: page, providerCount: providerCount)
        return ProviderPageState(page: page, pageCount: pageCount, visibleRange: visibleRange)
    }

    private func pagedProviders(
        from providers: [WidgetProviderSelection],
        pageState: ProviderPageState
    ) -> [WidgetProviderSelection] {
        let startIndex = min(max(pageState.visibleRange.lowerBound, 0), providers.count)
        return Array(providers.dropFirst(startIndex).prefix(WidgetProviderPageStore.pageSize))
    }

    private func quotaPageControls(pageState: ProviderPageState) -> some View {
        HStack(spacing: 5) {
            Button(intent: SetDesktopQuotaProviderPageIntent(direction: .previous)) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 8, weight: .black))
                    .frame(width: 20, height: 19)
                    .background(cardBackground.opacity(pageState.canGoPrevious ? 1 : 0.45), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .foregroundStyle(secondaryTextColor.opacity(pageState.canGoPrevious ? 1 : 0.45))
            }
            .buttonStyle(.plain)

            Text("\(pageState.page + 1)/\(pageState.pageCount)")
                .font(.system(size: 8, weight: .black, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(secondaryTextColor)
                .frame(minWidth: 26)

            Button(intent: SetDesktopQuotaProviderPageIntent(direction: .next)) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 8, weight: .black))
                    .frame(width: 20, height: 19)
                    .background(cardBackground.opacity(pageState.canGoNext ? 1 : 0.45), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .foregroundStyle(secondaryTextColor.opacity(pageState.canGoNext ? 1 : 0.45))
            }
            .buttonStyle(.plain)
        }
        .accessibilityLabel("Provider 第 \(pageState.page + 1) 页，共 \(pageState.pageCount) 页")
    }

    private func quotaDensity(for providerCount: Int) -> QuotaCardDensity {
        switch providerCount {
        case 0...1: return .comfortable
        case 2: return .regular
        case 3: return .compact
        default: return .dense
        }
    }

    private func providerCard(_ provider: WidgetProviderSelection, density: QuotaCardDensity) -> some View {
        let data = dataByProvider[provider]
        let limits = visibleQuotaLimits(in: data, maxCount: density.maxVisibleLimits)
        let showsOpenAIResetBadge = provider == .openai && (data?.availableResetCount ?? 0) > 0
        let headerDetail = showsOpenAIResetBadge
            ? (data?.level?.capitalized ?? "--")
            : quotaHeaderDetail(
                in: limits,
                provider: provider,
                fallbackLevel: data?.level,
                canShowResetInBody: density.showsDetail
            )

        return VStack(alignment: .leading, spacing: density.contentSpacing) {
            HStack(spacing: 5) {
                Circle()
                    .fill(providerColor(provider))
                    .frame(width: 6, height: 6)
                Text(provider.displayName)
                    .font(.system(size: density.titleFontSize, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                Spacer()
                if showsOpenAIResetBadge,
                   let resetCount = data?.availableResetCount {
                    ResetCreditsBadge(
                        count: resetCount,
                        size: min(max(density.titleFontSize + 6, 15), 19),
                        visualStyle: visualStyle
                    )
                }
                Text(headerDetail)
                    .font(.system(size: density.levelFontSize, weight: .bold))
                    .foregroundStyle(secondaryTextColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }

            if limits.isEmpty {
                Text("等待额度同步")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(secondaryTextColor)
            } else {
                ForEach(limits) { limit in
                    quotaLine(limit, provider: provider, density: density)
                }
            }
        }
        .padding(.horizontal, density.horizontalPadding)
        .padding(.vertical, density.verticalPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(cardBorder, lineWidth: 1)
        }
    }

    private func quotaLine(
        _ limit: WidgetQuotaLimit,
        provider: WidgetProviderSelection,
        density: QuotaCardDensity
    ) -> some View {
        VStack(alignment: .leading, spacing: density.lineSpacing) {
            HStack(spacing: 7) {
                Text(quotaMarker(for: limit, provider: provider))
                    .font(.system(size: density.markerFontSize, weight: .black, design: .rounded))
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
                    .font(.system(size: density.percentFontSize, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .frame(width: density.percentWidth, alignment: .trailing)

                if density.showsInlineReset,
                   let reset = QuotaWidgetResetPresentation.text(
                       for: limit.formattedResetTime,
                       at: referenceDate
                   ) {
                    Text("\(reset)重置")
                        .font(.system(size: density.detailFontSize, weight: .semibold))
                        .foregroundStyle(secondaryTextColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.64)
                        .frame(width: density.inlineResetWidth, alignment: .trailing)
                }
            }

            if density.showsDetail, let detail = quotaDetail(for: limit) {
                Text(detail)
                    .font(.system(size: density.detailFontSize, weight: .semibold))
                    .foregroundStyle(secondaryTextColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.leading, 17)
            }
        }
    }

    private var lastUpdated: Date? {
        visibleSyncedProviders
            .compactMap { dataByProvider[$0]?.lastUpdated }
            .filter { $0 != .distantPast }
            .max()
    }

    private var syncedProviderCount: Int {
        visibleSyncedProviders.count
    }

    private var visibleSyncedProviders: [WidgetProviderSelection] {
        visibleProviders.filter { provider in
            guard let data = dataByProvider[provider] else { return false }
            return data.lastUpdated != .distantPast
        }
    }

    private var primaryTextColor: Color {
        .white
    }

    private var secondaryTextColor: Color {
        .white.opacity(0.62)
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
        case .deepseek: return .indigo
        }
    }

    private func quotaMarker(for limit: WidgetQuotaLimit, provider: WidgetProviderSelection) -> String {
        WidgetQuotaPresentation.marker(for: limit, provider: WidgetProvider(rawValue: provider.rawValue))
    }

    private func visibleQuotaLimits(in data: WidgetSharedData?, maxCount: Int = 2) -> [WidgetQuotaLimit] {
        Array(WidgetQuotaPresentation.sortedLimits(
            data?.limits ?? [],
            provider: data?.provider
        ).prefix(maxCount))
    }

    private struct ProviderPageState {
        let page: Int
        let pageCount: Int
        let visibleRange: Range<Int>

        var canGoPrevious: Bool { page > 0 }
        var canGoNext: Bool { page < pageCount - 1 }
    }

    private struct QuotaCardDensity {
        let maxVisibleLimits: Int
        let cardSpacing: CGFloat
        let contentSpacing: CGFloat
        let horizontalPadding: CGFloat
        let verticalPadding: CGFloat
        let titleFontSize: CGFloat
        let levelFontSize: CGFloat
        let markerFontSize: CGFloat
        let percentFontSize: CGFloat
        let percentWidth: CGFloat
        let detailFontSize: CGFloat
        let lineSpacing: CGFloat
        let showsDetail: Bool
        let showsInlineReset: Bool
        let inlineResetWidth: CGFloat

        static let comfortable = QuotaCardDensity(
            maxVisibleLimits: 2,
            cardSpacing: 8,
            contentSpacing: 6,
            horizontalPadding: 10,
            verticalPadding: 8,
            titleFontSize: 13,
            levelFontSize: 10,
            markerFontSize: 10,
            percentFontSize: 10.5,
            percentWidth: 34,
            detailFontSize: 8,
            lineSpacing: 3,
            showsDetail: true,
            showsInlineReset: false,
            inlineResetWidth: 0
        )

        static let regular = QuotaCardDensity(
            maxVisibleLimits: 2,
            cardSpacing: 7,
            contentSpacing: 5,
            horizontalPadding: 10,
            verticalPadding: 7,
            titleFontSize: 12,
            levelFontSize: 9,
            markerFontSize: 9.5,
            percentFontSize: 10,
            percentWidth: 34,
            detailFontSize: 8,
            lineSpacing: 3,
            showsDetail: true,
            showsInlineReset: false,
            inlineResetWidth: 0
        )

        static let compact = QuotaCardDensity(
            maxVisibleLimits: 2,
            cardSpacing: 6,
            contentSpacing: 4,
            horizontalPadding: 9,
            verticalPadding: 6,
            titleFontSize: 11.5,
            levelFontSize: 8.5,
            markerFontSize: 9,
            percentFontSize: 10,
            percentWidth: 34,
            detailFontSize: 8,
            lineSpacing: 3,
            showsDetail: true,
            showsInlineReset: false,
            inlineResetWidth: 0
        )

        static let dense = QuotaCardDensity(
            maxVisibleLimits: 1,
            cardSpacing: 3,
            contentSpacing: 2,
            horizontalPadding: 7,
            verticalPadding: 4,
            titleFontSize: 11,
            levelFontSize: 8,
            markerFontSize: 8.5,
            percentFontSize: 9,
            percentWidth: 28,
            detailFontSize: 7.5,
            lineSpacing: 1,
            showsDetail: false,
            showsInlineReset: true,
            inlineResetWidth: 58
        )
    }

    private func quotaDetail(for limit: WidgetQuotaLimit) -> String? {
        if let reset = QuotaWidgetResetPresentation.text(
            for: limit.formattedResetTime,
            at: referenceDate
        ) {
            return "\(reset) 重置"
        }
        if let unit = limit.unitDescription, !unit.isEmpty {
            return unit
        }
        return nil
    }

    private func quotaHeaderDetail(
        in limits: [WidgetQuotaLimit],
        provider: WidgetProviderSelection,
        fallbackLevel: String?,
        canShowResetInBody: Bool
    ) -> String {
        if !canShowResetInBody,
           let resetLimit = limits.first(where: { $0.formattedResetTime?.isEmpty == false }),
           let reset = QuotaWidgetResetPresentation.text(
               for: resetLimit.formattedResetTime,
               at: referenceDate
           ) {
            return "\(quotaMarker(for: resetLimit, provider: provider)) \(reset)重置"
        }
        return fallbackLevel?.capitalized ?? "--"
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

    private static let maxVisibleProviderCount = 6
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
            DesktopStyledWidgetRootView(entry: entry, visualStyle: .transparent)
        }
        .configurationDisplayName("透明小组件")
        .description(desktopStyledWidgetDescription)
        .supportedFamilies(desktopStyledFamilies)
        .contentMarginsDisabled()
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
        DesktopStyledWidgetRootView(entry: entry, visualStyle: style)
    }
    .configurationDisplayName(style.widgetDisplayName)
    .description(desktopStyledWidgetDescription)
    .supportedFamilies(desktopStyledFamilies)
    .contentMarginsDisabled()
}
