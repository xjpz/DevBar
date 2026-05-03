//
//  DevBarWidget.swift
//  DevBarWidget
//

import WidgetKit
import SwiftUI
import DevBarCore

struct QuotaTimelineProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> QuotaEntry {
        QuotaEntry(data: .placeholder, selectedProvider: .glm, isLoggedIn: false, date: Date())
    }

    func snapshot(for configuration: ConfigurationAppIntent, in context: Context) async -> QuotaEntry {
        let data = Self.loadSharedData(for: configuration.provider) ?? .placeholder
        let isLoggedIn = data.lastUpdated != .distantPast
        return QuotaEntry(
            data: data,
            selectedProvider: configuration.provider,
            isLoggedIn: isLoggedIn,
            date: Date()
        )
    }

    func timeline(for configuration: ConfigurationAppIntent, in context: Context) async -> Timeline<QuotaEntry> {
        let data = Self.loadSharedData(for: configuration.provider) ?? .placeholder
        let isLoggedIn = data.lastUpdated != .distantPast
        let now = Date()
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: now)!

        var entries = [
            QuotaEntry(
                data: data,
                selectedProvider: configuration.provider,
                isLoggedIn: isLoggedIn,
                date: now
            )
        ]

        let earliestReset = data.limits
            .compactMap { $0.formattedResetTime }
            .compactMap { Self.parseResetTime($0) }
            .filter { $0 > now && $0 < nextUpdate }
            .min()

        if let resetTime = earliestReset {
            entries.append(
                QuotaEntry(
                    data: data,
                    selectedProvider: configuration.provider,
                    isLoggedIn: isLoggedIn,
                    date: resetTime
                )
            )
        }

        return Timeline(entries: entries, policy: .after(nextUpdate))
    }

    private static func loadSharedData(for provider: WidgetProviderSelection) -> WidgetSharedData? {
        guard let defaults = UserDefaults(suiteName: DevBarCoreConstants.AppGroup.groupID),
              let raw = defaults.data(forKey: DevBarCoreConstants.AppGroup.sharedDataKey(for: provider.rawValue)) else {
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
    let selectedProvider: WidgetProviderSelection
    let isLoggedIn: Bool
    let date: Date

    init(
        data: WidgetSharedData,
        selectedProvider: WidgetProviderSelection = .glm,
        isLoggedIn: Bool,
        date: Date
    ) {
        self.data = data
        self.selectedProvider = selectedProvider
        self.isLoggedIn = isLoggedIn
        self.date = date
    }
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
        case .mimo:
            return "MiMo"
        case nil:
            return entry.selectedProvider.displayName
        }
    }

    var body: some View {
        if !entry.isLoggedIn {
            NotLoggedInView(title: providerTitle)
        } else if entry.data.limits.isEmpty {
            NoDataView(title: providerTitle, lastUpdated: entry.data.lastUpdated)
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
            case .systemLarge:
                QuotaLargeView(
                    limits: entry.data.limits,
                    level: entry.data.level,
                    subscriptionName: entry.data.subscriptionName,
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
        AppIntentConfiguration(
            kind: kind,
            intent: ConfigurationAppIntent.self,
            provider: QuotaTimelineProvider()
        ) { entry in
            DevBarWidgetEntryView(entry: entry)
                .containerBackground(for: .widget) {
                    Color.clear
                }
        }
        .configurationDisplayName(String(localized: "widget_name"))
        .description(String(localized: "widget_description"))
        .supportedFamilies(supportedFamilies)
    }

    private var supportedFamilies: [WidgetFamily] {
        #if os(iOS)
        [.systemSmall, .systemMedium, .systemLarge]
        #else
        [.systemSmall, .systemMedium]
        #endif
    }
}

// MARK: - Placeholder Views

struct NotLoggedInView: View {
    let title: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "person.crop.circle.badge.exclamationmark")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline.weight(.semibold))
                .lineLimit(1)
            Text(String(localized: "widget_not_logged_in"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }
}

struct NoDataView: View {
    let title: String
    let lastUpdated: Date

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "chart.bar.xaxis")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline.weight(.semibold))
                .lineLimit(1)
            Text(String(localized: "widget_waiting_data"))
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(lastUpdated, style: .relative)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }
}
