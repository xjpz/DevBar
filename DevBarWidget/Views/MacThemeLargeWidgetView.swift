import AppIntents
import SwiftUI
import WidgetKit
import DevBarCore
#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct MacThemeLargeWidgetView: View {
    let entry: MacThemeWidgetEntry
    let visualStyle: WidgetVisualStyle

    private var selectedPage: MacThemeWidgetPage {
        entry.selectedPage
    }

    var body: some View {
        GeometryReader { proxy in
            let isCompact = proxy.size.width < 360

            HStack(spacing: 6) {
                sidebar(isCompact: isCompact)

                VStack(alignment: .leading, spacing: 7) {
                    header(isCompact: isCompact)

                    switch selectedPage {
                    case .quota:
                        quotaContent
                    case .macConsole:
                        macConsoleContent
                    }
                }
            }
            .foregroundStyle(.white)
        }
    }

    private func sidebar(isCompact: Bool) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            trafficLights
                .padding(.leading, 2)
                .padding(.top, 1)
                .padding(.bottom, 5)

            sidebarItem(page: .quota, title: "AI 额度", icon: "chart.pie.fill", isCompact: isCompact)
            sidebarItem(page: .macConsole, title: "Mac 控制", icon: "macbook.and.iphone", isCompact: isCompact)

            Spacer()

            VStack(alignment: .leading, spacing: 5) {
                statusPill(icon: connectionIcon, text: isOnline ? "在线" : "未连")
                statusPill(icon: "bolt.horizontal", text: "Relay")
            }
            .font(.system(size: isCompact ? 9 : 10, weight: .semibold))
        }
        .frame(width: isCompact ? 64 : 70, alignment: .topLeading)
        .frame(maxHeight: .infinity, alignment: .topLeading)
    }

    private var trafficLights: some View {
        HStack(spacing: 5) {
            Circle().fill(Color(red: 1.0, green: 0.35, blue: 0.34))
            Circle().fill(Color(red: 1.0, green: 0.73, blue: 0.23))
            Circle().fill(Color(red: 0.18, green: 0.82, blue: 0.32))
        }
        .frame(height: 8)
    }

    private func sidebarItem(page: MacThemeWidgetPage, title: String, icon: String, isCompact: Bool) -> some View {
        Button(intent: SetMacThemeWidgetPageIntent(page: page == .quota ? .quota : .macConsole)) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: isCompact ? 10 : 11, weight: .bold))
                    .foregroundStyle(page == selectedPage ? selectedSidebarIconColor : .white.opacity(0.58))
                    .frame(width: 15, height: 15)
                Text(title)
                    .font(.system(size: isCompact ? 8.5 : 9, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                    .foregroundStyle(page == selectedPage ? .white : .white.opacity(0.58))
            }
            .padding(.horizontal, isCompact ? 4 : 5)
            .padding(.vertical, isCompact ? 6 : 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                if page == selectedPage {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(.white.opacity(0.11))
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var selectedSidebarIconColor: Color {
        Color(red: 0.34, green: 0.88, blue: 1.0)
    }

    private func statusPill(icon: String, text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).frame(width: 12)
            Text(text).lineLimit(1).minimumScaleFactor(0.7)
        }
        .foregroundStyle(.white.opacity(0.72))
    }

    private func header(isCompact: Bool) -> some View {
        HStack(spacing: isCompact ? 7 : 8) {
            MacThemeAvatarView(user: entry.macTheme.user)
            .frame(width: isCompact ? 30 : 34, height: isCompact ? 30 : 34)

            VStack(alignment: .leading, spacing: 3) {
                Text("Hi, \(entry.macTheme.user.displayName)")
                    .font(.system(size: isCompact ? 13 : 14, weight: .heavy, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)

                Text(entry.date, format: .dateTime.month().day().weekday(.wide))
                    .font(.system(size: isCompact ? 9 : 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.62))
                    .lineLimit(1)
            }

            Spacer()

            MacThemeClockPill(
                timerInterval: currentDayTimerInterval,
                isCompact: isCompact
            )
        }
        .padding(isCompact ? 6 : 7)
        .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(.white.opacity(0.065), lineWidth: 1)
        }
    }

    private var currentDayTimerInterval: ClosedRange<Date> {
        let start = Calendar.current.startOfDay(for: entry.date)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
        return start...end
    }

    private var quotaContent: some View {
        let providers = visibleProviders
        let density = quotaDensity(for: providers.count)

        return VStack(spacing: 0) {
            VStack(spacing: density.cardSpacing) {
                ForEach(Array(providers.enumerated()), id: \.offset) { _, provider in
                    providerQuotaCard(provider, density: density)
                }
            }
            .layoutPriority(0)

            Spacer(minLength: density.summarySpacing)

            quotaSyncSummary(density: density)
                .layoutPriority(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var visibleProviders: [WidgetProviderSelection] {
        let enabledSelections = WidgetProviderSelection.enabledSelectionsFromAppGroup
        if !enabledSelections.isEmpty {
            return Array(enabledSelections.prefix(Self.maxVisibleProviderCount))
        }

        let providersWithData = WidgetProviderSelection.allCases.filter { provider in
            guard let data = entry.quotaDataByProvider[provider] else { return false }
            return data.lastUpdated != .distantPast
        }
        let candidates = providersWithData.isEmpty ? WidgetProviderSelection.allCases : providersWithData
        return Array(candidates.prefix(Self.maxVisibleProviderCount))
    }

    private func quotaDensity(for providerCount: Int) -> QuotaCardDensity {
        switch providerCount {
        case 0...1:
            return .comfortable
        case 2:
            return .regular
        case 3:
            return .compact
        default:
            return .dense
        }
    }

    private func providerQuotaCard(_ provider: WidgetProviderSelection, density: QuotaCardDensity) -> some View {
        let data = entry.quotaDataByProvider[provider]
        let limits = visibleQuotaLimits(in: data, maxCount: density.maxVisibleLimits)
        let headerDetail = quotaHeaderDetail(
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
                    .font(.system(size: density.titleFontSize, weight: .heavy, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                Spacer()
                Text(headerDetail)
                    .font(.system(size: density.levelFontSize, weight: .bold))
                    .foregroundStyle(.white.opacity(0.64))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }

            if limits.isEmpty {
                Text("等待额度同步")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.58))
                    .lineLimit(1)
            } else {
                ForEach(limits) { limit in
                    quotaLine(limit, provider: provider, density: density)
                }
            }
        }
        .padding(.horizontal, density.horizontalPadding)
        .padding(.vertical, density.verticalPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private func quotaLine(
        _ limit: WidgetQuotaLimit,
        provider: WidgetProviderSelection,
        density: QuotaCardDensity
    ) -> some View {
        VStack(alignment: .leading, spacing: density.lineSpacing) {
            HStack(spacing: 6) {
                Text(quotaMarker(for: limit, provider: provider))
                    .font(.system(size: density.markerFontSize, weight: .black, design: .rounded))
                    .foregroundStyle(limitColor(limit.percentage))
                    .frame(width: 10, alignment: .leading)

                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.13))
                        Capsule()
                            .fill(limitColor(limit.percentage))
                            .frame(width: proxy.size.width * CGFloat(clampedPercentage(limit.percentage)) / 100)
                    }
                }
                .frame(height: 5)

                Text("\(limit.percentage)%")
                    .font(.system(size: density.percentFontSize, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .frame(width: density.percentWidth, alignment: .trailing)

                if density.showsInlineReset,
                   let reset = limit.formattedResetTime,
                   !reset.isEmpty {
                    Text("\(reset)重置")
                        .font(.system(size: density.detailFontSize, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.58))
                        .lineLimit(1)
                        .minimumScaleFactor(0.64)
                        .frame(width: density.inlineResetWidth, alignment: .trailing)
                }
            }

            if density.showsDetail, let detail = quotaDetail(for: limit) {
                Text(detail)
                    .font(.system(size: density.detailFontSize, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.56))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.leading, 16)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(limit.displayName) \(limit.percentage)%")
    }

    private func quotaSyncSummary(density: QuotaCardDensity) -> some View {
        HStack(spacing: density.summaryIconSpacing) {
            Label {
                if let updatedAt = latestQuotaUpdatedAt {
                    Text("最近同步 \(updatedAt, format: .dateTime.hour().minute())")
                } else {
                    Text("等待额度同步")
                }
            } icon: {
                Image(systemName: "arrow.triangle.2.circlepath")
            }

            Spacer(minLength: 4)

            Text("已同步 \(syncedProviderCount) 个 Provider")
        }
        .font(.system(size: density.summaryFontSize, weight: .semibold))
        .foregroundStyle(.white.opacity(0.62))
        .padding(.horizontal, density.summaryHorizontalPadding)
        .padding(.vertical, density.summaryVerticalPadding)
        .frame(maxWidth: .infinity)
        .cardStyle()
    }

    private var macConsoleContent: some View {
        VStack(spacing: 7) {
            controlRow(
                left: statusItem(icon: connectionIcon, title: "Mac 状态", value: macConnectionStatusText),
                right: actionItem(icon: "lock.fill", title: "锁定 Mac", action: "lock")
            )
            controlRow(
                left: statusItem(icon: "lock.display", title: "锁屏状态", value: screenStateText),
                right: actionItem(icon: "sun.max.fill", title: "点亮", action: "wakeDisplay")
            )
            controlRow(
                left: statusItem(icon: "display", title: "屏幕状态", value: displayStateText),
                right: actionItem(icon: "display.trianglebadge.exclamationmark", title: "熄屏", action: "sleepDisplay")
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func controlRow(left: some View, right: some View) -> some View {
        HStack(spacing: 7) {
            left.frame(maxWidth: .infinity, maxHeight: .infinity)
            right.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func statusItem(icon: String, title: String, value: String) -> some View {
        VStack(spacing: 4) {
            Label(title, systemImage: icon)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white.opacity(0.74))

            Text(value)
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.65)
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .cardStyle()
    }

    private func actionItem(icon: String, title: String, action: String) -> some View {
        Link(destination: URL(string: "devbar://mac-control?action=\(action)")!) {
            Label(title, systemImage: icon)
                .font(.system(size: 11, weight: .bold))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .cardStyle(emphasized: true)
        }
    }

    private func visibleQuotaLimits(in data: WidgetSharedData?, maxCount: Int = 2) -> [WidgetQuotaLimit] {
        Array(WidgetQuotaPresentation.sortedLimits(
            data?.limits ?? [],
            provider: data?.provider
        ).prefix(maxCount))
    }

    private func quotaMarker(for limit: WidgetQuotaLimit, provider: WidgetProviderSelection) -> String {
        WidgetQuotaPresentation.marker(for: limit, provider: WidgetProvider(rawValue: provider.rawValue))
    }

    private func clampedPercentage(_ percentage: Int) -> Int {
        min(max(percentage, 0), 100)
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

    private func quotaHeaderDetail(
        in limits: [WidgetQuotaLimit],
        provider: WidgetProviderSelection,
        fallbackLevel: String?,
        canShowResetInBody: Bool
    ) -> String {
        if !canShowResetInBody,
           let resetLimit = limits.first(where: { $0.formattedResetTime?.isEmpty == false }),
           let reset = resetLimit.formattedResetTime {
            return "\(quotaMarker(for: resetLimit, provider: provider)) \(reset)重置"
        }
        return fallbackLevel?.capitalized ?? "--"
    }

    private var latestQuotaUpdatedAt: Date? {
        entry.quotaDataByProvider.values
            .map(\.lastUpdated)
            .filter { $0 != .distantPast }
            .max()
    }

    private var syncedProviderCount: Int {
        entry.quotaDataByProvider.values.filter { $0.lastUpdated != .distantPast }.count
    }

    private func providerColor(_ provider: WidgetProviderSelection) -> Color {
        switch provider {
        case .glm: return .green
        case .openai: return .blue
        case .mimo: return .orange
        case .deepseek: return .indigo
        }
    }

    private struct QuotaCardDensity {
        let maxVisibleLimits: Int
        let cardSpacing: CGFloat
        let summarySpacing: CGFloat
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
        let summaryFontSize: CGFloat
        let summaryIconSpacing: CGFloat
        let summaryHorizontalPadding: CGFloat
        let summaryVerticalPadding: CGFloat

        static let comfortable = QuotaCardDensity(
            maxVisibleLimits: 2,
            cardSpacing: 7,
            summarySpacing: 7,
            contentSpacing: 6,
            horizontalPadding: 10,
            verticalPadding: 8,
            titleFontSize: 12,
            levelFontSize: 9,
            markerFontSize: 9,
            percentFontSize: 10,
            percentWidth: 34,
            detailFontSize: 8,
            lineSpacing: 3,
            showsDetail: true,
            showsInlineReset: false,
            inlineResetWidth: 0,
            summaryFontSize: 8,
            summaryIconSpacing: 6,
            summaryHorizontalPadding: 8,
            summaryVerticalPadding: 6
        )

        static let regular = QuotaCardDensity(
            maxVisibleLimits: 2,
            cardSpacing: 6,
            summarySpacing: 6,
            contentSpacing: 5,
            horizontalPadding: 9,
            verticalPadding: 7,
            titleFontSize: 11.5,
            levelFontSize: 8.5,
            markerFontSize: 9,
            percentFontSize: 10,
            percentWidth: 34,
            detailFontSize: 8,
            lineSpacing: 3,
            showsDetail: true,
            showsInlineReset: false,
            inlineResetWidth: 0,
            summaryFontSize: 8,
            summaryIconSpacing: 6,
            summaryHorizontalPadding: 8,
            summaryVerticalPadding: 5
        )

        static let compact = QuotaCardDensity(
            maxVisibleLimits: 2,
            cardSpacing: 5,
            summarySpacing: 5,
            contentSpacing: 4,
            horizontalPadding: 8,
            verticalPadding: 6,
            titleFontSize: 11,
            levelFontSize: 8.5,
            markerFontSize: 9,
            percentFontSize: 10,
            percentWidth: 34,
            detailFontSize: 8,
            lineSpacing: 3,
            showsDetail: true,
            showsInlineReset: false,
            inlineResetWidth: 0,
            summaryFontSize: 8,
            summaryIconSpacing: 6,
            summaryHorizontalPadding: 8,
            summaryVerticalPadding: 5
        )

        static let dense = QuotaCardDensity(
            maxVisibleLimits: 1,
            cardSpacing: 3,
            summarySpacing: 3,
            contentSpacing: 2,
            horizontalPadding: 7,
            verticalPadding: 4,
            titleFontSize: 10.5,
            levelFontSize: 8,
            markerFontSize: 8.5,
            percentFontSize: 9,
            percentWidth: 28,
            detailFontSize: 7.5,
            lineSpacing: 1,
            showsDetail: false,
            showsInlineReset: true,
            inlineResetWidth: 58,
            summaryFontSize: 7.5,
            summaryIconSpacing: 4,
            summaryHorizontalPadding: 7,
            summaryVerticalPadding: 4
        )
    }

    private var isOnline: Bool {
        entry.macTheme.macStatus?.isOnline == true
    }

    private var connectionIcon: String {
        switch entry.macTheme.macStatus?.connectionMode ?? .unknown {
        case .local: return "wifi"
        case .relay: return "bolt.horizontal"
        case .unknown: return "wifi.slash"
        }
    }

    private var connectionSummary: String {
        switch entry.macTheme.macStatus?.connectionMode ?? .unknown {
        case .local: return "本地"
        case .relay: return "远程"
        case .unknown: return "等待连接"
        }
    }

    private var macConnectionStatusText: String {
        isOnline ? "在线 · \(connectionSummary)" : "离线 · \(connectionSummary)"
    }

    private var screenStateText: String {
        switch entry.macTheme.macStatus?.screenState ?? .unknown {
        case .locked: return "已锁定"
        case .unlocked: return "未锁定"
        case .unknown: return "--"
        }
    }

    private var displayStateText: String {
        switch entry.macTheme.macStatus?.displayState ?? .unknown {
        case .awake: return "已点亮"
        case .sleeping: return "已关闭"
        case .unknown: return "--"
        }
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

private struct MacThemeClockPill: View {
    let timerInterval: ClosedRange<Date>
    let isCompact: Bool

    var body: some View {
        let width: CGFloat = isCompact ? 76 : 88
        let height: CGFloat = isCompact ? 25 : 28

        ZStack(alignment: .center) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.white.opacity(0.075))
                .frame(width: width, height: height)

            Text(timerInterval: timerInterval, countsDown: false, showsHours: true)
                .font(.system(size: isCompact ? 10 : 11, weight: .heavy, design: .monospaced))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .multilineTextAlignment(.center)
                .frame(width: width, height: height, alignment: .center)
        }
        .frame(width: width, height: height, alignment: .center)
        .transaction { transaction in
            transaction.animation = nil
        }
    }
}

private struct MacThemeAvatarView: View {
    let user: MacThemeWidgetUserSnapshot

    var body: some View {
        ZStack {
            Circle().fill(.white.opacity(0.18))

            if let avatarImage {
#if os(macOS)
                Image(nsImage: avatarImage)
                    .resizable()
                    .scaledToFill()
                    .clipShape(Circle())
#else
                Image(uiImage: avatarImage)
                    .resizable()
                    .scaledToFill()
                    .clipShape(Circle())
#endif
            } else {
                Image(systemName: user.avatarSymbol)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white.opacity(0.86))
            }
        }
    }

#if os(macOS)
    private var avatarImage: NSImage? {
        avatarData.flatMap(NSImage.init(data:))
    }
#else
    private var avatarImage: UIImage? {
        avatarData.flatMap(UIImage.init(data:))
    }
#endif

    private var avatarData: Data? {
        MacThemeWidgetAvatarStore().load(fileName: user.avatarFileName)
    }
}

struct MacThemeWidgetBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.12, green: 0.22, blue: 0.28),
                    Color(red: 0.18, green: 0.36, blue: 0.45),
                    Color(red: 0.42, green: 0.36, blue: 0.28)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Rectangle()
                .fill(.ultraThinMaterial)
                .opacity(0.42)

            LinearGradient(
                colors: [.white.opacity(0.12), .clear, .black.opacity(0.32)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
}

private extension View {
    func cardStyle(emphasized: Bool = false) -> some View {
        background(.white.opacity(emphasized ? 0.1 : 0.062), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(.white.opacity(0.085), lineWidth: 1)
            }
    }
}
