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

    static func loadSharedData(for provider: WidgetProviderSelection) -> WidgetSharedData? {
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
    var visualStyle: WidgetVisualStyle = .liquidGlass

    @Environment(\.widgetFamily) var family

    private var providerTitle: String {
        switch entry.data.provider {
        case .glm:
            return "GLM"
        case .openai:
            return "OpenAI"
        case .mimo:
            return "MiMo"
        case .deepseek:
            return "DeepSeek"
        case nil:
            return entry.selectedProvider.displayName
        }
    }

    var body: some View {
        #if os(iOS)
        if family == .accessoryCircular {
            LockScreenHelloSquareView()
        } else if family == .accessoryRectangular {
            LockScreenHelloView()
        } else if !entry.isLoggedIn {
            NotLoggedInView(title: providerTitle, visualStyle: visualStyle)
        } else if entry.data.limits.isEmpty {
            NoDataView(title: providerTitle, lastUpdated: entry.data.lastUpdated, visualStyle: visualStyle)
        } else {
            quotaView
        }
        #else
        if !entry.isLoggedIn {
            NotLoggedInView(title: providerTitle, visualStyle: visualStyle)
        } else if entry.data.limits.isEmpty {
            NoDataView(title: providerTitle, lastUpdated: entry.data.lastUpdated, visualStyle: visualStyle)
        } else {
            quotaView
        }
        #endif
    }

    @ViewBuilder
    private var quotaView: some View {
        switch family {
        case .systemSmall:
            QuotaSmallView(
                title: providerTitle,
                limits: entry.data.limits,
                level: entry.data.level,
                visualStyle: visualStyle
            )
        case .systemMedium:
            QuotaMediumView(
                title: providerTitle,
                limits: entry.data.limits,
                level: entry.data.level,
                subscriptionName: entry.data.subscriptionName,
                subscriptionPrice: entry.data.subscriptionPrice,
                subscriptionExpireDate: entry.data.subscriptionExpireDate,
                lastUpdated: entry.data.lastUpdated,
                visualStyle: visualStyle
            )
        case .systemLarge:
            QuotaLargeView(
                limits: entry.data.limits,
                level: entry.data.level,
                subscriptionName: entry.data.subscriptionName,
                lastUpdated: entry.data.lastUpdated,
                visualStyle: visualStyle
            )
        default:
            QuotaMediumView(
                title: providerTitle,
                limits: entry.data.limits,
                level: entry.data.level,
                subscriptionName: entry.data.subscriptionName,
                subscriptionPrice: entry.data.subscriptionPrice,
                subscriptionExpireDate: entry.data.subscriptionExpireDate,
                lastUpdated: entry.data.lastUpdated,
                visualStyle: visualStyle
            )
        }
    }
}

struct LockScreenHelloView: View {
    var body: some View {
        ZStack {
            scriptText
                .foregroundStyle(.black.opacity(0.28))
                .blur(radius: 1.2)
                .offset(x: 2.2, y: 3)

            scriptText
                .foregroundStyle(.black.opacity(0.18))
                .offset(x: -1.2, y: 2.2)

            scriptText
                .foregroundStyle(.white.opacity(0.9))
                .offset(x: 0.8, y: 0.1)

            scriptText
                .foregroundStyle(.white)
                .widgetAccentable()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .scaleEffect(1.12, anchor: .leading)
        .padding(.leading, 2)
        .padding(.top, -2)
        .accessibilityLabel("Hello")
    }

    private var scriptText: some View {
        Text("Hello")
            .font(.custom("SignPainter-HouseScriptSemibold", size: 60))
            .fontWeight(.semibold)
            .lineLimit(1)
            .minimumScaleFactor(0.72)
            .allowsTightening(true)
            .kerning(3)
            .transformEffect(.init(a: 1, b: 0, c: -0.12, d: 1, tx: 0, ty: 0))
    }
}

struct LockScreenHelloSquareView: View {
    var body: some View {
        ZStack {
            scriptText
                .foregroundStyle(.black.opacity(0.26))
                .blur(radius: 0.9)
                .offset(x: 1.4, y: 2)

            scriptText
                .foregroundStyle(.black.opacity(0.16))
                .offset(x: -0.8, y: 1.3)

            scriptText
                .foregroundStyle(.white.opacity(0.9))
                .offset(x: 0.4, y: 0.1)

            scriptText
                .foregroundStyle(.white)
                .widgetAccentable()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .scaleEffect(x: 1.08, y: 1.28, anchor: .center)
        .padding(.horizontal, 1)
        .accessibilityLabel("Hello")
    }

    private var scriptText: some View {
        Text("Hello")
            .font(.custom("SignPainter-HouseScriptSemibold", size: 32))
            .fontWeight(.semibold)
            .lineLimit(1)
            .minimumScaleFactor(0.48)
            .allowsTightening(true)
            .kerning(0.6)
            .transformEffect(.init(a: 1, b: 0, c: -0.12, d: 1, tx: 0, ty: 0))
    }
}

struct DevBarLockScreenHelloWidget: Widget {
    let kind: String = "DevBarLockScreenHelloWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: LockScreenHelloTimelineProvider()) { _ in
            LockScreenHelloEntryView()
                .containerBackground(for: .widget) {
                    Color.clear
                }
        }
        .configurationDisplayName("DevBar Hello")
        .description("Show the DevBar Hello signature on the Lock Screen.")
        .supportedFamilies(supportedFamilies)
        .containerBackgroundRemovable(true)
    }

    private var supportedFamilies: [WidgetFamily] {
        #if os(iOS)
        [.accessoryRectangular, .accessoryCircular]
        #else
        []
        #endif
    }
}

private struct LockScreenHelloEntry: TimelineEntry {
    let date: Date
}

private struct LockScreenHelloTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> LockScreenHelloEntry {
        LockScreenHelloEntry(date: Date())
    }

    func getSnapshot(in context: Context, completion: @escaping (LockScreenHelloEntry) -> Void) {
        completion(LockScreenHelloEntry(date: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<LockScreenHelloEntry>) -> Void) {
        completion(Timeline(entries: [LockScreenHelloEntry(date: Date())], policy: .never))
    }
}

private struct LockScreenHelloEntryView: View {
    @Environment(\.widgetFamily) private var family

    var body: some View {
        #if os(iOS)
        switch family {
        case .accessoryCircular:
            LockScreenHelloSquareView()
        default:
            LockScreenHelloView()
        }
        #else
        EmptyView()
        #endif
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
            DevBarWidgetCompatibilityEntryView(entry: entry)
        }
        .configurationDisplayName(String(localized: "widget_name"))
        .description(String(localized: "widget_description"))
        .supportedFamilies(supportedFamilies)
        .containerBackgroundRemovable(true)
    }

    private var supportedFamilies: [WidgetFamily] {
        #if os(iOS)
        [.systemSmall, .systemMedium, .systemLarge, .accessoryCircular, .accessoryRectangular]
        #else
        [.systemSmall, .systemMedium]
        #endif
    }
}

private struct DevBarWidgetCompatibilityEntryView: View {
    let entry: QuotaEntry

    @Environment(\.widgetFamily) private var family

    var body: some View {
        if isLockScreenFamily {
            DevBarWidgetEntryView(entry: entry)
                .containerBackground(for: .widget) {
                    Color.clear
                }
        } else {
            DevBarWidgetEntryView(entry: entry)
                .styledWidgetBackground(.liquidGlass)
        }
    }

    private var isLockScreenFamily: Bool {
        #if os(iOS)
        family == .accessoryCircular || family == .accessoryRectangular
        #else
        false
        #endif
    }
}

struct DevBarLockScreenQuotaWidget: Widget {
    let kind: String = "DevBarLockScreenQuotaWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: ConfigurationAppIntent.self,
            provider: QuotaTimelineProvider()
        ) { entry in
            LockScreenQuotaEntryView(entry: entry)
                .containerBackground(for: .widget) {
                    Color.clear
                }
        }
        .configurationDisplayName("DevBar Lock Screen Quota")
        .description("Show short-period provider quota usage on the Lock Screen.")
        .supportedFamilies(supportedFamilies)
        .containerBackgroundRemovable(true)
    }

    private var supportedFamilies: [WidgetFamily] {
        #if os(iOS)
        [.accessoryRectangular, .accessoryCircular]
        #else
        []
        #endif
    }
}

struct LockScreenQuotaEntryView: View {
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
        case .deepseek:
            return "DeepSeek"
        case nil:
            return entry.selectedProvider.displayName
        }
    }

    private var limits: [WidgetQuotaLimit] {
        LockScreenQuotaLimitPicker.visibleLimits(from: entry.data.limits)
    }

    var body: some View {
        if !entry.isLoggedIn {
            LockScreenQuotaEmptyView(title: providerTitle, message: String(localized: "widget_not_logged_in"))
        } else if limits.isEmpty {
            LockScreenQuotaEmptyView(title: providerTitle, message: String(localized: "widget_waiting_data"))
        } else {
            switch family {
            case .accessoryCircular:
                LockScreenQuotaCircularView(title: providerTitle, limits: limits)
            default:
                LockScreenQuotaRectangularView(
                    title: providerTitle,
                    level: entry.data.level,
                    limits: limits
                )
            }
        }
    }
}

private enum LockScreenQuotaLimitPicker {
    static func visibleLimits(from limits: [WidgetQuotaLimit]) -> [WidgetQuotaLimit] {
        let prioritized = limits
            .filter { priority($0) < 99 }
            .sorted { lhs, rhs in
                let leftPriority = priority(lhs)
                let rightPriority = priority(rhs)

                if leftPriority != rightPriority {
                    return leftPriority < rightPriority
                }

                return lhs.displayName.localizedCompare(rhs.displayName) == .orderedAscending
            }

        let candidates = prioritized.isEmpty
            ? limits.sorted { $0.percentage > $1.percentage }
            : prioritized

        return Array(candidates.prefix(2))
    }

    private static func priority(_ limit: WidgetQuotaLimit) -> Int {
        switch limit.type {
        case "OPENAI_SESSION":
            return 0
        case "OPENAI_WEEKLY":
            return 1
        case "TOKENS_LIMIT":
            let name = limit.displayName.lowercased()
            if name.contains("5h") || name.contains("5 h") || name.contains("5小时") {
                return 0
            }
            if name.contains("weekly") || name.contains("week") || name.contains("每周") || name.contains("周") {
                return 1
            }
            return 3
        case "TIME_LIMIT":
            return 2
        default:
            return 99
        }
    }
}

private struct LockScreenQuotaRectangularView: View {
    let title: String
    let level: String?
    let limits: [WidgetQuotaLimit]

    var body: some View {
        VStack(alignment: .leading, spacing: limits.count > 1 ? 3 : 4) {
            HStack(spacing: 4) {
                Text(title)
                    .font(.caption2.weight(.bold))
                    .lineLimit(1)
                    .widgetAccentable()

                Spacer(minLength: 4)

                if let level {
                    Text(level.capitalized)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }
            }

            ForEach(limits) { limit in
                LockScreenQuotaLine(limit: limit)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
}

private struct LockScreenQuotaLine: View {
    let limit: WidgetQuotaLimit

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Text(shortName(for: limit))
                    .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)

                Spacer(minLength: 2)

                Text("\(limit.percentage)%")
                    .font(.system(size: 10.5, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(lockScreenQuotaColor(limit.percentage))
                    .lineLimit(1)
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.secondary.opacity(0.18))
                    Capsule()
                        .fill(lockScreenQuotaColor(limit.percentage))
                        .frame(width: proxy.size.width * CGFloat(limit.percentage) / 100)
                }
            }
            .frame(height: 3)
        }
    }

    private func shortName(for limit: WidgetQuotaLimit) -> String {
        let lowercased = limit.displayName.lowercased()
        if lowercased.contains("5h") || lowercased.contains("5 h") || lowercased.contains("5小时") {
            return "5h"
        }
        if lowercased.contains("weekly") || lowercased.contains("week") || lowercased.contains("每周") || lowercased.contains("周") {
            return "Weekly"
        }
        if lowercased.contains("monthly") || lowercased.contains("month") || lowercased.contains("每月") || lowercased.contains("月") {
            return "Monthly"
        }
        return limit.displayName
    }
}

private struct LockScreenQuotaCircularView: View {
    let title: String
    let limits: [WidgetQuotaLimit]

    var body: some View {
        VStack(spacing: limits.count == 1 ? 1 : 2) {
            Text(title)
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.65)

            if limits.count == 1, let limit = limits.first {
                LockScreenQuotaSemiGauge(limit: limit)
            } else {
                ForEach(limits) { limit in
                    HStack(spacing: 2) {
                        Text(lockScreenQuotaMarker(for: limit))
                            .font(.system(size: 8, weight: .black, design: .rounded))
                            .foregroundStyle(lockScreenQuotaColor(limit.percentage))
                            .frame(width: 8, alignment: .center)
                        Text("\(limit.percentage)%")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .lineLimit(1)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .widgetAccentable()
    }
}

private struct LockScreenQuotaSemiGauge: View {
    let limit: WidgetQuotaLimit

    var body: some View {
        ZStack {
            LockScreenQuotaSemiArc(progress: 1, inset: 4.5)
                .stroke(.secondary.opacity(0.28), style: StrokeStyle(lineWidth: 3.8, lineCap: .round))
            LockScreenQuotaSemiArc(progress: progress, inset: 4.5)
                .stroke(lockScreenQuotaColor(limit.percentage), style: StrokeStyle(lineWidth: 3.8, lineCap: .round))
            LockScreenQuotaSemiGaugeDot(progress: progress, inset: 4.5)
                .fill(.primary)

            VStack(spacing: -1) {
                Text(lockScreenQuotaMarker(for: limit))
                    .font(.system(size: 7.5, weight: .black, design: .rounded))
                    .foregroundStyle(lockScreenQuotaColor(limit.percentage))
                    .lineLimit(1)

                Text("\(limit.percentage)%")
                    .font(.system(size: 10.5, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }
            .offset(y: 5)
        }
        .frame(width: 50, height: 36)
    }

    private var progress: Double {
        min(max(Double(limit.percentage) / 100, 0), 1)
    }
}

private struct LockScreenQuotaSemiArc: Shape {
    let progress: Double
    let inset: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let clampedProgress = min(max(progress, 0), 1)
        let radius = min(rect.width / 2 - inset, rect.height - inset - 5)
        let center = CGPoint(x: rect.midX, y: rect.maxY - inset - 5)
        let steps = max(Int(30 * clampedProgress), 1)
        let startDegrees = 205.0
        let sweepDegrees = 230.0

        for index in 0...steps {
            let t = clampedProgress * Double(index) / Double(steps)
            let angle = (startDegrees - sweepDegrees * t) * Double.pi / 180
            let point = CGPoint(
                x: center.x + cos(angle) * radius,
                y: center.y - sin(angle) * radius
            )
            if index == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }

        return path
    }
}

private struct LockScreenQuotaSemiGaugeDot: Shape {
    let progress: Double
    let inset: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let clampedProgress = min(max(progress, 0), 1)
        let startDegrees = 205.0
        let sweepDegrees = 230.0
        let angle = (startDegrees - sweepDegrees * clampedProgress) * Double.pi / 180
        let radius = min(rect.width / 2 - inset, rect.height - inset - 5)
        let center = CGPoint(x: rect.midX, y: rect.maxY - inset - 5)
        let point = CGPoint(
            x: center.x + cos(angle) * radius,
            y: center.y - sin(angle) * radius
        )
        path.addEllipse(in: CGRect(x: point.x - 2.5, y: point.y - 2.5, width: 5, height: 5))
        return path
    }
}

private struct LockScreenQuotaEmptyView: View {
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.caption2.weight(.bold))
                .lineLimit(1)
            Text(message)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .widgetAccentable()
    }
}

private func lockScreenQuotaColor(_ percentage: Int) -> Color {
    switch percentage {
    case ..<50: return .green
    case 50..<80: return .orange
    default: return .red
    }
}

private func lockScreenQuotaMarker(for limit: WidgetQuotaLimit) -> String {
    let lowercased = limit.displayName.lowercased()
    if lowercased.contains("5h") || lowercased.contains("5 h") || lowercased.contains("小时") || lowercased.contains("hour") {
        return "H"
    }
    if lowercased.contains("weekly") || lowercased.contains("week") || lowercased.contains("每周") || lowercased.contains("周") {
        return "W"
    }
    if lowercased.contains("monthly") || lowercased.contains("month") || lowercased.contains("每月") || lowercased.contains("月") {
        return "M"
    }
    return "Q"
}

// MARK: - Placeholder Views

struct NotLoggedInView: View {
    let title: String
    var visualStyle: WidgetVisualStyle = .liquidGlass

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "person.crop.circle.badge.exclamationmark")
                .font(.title2)
                .foregroundStyle(iconColor)
            Text(title)
                .font(.headline.weight(.semibold))
                .foregroundStyle(primaryTextColor)
                .lineLimit(1)
            Text(String(localized: "widget_not_logged_in"))
                .font(.caption)
                .foregroundStyle(secondaryTextColor)
                .multilineTextAlignment(.center)
        }
    }

    private var primaryTextColor: Color {
        visualStyle == .transparent ? .primary : .white
    }

    private var secondaryTextColor: Color {
        visualStyle == .transparent ? .secondary : .white.opacity(0.58)
    }

    private var iconColor: Color {
        visualStyle == .transparent ? .secondary : .white.opacity(0.65)
    }
}

struct NoDataView: View {
    let title: String
    let lastUpdated: Date
    var visualStyle: WidgetVisualStyle = .liquidGlass

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "chart.bar.xaxis")
                .font(.title2)
                .foregroundStyle(iconColor)
            Text(title)
                .font(.headline.weight(.semibold))
                .foregroundStyle(primaryTextColor)
                .lineLimit(1)
            Text(String(localized: "widget_waiting_data"))
                .font(.caption)
                .foregroundStyle(secondaryTextColor)
            Text(lastUpdated, style: .relative)
                .font(.caption2)
                .foregroundStyle(secondaryTextColor)
        }
    }

    private var primaryTextColor: Color {
        visualStyle == .transparent ? .primary : .white
    }

    private var secondaryTextColor: Color {
        visualStyle == .transparent ? .secondary : .white.opacity(0.58)
    }

    private var iconColor: Color {
        visualStyle == .transparent ? .secondary : .white.opacity(0.65)
    }
}

struct DevBarWidgetBackground: View {
    var body: some View {
        #if os(iOS)
        if #available(iOS 26.0, *) {
            ContainerRelativeShape()
                .fill(.ultraThinMaterial)
                .overlay {
                    ContainerRelativeShape()
                        .fill(
                            LinearGradient(
                                colors: [
                                    .white.opacity(0.22),
                                    .cyan.opacity(0.08),
                                    .black.opacity(0.06)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
                .overlay {
                    ContainerRelativeShape()
                        .strokeBorder(.white.opacity(0.34), lineWidth: 0.8)
                }
                .glassEffect(
                    .regular.tint(.white.opacity(0.16)),
                    in: ContainerRelativeShape()
                )
        } else {
            ContainerRelativeShape()
                .fill(.ultraThinMaterial)
                .overlay {
                    ContainerRelativeShape()
                        .fill(.white.opacity(0.08))
                }
                .overlay {
                    ContainerRelativeShape()
                        .strokeBorder(.white.opacity(0.18), lineWidth: 0.6)
                }
        }
        #else
        Color.clear
        #endif
    }
}
