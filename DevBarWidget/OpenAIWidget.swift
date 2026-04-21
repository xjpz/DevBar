// OpenAIWidget.swift
// DevBarWidget

import WidgetKit
import SwiftUI

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

        var entries = [QuotaEntry(data: data, isLoggedIn: isLoggedIn, date: now)]

        let earliestReset = data.limits
            .compactMap { $0.formattedResetTime }
            .compactMap { Self.parseResetTime($0) }
            .filter { $0 > now && $0 < nextUpdate }
            .min()

        if let resetTime = earliestReset {
            entries.append(QuotaEntry(data: data, isLoggedIn: isLoggedIn, date: resetTime))
        }

        completion(Timeline(entries: entries, policy: .after(nextUpdate)))
    }

    private static func loadSharedData() -> WidgetSharedData? {
        guard let defaults = UserDefaults(suiteName: "group.cc.xjpz.DevBar"),
              let raw = defaults.data(forKey: "widget_shared_data_openai") else {
            return nil
        }
        guard let decoded = try? JSONDecoder().decode(WidgetSharedData.self, from: raw) else {
            return nil
        }
        guard decoded.schemaVersion == WidgetSharedData.currentSchemaVersion else {
            return nil
        }
        return decoded
    }

    private static func parseResetTime(_ formatted: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd HH:mm"
        formatter.locale = Locale.current
        return formatter.date(from: formatted)
    }
}

struct OpenAIWidget: Widget {
    let kind: String = "DevBarOpenAIWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: kind,
            provider: OpenAITimelineProvider()
        ) { entry in
            DevBarWidgetEntryView(entry: entry)
                .containerBackground(for: .widget) {
                    Color.clear
                }
        }
        .configurationDisplayName("DevBar (OpenAI)")
        .description(String(localized: "widget_description_openai"))
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
