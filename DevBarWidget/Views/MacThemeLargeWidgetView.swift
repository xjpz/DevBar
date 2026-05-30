import AppIntents
import SwiftUI
import WidgetKit
import DevBarCore

struct MacThemeLargeWidgetView: View {
    let entry: MacThemeWidgetEntry

    private var selectedPage: MacThemeWidgetPage {
        entry.selectedPage
    }

    private var providerTitle: String {
        entry.quotaData.provider.map { provider in
            switch provider {
            case .glm: return "GLM"
            case .openai: return "OpenAI"
            case .mimo: return "MiMo"
            }
        } ?? entry.configuration.provider.displayName
    }

    var body: some View {
        GeometryReader { proxy in
            let isCompact = proxy.size.width < 360

            HStack(spacing: isCompact ? 7 : 9) {
                sidebar(isCompact: isCompact)

                VStack(alignment: .leading, spacing: 8) {
                    header(isCompact: isCompact)

                    Group {
                        switch selectedPage {
                        case .quota:
                            quotaPanel
                        case .macConsole:
                            macConsolePanel
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .padding(isCompact ? 8 : 10)
            .foregroundStyle(.white)
        }
    }

    private func sidebar(isCompact: Bool) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            trafficLights
                .padding(.leading, 3)
                .padding(.bottom, 3)

            sidebarItem(page: .quota, title: "AI 额度", icon: "chart.pie.fill", isCompact: isCompact)
            sidebarItem(page: .macConsole, title: "Mac 控制", icon: "macbook.and.iphone", isCompact: isCompact)

            Spacer()

            VStack(alignment: .leading, spacing: 6) {
                statusPill(icon: "wifi", text: entry.macTheme.macStatus?.isOnline == true ? "在线" : "未连")
                statusPill(icon: "bolt.horizontal", text: "Relay")
            }
            .font(.system(size: isCompact ? 10 : 11, weight: .semibold))
        }
        .frame(width: isCompact ? 82 : 90, alignment: .topLeading)
        .frame(maxHeight: .infinity, alignment: .topLeading)
    }

    private var trafficLights: some View {
        HStack(spacing: 6) {
            Circle().fill(Color(red: 1.0, green: 0.35, blue: 0.34))
            Circle().fill(Color(red: 1.0, green: 0.73, blue: 0.23))
            Circle().fill(Color(red: 0.18, green: 0.82, blue: 0.32))
        }
        .frame(width: 48, height: 12)
    }

    private func sidebarItem(page: MacThemeWidgetPage, title: String, icon: String, isCompact: Bool) -> some View {
        Button(intent: SetMacThemeWidgetPageIntent(page: page == .quota ? .quota : .macConsole)) {
            HStack(spacing: isCompact ? 6 : 7) {
                Image(systemName: icon)
                    .font(.system(size: isCompact ? 12 : 13, weight: .bold))
                    .frame(width: isCompact ? 18 : 19, height: isCompact ? 18 : 19)

                Text(title)
                    .font(.system(size: isCompact ? 10 : 11, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
            }
            .foregroundStyle(page == selectedPage ? .white : .white.opacity(0.58))
            .padding(.horizontal, isCompact ? 7 : 8)
            .padding(.vertical, isCompact ? 8 : 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                if page == selectedPage {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(.white.opacity(0.18))
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func statusPill(icon: String, text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .frame(width: 12)
            Text(text)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .foregroundStyle(.white.opacity(0.72))
    }

    private func header(isCompact: Bool) -> some View {
        HStack(spacing: isCompact ? 8 : 10) {
            ZStack {
                Circle()
                    .fill(.white.opacity(0.18))
                Image(systemName: entry.macTheme.user.avatarSymbol)
                    .font(.system(size: isCompact ? 16 : 18, weight: .bold))
            }
            .frame(width: isCompact ? 34 : 40, height: isCompact ? 34 : 40)

            VStack(alignment: .leading, spacing: 3) {
                Text("Hi, \(entry.macTheme.user.displayName)")
                    .font(.system(size: isCompact ? 15 : 17, weight: .heavy, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)

                Text(entry.date, format: .dateTime.month().day().weekday(.wide))
                    .font(.system(size: isCompact ? 10 : 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.62))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .layoutPriority(1)

            Spacer()

            Text(entry.date, style: .time)
                .font(.system(size: isCompact ? 13 : 15, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.65)
                .padding(.horizontal, isCompact ? 8 : 10)
                .padding(.vertical, isCompact ? 7 : 8)
                .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .padding(isCompact ? 8 : 10)
        .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(.white.opacity(0.08), lineWidth: 1)
        }
    }

    private var quotaPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Circle()
                    .fill(.red)
                    .frame(width: 8, height: 8)
                Text("\(providerTitle) · AI 额度")
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                    .layoutPriority(1)
                Spacer()
                if let level = entry.quotaData.level {
                    Text(level.capitalized)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white.opacity(0.76))
                }
            }

            if !entry.isLoggedIn {
                emptyState(icon: "person.crop.circle.badge.exclamationmark", title: "未登录", subtitle: "打开 DevBar 同步 \(providerTitle) 额度")
            } else if entry.quotaData.limits.isEmpty {
                emptyState(icon: "chart.bar.doc.horizontal", title: "暂无额度数据", subtitle: "最近同步后会显示可用额度")
            } else {
                VStack(spacing: 9) {
                    ForEach(Array(entry.quotaData.limits.prefix(4))) { limit in
                        quotaRow(limit)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .panelStyle()
    }

    private func quotaRow(_ limit: WidgetQuotaLimit) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(limit.displayName)
                    .font(.system(size: 11, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                    .layoutPriority(1)

                Text("\(limit.percentage)%")
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                    .frame(minWidth: 44, alignment: .trailing)
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.white.opacity(0.13))
                    Capsule()
                        .fill(limitColor(limit.percentage))
                        .frame(width: proxy.size.width * CGFloat(max(0, min(limit.percentage, 100))) / 100)
                }
            }
            .frame(height: 7)

            if let detail = limit.unitDescription ?? limit.formattedResetTime {
                Text(detail)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.58))
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, minHeight: 54, alignment: .topLeading)
        .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var macConsolePanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Circle()
                    .fill(entry.macTheme.macStatus?.isOnline == true ? .green : .orange)
                    .frame(width: 8, height: 8)
                Text(entry.macTheme.macStatus?.deviceName ?? "未绑定 Mac")
                    .font(.system(size: 17, weight: .heavy, design: .rounded))
                    .lineLimit(1)
                Spacer()
                Text(entry.macTheme.macStatus?.isOnline == true ? "在线" : "待连接")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white.opacity(0.72))
            }

            HStack(spacing: 10) {
                macStateCard(icon: "lock.display", title: "锁屏", value: screenStateText)
                macStateCard(icon: "display", title: "显示器", value: displayStateText)
                macStateCard(icon: "moon.zzz", title: "防休眠", value: keepAwakeText)
            }

            HStack(spacing: 10) {
                Link(destination: URL(string: "devbar://mac-control?action=lock")!) {
                    actionCard(icon: "lock.fill", title: "锁定")
                }
                Link(destination: URL(string: "devbar://mac-control?action=wakeDisplay")!) {
                    actionCard(icon: "sun.max.fill", title: "点亮")
                }
                Link(destination: URL(string: "devbar://mac-control?action=sleepDisplay")!) {
                    actionCard(icon: "display.trianglebadge.exclamationmark", title: "熄屏")
                }
            }
        }
        .panelStyle()
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

    private var keepAwakeText: String {
        switch entry.macTheme.macStatus?.keepAwakeState ?? .unknown {
        case .active: return "保持"
        case .inactive: return "未保持"
        case .unknown: return "--"
        }
    }

    private func macStateCard(icon: String, title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white.opacity(0.78))
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.58))
            Text(value)
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.65)
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 78, alignment: .leading)
        .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func actionCard(icon: String, title: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .bold))
            Text(title)
                .font(.system(size: 11, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 6)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: 62)
        .background(.white.opacity(0.16), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func emptyState(icon: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(.white.opacity(0.78))
            Text(title)
                .font(.system(size: 16, weight: .heavy, design: .rounded))
            Text(subtitle)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.62))
                .lineLimit(2)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func limitColor(_ percentage: Int) -> Color {
        switch percentage {
        case ..<50: return .green
        case 50..<80: return .blue
        default: return .orange
        }
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
                .opacity(0.54)

            LinearGradient(
                colors: [.white.opacity(0.16), .clear, .black.opacity(0.18)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
}

private extension View {
    func panelStyle() -> some View {
        self
            .padding(10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(.white.opacity(0.14), lineWidth: 1)
            }
    }
}
