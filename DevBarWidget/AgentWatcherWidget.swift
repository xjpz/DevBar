import WidgetKit
import SwiftUI
import DevBarCore

#if os(macOS)

// MARK: - Timeline Provider

struct AgentWatcherTimelineProvider: AppIntentTimelineProvider {
    typealias Intent = AgentWatcherConfigurationIntent
    typealias Entry = AgentWatcherEntry

    func placeholder(in context: Context) -> AgentWatcherEntry {
        AgentWatcherEntry.placeholder
    }

    func snapshot(for configuration: AgentWatcherConfigurationIntent, in context: Context) async -> AgentWatcherEntry {
        loadEntry(content: configuration.content) ?? .placeholder
    }

    func timeline(for configuration: AgentWatcherConfigurationIntent, in context: Context) async -> Timeline<AgentWatcherEntry> {
        let entry = loadEntry(content: configuration.content) ?? .placeholder
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 5, to: Date())!
        return Timeline(entries: [entry], policy: .after(nextUpdate))
    }

    func loadEntry(content: AgentWatcherContentSelection) -> AgentWatcherEntry? {
        let defaults = UserDefaults(suiteName: DevBarCoreConstants.AppGroup.groupID)
        guard let data = defaults?.data(forKey: DevBarCoreConstants.AppGroup.agentWatcherWidgetKey) else {
            return nil
        }
        let widgetData = try? JSONDecoder().decode(AgentWatcherWidgetData.self, from: data)
        return widgetData.map { AgentWatcherEntry(from: $0, content: content) }
    }
}

// MARK: - Timeline Entry

struct AgentWatcherEntry: TimelineEntry {
    let date: Date
    let waitingCount: Int
    let activeCount: Int
    let waitingSessions: [AgentWatcherSessionInfo]
    let content: AgentWatcherContentSelection

    static let placeholder = AgentWatcherEntry(
        date: Date(),
        waitingCount: 0,
        activeCount: 0,
        waitingSessions: [],
        content: .waiting
    )

    init(
        date: Date = Date(),
        waitingCount: Int,
        activeCount: Int,
        waitingSessions: [AgentWatcherSessionInfo],
        content: AgentWatcherContentSelection
    ) {
        self.date = date
        self.waitingCount = waitingCount
        self.activeCount = activeCount
        self.waitingSessions = waitingSessions
        self.content = content
    }

    init(from data: AgentWatcherWidgetData, content: AgentWatcherContentSelection) {
        self.date = data.lastUpdated
        self.waitingCount = data.waitingCount
        self.activeCount = data.activeCount
        self.waitingSessions = data.waitingSessions
        self.content = content
    }
}

// MARK: - Widget View

struct AgentWatcherWidgetView: View {
    let entry: AgentWatcherEntry
    let visualStyle: WidgetVisualStyle

    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            if family == .systemMedium {
                mediumView
            } else {
                smallView
            }
        }
        .foregroundStyle(primaryTextColor)
    }

    private var smallView: some View {
        VStack(alignment: .leading, spacing: 0) {
            widgetHeader

            Spacer(minLength: 8)

            if entry.content == .overview {
                Text("\(entry.activeCount)")
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text("运行中")
                    .font(.caption)
                    .foregroundStyle(secondaryTextColor)
            } else {
                Text("\(entry.waitingCount)")
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text(entry.waitingCount > 0 ? "等待你处理" : "运行正常")
                    .font(.caption)
                    .foregroundStyle(entry.waitingCount > 0 ? .orange : .green)
            }

            Spacer(minLength: 12)

            HStack {
                metricLabel(title: "运行", value: entry.activeCount)
                Spacer()
                metricLabel(title: "卡住", value: stalledCount)
            }
        }
        .padding(14)
    }

    private var mediumView: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    widgetHeader
                    Text(entry.content == .overview ? "运行概览" : "\(entry.waitingCount) 个任务等待处理")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .lineLimit(1)
                }

                Spacer()

                Text("\(entry.activeCount) RUNNING")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(.green)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(.green.opacity(0.14), in: Capsule())
            }

            if entry.content == .overview {
                overviewMetrics
            } else if sortedWaitingSessions.isEmpty {
                healthyState
            } else {
                HStack(spacing: 8) {
                    ForEach(sortedWaitingSessions.prefix(2)) { session in
                        sessionCard(session)
                    }
                }
            }

            Spacer(minLength: 0)

            Text(entry.date, style: .relative)
                .font(.caption2)
                .foregroundStyle(secondaryTextColor)
        }
        .padding(14)
    }

    private var widgetHeader: some View {
        ZStack(alignment: .trailing) {
            Text(family == .systemSmall ? "Agent Watcher" : "AGENT WATCHER")
                .font(.system(size: family == .systemSmall ? 10.5 : 10, weight: .bold, design: .rounded))
                .tracking(family == .systemSmall ? -0.15 : 0.05)
                .foregroundStyle(secondaryTextColor)
                .lineLimit(1)
                .minimumScaleFactor(0.68)
                .allowsTightening(true)
                .layoutPriority(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.trailing, 12)

            Circle()
                .fill(entry.waitingCount > 0 ? .orange : .green)
                .frame(width: 7, height: 7)
        }
    }

    private var overviewMetrics: some View {
        HStack(spacing: 8) {
            overviewMetric(title: "运行中", value: entry.activeCount, color: .green)
            overviewMetric(title: "等待处理", value: entry.waitingCount, color: .orange)
            overviewMetric(title: "任务卡住", value: stalledCount, color: .red)
        }
    }

    private var healthyState: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.title2)
                .foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 2) {
                Text("一切正常")
                    .font(.headline)
                Text("当前没有需要处理的任务")
                    .font(.caption)
                    .foregroundStyle(secondaryTextColor)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(cardFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func sessionCard(_ session: AgentWatcherSessionInfo) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                Circle()
                    .fill(stateColor(session.state))
                    .frame(width: 6, height: 6)
                Text(stateTitle(session.state))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(stateColor(session.state))
            }

            Text(session.projectName)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .lineLimit(1)

            Text(session.source)
                .font(.caption2)
                .foregroundStyle(secondaryTextColor)
                .lineLimit(1)
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func overviewMetric(title: String, value: Int, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("\(value)")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .monospacedDigit()
            Text(title)
                .font(.caption2)
                .foregroundStyle(secondaryTextColor)
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.13), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func metricLabel(title: String, value: Int) -> some View {
        Text("\(title) \(value)")
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .foregroundStyle(secondaryTextColor)
    }

    private var sortedWaitingSessions: [AgentWatcherSessionInfo] {
        entry.waitingSessions.sorted { statePriority($0.state) < statePriority($1.state) }
    }

    private var stalledCount: Int {
        entry.waitingSessions.filter { $0.state == "stalled" }.count
    }

    private var primaryTextColor: Color {
        .white
    }

    private var secondaryTextColor: Color {
        .white.opacity(0.62)
    }

    private var cardFill: Color {
        visualStyle == .transparent ? .black.opacity(0.08) : .white.opacity(0.11)
    }

    private func statePriority(_ state: String) -> Int {
        switch state {
        case "waitingApproval": return 0
        case "stalled": return 1
        case "waitingInput": return 2
        default: return 3
        }
    }

    private func stateTitle(_ state: String) -> String {
        switch state {
        case "waitingApproval": return "等待授权"
        case "stalled": return "任务卡住"
        case "waitingInput": return "等待输入"
        default: return "等待处理"
        }
    }

    private func stateColor(_ state: String) -> Color {
        switch state {
        case "waitingApproval": return .orange
        case "stalled": return .red
        case "waitingInput": return .blue
        default: return .secondary
        }
    }
}

// MARK: - Widget

struct AgentWatcherWidget: Widget {
    let kind: String = "AgentWatcherWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: AgentWatcherConfigurationIntent.self,
            provider: AgentWatcherTimelineProvider()
        ) { entry in
            AgentWatcherWidgetView(entry: entry, visualStyle: .liquidGlass)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Agent Watcher")
        .description("监控 AI 任务状态，查看是否有任务等待处理")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

#endif
