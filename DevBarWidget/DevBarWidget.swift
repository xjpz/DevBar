//
//  DevBarWidget.swift
//  DevBarWidget
//

import WidgetKit
import SwiftUI

struct QuotaTimelineProvider: TimelineProvider {
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
              let raw = defaults.data(forKey: "widget_shared_data") else {
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

struct QuotaEntry: TimelineEntry {
    let data: WidgetSharedData
    let isLoggedIn: Bool
    let date: Date
}

struct DevBarWidgetEntryView: View {
    let entry: QuotaEntry

    @Environment(\.widgetFamily) var family

    private var providerTitle: String {
        switch entry.data.provider {
        case .glm:
            return "GLM"
        case .openai:
            return "OpenAI"
        case nil:
            return "DevBar"
        }
    }

    var body: some View {
        if !entry.isLoggedIn {
            NotLoggedInView()
        } else if entry.data.limits.isEmpty {
            NoDataView(lastUpdated: entry.data.lastUpdated)
        } else {
            switch family {
            case .systemSmall:
                QuotaSmallView(
                    title: providerTitle,
                    limits: entry.data.limits,
                    level: entry.data.level
                )
            case .systemMedium:
                QuotaMediumView(
                    title: providerTitle,
                    limits: entry.data.limits,
                    level: entry.data.level,
                    subscriptionName: entry.data.subscriptionName,
                    subscriptionPrice: entry.data.subscriptionPrice,
                    subscriptionExpireDate: entry.data.subscriptionExpireDate,
                    lastUpdated: entry.data.lastUpdated
                )
            default:
                QuotaMediumView(
                    title: providerTitle,
                    limits: entry.data.limits,
                    level: entry.data.level,
                    subscriptionName: entry.data.subscriptionName,
                    subscriptionPrice: entry.data.subscriptionPrice,
                    subscriptionExpireDate: entry.data.subscriptionExpireDate,
                    lastUpdated: entry.data.lastUpdated
                )
            }
        }
    }
}

struct DevBarWidget: Widget {
    let kind: String = "DevBarWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: kind,
            provider: QuotaTimelineProvider()
        ) { entry in
            DevBarWidgetEntryView(entry: entry)
                .containerBackground(for: .widget) {
                    Color.clear
                }
        }
        .configurationDisplayName(String(localized: "widget_name"))
        .description(String(localized: "widget_description"))
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: - Placeholder Views

struct NotLoggedInView: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "person.crop.circle.badge.exclamationmark")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text(String(localized: "widget_not_logged_in"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }
}

struct NoDataView: View {
    let lastUpdated: Date

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "chart.bar.xaxis")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text(String(localized: "widget_waiting_data"))
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(lastUpdated, style: .relative)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }
}
