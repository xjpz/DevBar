import WidgetKit
import SwiftUI
import DevBarCore

// MARK: - Timeline Provider

struct AgentWatcherTimelineProvider: AppIntentTimelineProvider {
    typealias Intent = AgentWatcherBackgroundIntent
    typealias Entry = AgentWatcherEntry

    func placeholder(in context: Context) -> AgentWatcherEntry {
        AgentWatcherEntry.placeholder
    }

    func snapshot(for intent: AgentWatcherBackgroundIntent, in context: Context) async -> AgentWatcherEntry {
        loadEntry() ?? .placeholder
    }

    func timeline(for intent: AgentWatcherBackgroundIntent, in context: Context) async -> Timeline<AgentWatcherEntry> {
        // 保存背景模式偏好到 UserDefaults（供 swizzle 读取）
        let defaults = UserDefaults(suiteName: DevBarCoreConstants.AppGroup.groupID)
        defaults?.set(intent.backgroundMode.rawValue, forKey: "agentWatcherWidgetBackgroundMode")

        let entry = loadEntry() ?? .placeholder
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 5, to: Date())!
        return Timeline(entries: [entry], policy: .after(nextUpdate))
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
    @Environment(\.widgetFamily) var family

    var body: some View {
        switch family {
        case .systemSmall:
            smallView
        case .systemMedium:
            mediumView
        default:
            smallView
        }
    }

    // MARK: - Small View

    private var smallView: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                Image(systemName: "eye")
                    .font(.title3)
                    .foregroundColor(entry.waitingCount > 0 ? .red : .green)
                Text("Agent Watcher")
                    .font(.caption)
                    .fontWeight(.medium)
                Spacer()
            }

            if entry.waitingCount > 0 {
                // Waiting state
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundColor(.red)
                        Text("\(entry.waitingCount) 个任务")
                            .font(.headline)
                    }

                    if let first = entry.waitingSessions.first {
                        FrostedCard(padding: 6) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(first.source)
                                    .font(.caption2)
                                    .foregroundColor(.white.opacity(0.8))
                                Text(first.projectName)
                                    .font(.caption)
                                    .foregroundColor(.white)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
            } else {
                // Normal state
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.circle")
                        .font(.title)
                        .foregroundColor(.green)
                    Text("一切正常")
                        .font(.headline)
                        .foregroundColor(.white)
                    Text("\(entry.activeCount) 个任务运行中")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))
                }
                .frame(maxWidth: .infinity)
            }

            Spacer()

            // Footer
            HStack {
                Spacer()
                Text(entry.date, style: .relative)
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.5))
            }
        }
        .padding()
    }

    // MARK: - Medium View

    private var mediumView: some View {
        HStack(spacing: 12) {
            // Left side - Status
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: "eye")
                        .font(.title3)
                        .foregroundColor(entry.waitingCount > 0 ? .red : .green)
                    Text("Agent Watcher")
                        .font(.caption)
                        .fontWeight(.medium)
                }

                if entry.waitingCount > 0 {
                    Text("\(entry.waitingCount) 个任务等待处理")
                        .font(.headline)
                        .foregroundColor(.white)
                } else {
                    Text("运行正常")
                        .font(.headline)
                        .foregroundColor(.white)
                }

                Text("\(entry.activeCount) 个活跃任务")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))
            }

            Spacer()

            // Right side - Sessions or Status
            if entry.waitingCount > 0 {
                VStack(alignment: .trailing, spacing: 6) {
                    ForEach(entry.waitingSessions.prefix(2)) { session in
                        FrostedCard(padding: 6) {
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(session.state == "waitingApproval" ? Color.orange : Color.blue)
                                    .frame(width: 6, height: 6)
                                VStack(alignment: .leading) {
                                    Text(session.source)
                                        .font(.caption2)
                                        .foregroundColor(.white.opacity(0.8))
                                    Text(session.projectName)
                                        .font(.caption)
                                        .foregroundColor(.white)
                                        .lineLimit(1)
                                }
                            }
                        }
                    }
                }
            } else {
                VStack(alignment: .trailing, spacing: 4) {
                    Image(systemName: "checkmark.circle")
                        .font(.title)
                        .foregroundColor(.green)
                    Text("一切正常")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))
                }
            }
        }
        .padding()
    }
}

// MARK: - Widget

struct AgentWatcherWidget: Widget {
    let kind: String = "cc.xjpz.DevBar.AgentWatcherWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: AgentWatcherBackgroundIntent.self, provider: AgentWatcherTimelineProvider()) { entry in
            AgentWatcherWidgetView(entry: entry)
                .containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName("Agent Watcher")
        .description("监控 AI 任务状态，查看是否有任务等待处理")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
