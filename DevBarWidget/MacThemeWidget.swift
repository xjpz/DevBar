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

    private func entry(for configuration: MacThemeWidgetConfigurationIntent, date: Date) -> MacThemeWidgetEntry {
        let quotaData = Self.loadSharedData(for: configuration.provider) ?? .placeholder
        let macTheme = Self.loadMacThemeSnapshot() ?? .placeholder
        let selectedPage = Self.loadSelectedPage() ?? configuration.defaultPage.corePage

        return MacThemeWidgetEntry(
            date: date,
            configuration: configuration,
            selectedPage: selectedPage,
            quotaData: quotaData,
            isLoggedIn: quotaData.lastUpdated != .distantPast,
            macTheme: macTheme
        )
    }

    private static func loadSharedData(for provider: WidgetProviderSelection) -> WidgetSharedData? {
        guard let defaults = UserDefaults(suiteName: DevBarCoreConstants.AppGroup.groupID),
              let raw = defaults.data(forKey: DevBarCoreConstants.AppGroup.sharedDataKey(for: provider.rawValue)),
              let decoded = try? JSONDecoder().decode(WidgetSharedData.self, from: raw),
              decoded.schemaVersion == WidgetSharedData.currentSchemaVersion else {
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
    let isLoggedIn: Bool
    let macTheme: MacThemeWidgetSnapshot
}

struct MacThemeWidgetEntryView: View {
    let entry: MacThemeWidgetEntry

    @Environment(\.widgetFamily) private var family

    var body: some View {
        if family == .systemLarge {
            MacThemeLargeWidgetView(entry: entry)
                .widgetURL(URL(string: "devbar://mac-dashboard"))
        } else {
            MacThemeCompactFallbackView()
        }
    }
}

struct MacThemeWidget: Widget {
    let kind = "DevBarMacThemeWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: MacThemeWidgetConfigurationIntent.self,
            provider: MacThemeWidgetProvider()
        ) { entry in
            MacThemeWidgetEntryView(entry: entry)
                .containerBackground(for: .widget) {
                    MacThemeWidgetBackground()
                }
        }
        .configurationDisplayName("DevBar 电脑主题")
        .description("在一个大号小组件里查看 AI 额度和电脑控制入口。")
        .supportedFamilies([.systemLarge])
    }
}

private struct MacThemeCompactFallbackView: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "macbook.and.iphone")
                .font(.title2)
            Text("DevBar")
                .font(.headline)
            Text("请使用大号小组件")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
