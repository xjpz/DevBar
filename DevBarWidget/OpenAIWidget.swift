// OpenAIWidget.swift
// DevBarWidget

import WidgetKit
import SwiftUI
import DevBarCore

struct OpenAITimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> QuotaEntry {
        QuotaEntry(data: .placeholder, isLoggedIn: false, date: Date())
    }

    func getSnapshot(in context: Context, completion: @escaping (QuotaEntry) -> Void) {
        let data = Self.loadSharedData() ?? .placeholder
        let isLoggedIn = data.lastUpdated != .distantPast
        completion(QuotaEntry(data: data, isLoggedIn: isLoggedIn, date: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<QuotaEntry>) -> Void) {
        let data = Self.loadSharedData() ?? .placeholder
        let isLoggedIn = data.lastUpdated != .distantPast
        let now = Date()
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: now)!

        let entries = QuotaWidgetResetPresentation.timelineDates(
            from: now,
            through: nextUpdate,
            limits: data.limits
        ).map { QuotaEntry(data: data, isLoggedIn: isLoggedIn, date: $0) }

        completion(Timeline(entries: entries, policy: .after(nextUpdate)))
    }

    private static func loadSharedData() -> WidgetSharedData? {
        guard let defaults = UserDefaults(suiteName: DevBarCoreConstants.AppGroup.groupID),
              let raw = defaults.data(forKey: DevBarCoreConstants.AppGroup.sharedDataKey(for: "openai")) else {
            return nil
        }
        guard let decoded = try? JSONDecoder().decode(WidgetSharedData.self, from: raw) else {
            return nil
        }
        guard decoded.schemaVersion <= WidgetSharedData.currentSchemaVersion else {
            return nil
        }
        return decoded
    }

}

struct OpenAIWidget: Widget {
    let kind: String = "DevBarOpenAIWidget"

    private var supportedFamilies: [WidgetFamily] {
        #if os(iOS)
        [.systemSmall, .systemMedium, .systemLarge]
        #else
        [.systemSmall, .systemMedium]
        #endif
    }

    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: kind,
            provider: OpenAITimelineProvider()
        ) { entry in
            DevBarWidgetEntryView(entry: entry)
                .containerBackground(for: .widget) {
                    DevBarWidgetBackground()
                }
        }
        .configurationDisplayName("DevBar (OpenAI)")
        .description(String(localized: "widget_description_openai"))
        .supportedFamilies(supportedFamilies)
        .containerBackgroundRemovable(true)
    }
}
