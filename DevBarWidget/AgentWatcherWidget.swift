import WidgetKit
import SwiftUI
import DevBarCore

// MARK: - Timeline Provider

struct AgentWatcherTimelineProvider: TimelineProvider {
    typealias Entry = AgentWatcherEntry

    func placeholder(in context: Context) -> AgentWatcherEntry {
        AgentWatcherEntry.placeholder
    }

    func getSnapshot(in context: Context, completion: @escaping (AgentWatcherEntry) -> Void) {
        completion(loadEntry() ?? .placeholder)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<AgentWatcherEntry>) -> Void) {
        let entry = loadEntry() ?? .placeholder
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 5, to: Date())!
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }

    private func loadEntry() -> AgentWatcherEntry? {
        let defaults = UserDefaults(suiteName: DevBarCoreConstants.AppGroup.groupID)
        guard let data = defaults?.data(forKey: DevBarCoreConstants.AppGroup.agentWatcherWidgetKey) else {
            return nil
        }
        let widgetData = try? JSONDecoder().decode(AgentWatcherWidgetData.self, from: data)
        return widgetData.map { AgentWatcherEntry(from: $0) }
    }
}

// MARK: - Timeline Entry

struct AgentWatcherEntry: TimelineEntry {
    let date: Date
    let waitingCount: Int
    let activeCount: Int
    let waitingSessions: [AgentWatcherSessionInfo]

    static let placeholder = AgentWatcherEntry(
        date: Date(),
        waitingCount: 0,
        activeCount: 0,
        waitingSessions: []
    )

    init(date: Date = Date(), waitingCount: Int, activeCount: Int, waitingSessions: [AgentWatcherSessionInfo]) {
        self.date = date
        self.waitingCount = waitingCount
        self.activeCount = activeCount
        self.waitingSessions = waitingSessions
    }

    init(from data: AgentWatcherWidgetData) {
        self.date = data.lastUpdated
        self.waitingCount = data.waitingCount
        self.activeCount = data.activeCount
        self.waitingSessions = data.waitingSessions
    }
}

// MARK: - Widget View

struct AgentWatcherWidgetView: View {
    let entry: AgentWatcherEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "eye")
                    .font(.title3)
                    .foregroundColor(.accentColor)
                Text("Agent Watcher")
                    .font(.caption)
                    .fontWeight(.medium)
                Spacer()
            }

            if entry.waitingCount > 0 {
                HStack {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundColor(.red)
                    Text("\(entry.waitingCount) 个任务等待处理")
                        .font(.headline)
                }

                ForEach(entry.waitingSessions.prefix(2)) { session in
                    HStack {
                        Circle()
                            .fill(session.state == "waitingApproval" ? Color.orange : Color.blue)
                            .frame(width: 6, height: 6)
                        VStack(alignment: .leading) {
                            Text(session.source)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Text(session.projectName)
                                .font(.caption)
                                .lineLimit(1)
                        }
                        Spacer()
                    }
                }
            } else {
                VStack {
                    Image(systemName: "checkmark.circle")
                        .font(.title)
                        .foregroundColor(.green)
                    Text("一切正常")
                        .font(.headline)
                    Text("\(entry.activeCount) 个任务运行中")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
            }

            Spacer()

            HStack {
                Spacer()
                Text("更新于 \(entry.date, style: .relative)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
    }
}

// MARK: - Widget

struct AgentWatcherWidget: Widget {
    let kind: String = "AgentWatcherWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: AgentWatcherTimelineProvider()) { entry in
            AgentWatcherWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Agent Watcher")
        .description("监控 AI 任务状态，查看是否有任务等待处理")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
