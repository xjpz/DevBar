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
        VStack(spacing: 0) {
            VStack(spacing: 7) {
                ForEach(WidgetProviderSelection.allCases, id: \.self) { provider in
                    providerQuotaCard(provider)
                }
            }

            Spacer(minLength: 7)

            quotaSyncSummary
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func providerQuotaCard(_ provider: WidgetProviderSelection) -> some View {
        let data = entry.quotaDataByProvider[provider]
        let limits = visibleQuotaLimits(in: data)

        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 7) {
                Circle()
                    .fill(providerColor(provider))
                    .frame(width: 7, height: 7)
                Text(provider.displayName)
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                Spacer()
                Text(data?.level?.capitalized ?? "--")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white.opacity(0.64))
            }

            if limits.isEmpty {
                Text("等待额度同步")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.58))
                    .lineLimit(1)
            } else {
                ForEach(limits) { limit in
                    quotaLine(limit)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private func quotaLine(_ limit: WidgetQuotaLimit) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(quotaMarker(for: limit))
                    .font(.system(size: 9, weight: .black, design: .rounded))
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
                    .font(.system(size: 10, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .frame(width: 34, alignment: .trailing)
            }

            if let detail = quotaDetail(for: limit) {
                Text(detail)
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.56))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.leading, 16)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(limit.displayName) \(limit.percentage)%")
    }

    private var quotaSyncSummary: some View {
        HStack(spacing: 6) {
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
        .font(.system(size: 8, weight: .semibold))
        .foregroundStyle(.white.opacity(0.62))
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
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
        }
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
