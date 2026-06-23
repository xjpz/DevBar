import WidgetKit
import SwiftUI
import DevBarCore

struct MacThemeWidgetProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> MacThemeWidgetEntry {
        MacThemeWidgetEntry(
            date: Date(),
            configuration: MacThemeWidgetConfigurationIntent(),
            selectedPage: .quota,
            quotaData: .placeholder,
            quotaDataByProvider: [:],
            isLoggedIn: false,
            macTheme: .placeholder
        )
    }

    func snapshot(for configuration: MacThemeWidgetConfigurationIntent, in context: Context) async -> MacThemeWidgetEntry {
        entry(for: configuration, date: Date())
    }

    func timeline(for configuration: MacThemeWidgetConfigurationIntent, in context: Context) async -> Timeline<MacThemeWidgetEntry> {
        let now = Date()
        let entry = entry(for: configuration, date: now)
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: now) ?? now.addingTimeInterval(900)
        return Timeline(entries: [entry], policy: .after(nextUpdate))
    }

    func entry(for configuration: MacThemeWidgetConfigurationIntent, date: Date) -> MacThemeWidgetEntry {
        let quotaData = Self.loadSharedData(for: configuration.provider) ?? .placeholder
        let quotaDataByProvider = Dictionary(
            uniqueKeysWithValues: WidgetProviderSelection.allCases.compactMap { provider in
                Self.loadSharedData(for: provider).map { (provider, $0) }
            }
        )
        let macTheme = Self.loadMacThemeSnapshot() ?? .placeholder
        let selectedPage = Self.loadSelectedPage() ?? configuration.defaultPage.corePage

        return MacThemeWidgetEntry(
            date: date,
            configuration: configuration,
            selectedPage: selectedPage,
            quotaData: quotaData,
            quotaDataByProvider: quotaDataByProvider,
            isLoggedIn: quotaData.lastUpdated != .distantPast,
            macTheme: macTheme
        )
    }

    private static func loadSharedData(for provider: WidgetProviderSelection) -> WidgetSharedData? {
        guard let defaults = UserDefaults(suiteName: DevBarCoreConstants.AppGroup.groupID),
              let raw = defaults.data(forKey: DevBarCoreConstants.AppGroup.sharedDataKey(for: provider.rawValue)),
              let decoded = try? JSONDecoder().decode(WidgetSharedData.self, from: raw),
              decoded.schemaVersion <= WidgetSharedData.currentSchemaVersion else {
            return nil
        }
        return decoded
    }

    private static func loadMacThemeSnapshot() -> MacThemeWidgetSnapshot? {
        guard let defaults = UserDefaults(suiteName: DevBarCoreConstants.AppGroup.groupID),
              let raw = defaults.data(forKey: DevBarCoreConstants.AppGroup.macThemeWidgetSnapshotKey),
              let decoded = try? JSONDecoder().decode(MacThemeWidgetSnapshot.self, from: raw),
              decoded.schemaVersion == MacThemeWidgetSnapshot.currentSchemaVersion else {
            return nil
        }
        return decoded
    }

    private static func loadSelectedPage() -> MacThemeWidgetPage? {
        guard let defaults = UserDefaults(suiteName: DevBarCoreConstants.AppGroup.groupID),
              let rawValue = defaults.string(forKey: DevBarCoreConstants.AppGroup.macThemeWidgetSelectedPageKey) else {
            return nil
        }
        return MacThemeWidgetPage(rawValue: rawValue)
    }
}

struct MacThemeWidgetEntry: TimelineEntry {
    let date: Date
    let configuration: MacThemeWidgetConfigurationIntent
    let selectedPage: MacThemeWidgetPage
    let quotaData: WidgetSharedData
    let quotaDataByProvider: [WidgetProviderSelection: WidgetSharedData]
    let isLoggedIn: Bool
    let macTheme: MacThemeWidgetSnapshot
}

struct MacThemeWidgetEntryView: View {
    let entry: MacThemeWidgetEntry
    var visualStyle: WidgetVisualStyle = .liquidGlass

    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .systemLarge:
            MacThemeLargeWidgetView(entry: entry, visualStyle: visualStyle)
                .widgetURL(URL(string: "devbar://mac-dashboard"))
        case .systemMedium:
            MacThemeMediumWidgetView(entry: entry, visualStyle: visualStyle)
        default:
            MacThemeSmallWidgetView(entry: entry, visualStyle: visualStyle)
        }
    }
}

// MARK: - Widget

struct MacThemeWidget: Widget {
    let kind = "DevBarMacThemeWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: MacThemeWidgetConfigurationIntent.self,
            provider: MacThemeWidgetProvider()
        ) { entry in
            MacThemeWidgetEntryView(entry: entry, visualStyle: .liquidGlass)
                .styledWidgetBackground(.liquidGlass)
        }
        .configurationDisplayName("DevBar 电脑主题")
        .description("在一个大号小组件里查看 AI 额度和电脑控制入口。")
        .supportedFamilies([.systemLarge])
    }
}

private struct MacThemeSmallWidgetView: View {
    let entry: MacThemeWidgetEntry
    let visualStyle: WidgetVisualStyle

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            macStatusHeader
            Spacer(minLength: 0)
            Link(destination: URL(string: "devbar://mac-control?action=lock")!) {
                compactAction(icon: "lock.fill", title: "锁定 Mac")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var macStatusHeader: some View {
        VStack(alignment: .leading, spacing: 7) {
            Image(systemName: entry.macTheme.macStatus?.isOnline == true ? "macbook.and.iphone" : "macbook.slash")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(accentColor)
            Text(entry.macTheme.macStatus?.deviceName ?? "未绑定 Mac")
                .font(.headline.weight(.semibold))
                .foregroundStyle(primaryTextColor)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(entry.macTheme.macStatus?.isOnline == true ? "在线 · \(connectionSummary)" : "离线")
                .font(.caption)
                .foregroundStyle(secondaryTextColor)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func compactAction(icon: String, title: String) -> some View {
        Label(title, systemImage: icon)
            .font(.caption.weight(.bold))
            .foregroundStyle(primaryTextColor)
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity)
            .background(.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var connectionSummary: String {
        switch entry.macTheme.macStatus?.connectionMode ?? .unknown {
        case .local: return "本地"
        case .relay: return "远程"
        case .unknown: return "未连接"
        }
    }

    private var primaryTextColor: Color {
        visualStyle == .transparent ? .primary : .white
    }

    private var secondaryTextColor: Color {
        visualStyle == .transparent ? .secondary : .white.opacity(0.68)
    }

    private var accentColor: Color {
        visualStyle == .transparent ? .blue : .white.opacity(0.9)
    }
}

private struct MacThemeMediumWidgetView: View {
    let entry: MacThemeWidgetEntry
    let visualStyle: WidgetVisualStyle

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 7) {
                Label(entry.macTheme.macStatus?.deviceName ?? "未绑定 Mac", systemImage: "macbook.and.iphone")
                    .font(.headline.weight(.semibold))
                    .lineLimit(1)
                Text(entry.macTheme.macStatus?.isOnline == true ? "在线 · \(connectionSummary)" : "离线")
                    .font(.caption)
                    .foregroundStyle(secondaryTextColor)
                Text("屏幕：\(displayStateText)")
                    .font(.caption)
                    .foregroundStyle(secondaryTextColor)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: 7) {
                action(icon: "lock.fill", title: "锁定", action: "lock")
                HStack(spacing: 7) {
                    action(icon: "sun.max.fill", title: "点亮", action: "wakeDisplay")
                    action(icon: "display.trianglebadge.exclamationmark", title: "熄屏", action: "sleepDisplay")
                }
            }
            .frame(maxWidth: .infinity)
        }
        .foregroundStyle(primaryTextColor)
    }

    private func action(icon: String, title: String, action: String) -> some View {
        Link(destination: URL(string: "devbar://mac-control?action=\(action)")!) {
            Label(title, systemImage: icon)
                .font(.caption.weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, 7)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity)
                .background(.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    private var connectionSummary: String {
        switch entry.macTheme.macStatus?.connectionMode ?? .unknown {
        case .local: return "局域网直连"
        case .relay: return "Relay 中继"
        case .unknown: return "等待连接"
        }
    }

    private var displayStateText: String {
        switch entry.macTheme.macStatus?.displayState ?? .unknown {
        case .awake: return "已点亮"
        case .sleeping: return "已关闭"
        case .unknown: return "--"
        }
    }

    private var primaryTextColor: Color {
        visualStyle == .transparent ? .primary : .white
    }

    private var secondaryTextColor: Color {
        visualStyle == .transparent ? .secondary : .white.opacity(0.68)
    }
}
