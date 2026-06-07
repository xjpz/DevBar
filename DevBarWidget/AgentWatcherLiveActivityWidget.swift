#if os(iOS)
import ActivityKit
import DevBarCore
import SwiftUI
import WidgetKit

struct AgentWatcherLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: AgentWatcherActivityAttributes.self) { context in
            AgentWatcherLockScreenView(state: context.state)
                .activityBackgroundTint(.clear)
                .activitySystemActionForegroundColor(.primary)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    AgentWatcherExpandedLeading(title: context.attributes.title, state: context.state)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    AgentWatcherExpandedTrailing(state: context.state)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    AgentWatcherExpandedBottom(state: context.state)
                }
            } compactLeading: {
                Image(systemName: "eye")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(context.state.isWaiting ? .red : .green)
            } compactTrailing: {
                if context.state.isWaiting {
                    Text("\(context.state.waitingCount)")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundColor(.red)
                } else {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.green)
                }
            } minimal: {
                Image(systemName: "eye")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(context.state.isWaiting ? .red : .green)
            }
            .widgetURL(URL(string: "devbar://agent-watcher"))
            .keylineTint(context.state.isWaiting ? .red : .teal)
        }
    }
}

// MARK: - Lock Screen View

private struct AgentWatcherLockScreenView: View {
    let state: AgentWatcherActivityAttributes.ContentState

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            // 图标
            Image(systemName: state.isWaiting ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                .font(.system(size: 34))
                .foregroundColor(state.isWaiting ? .red : .green)

            // 信息
            VStack(alignment: .leading, spacing: 3) {
                Text(state.isWaiting ? "等待处理" : "运行正常")
                    .font(.headline.weight(.semibold))

                if state.isWaiting, let source = state.waitingSource {
                    Text(source)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if state.isWaiting, let project = state.waitingProject {
                    Text(project)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            // 状态数字
            VStack(alignment: .trailing, spacing: 2) {
                if state.isWaiting {
                    Text("\(state.waitingCount)")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundColor(.red)
                    Text("等待中")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    Text("\(state.activeCount)")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundColor(.green)
                    Text("运行中")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
    }
}

// MARK: - Dynamic Island

private struct AgentWatcherExpandedLeading: View {
    let title: String
    let state: AgentWatcherActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Image(systemName: "eye")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(state.isWaiting ? .red : .green)
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

private struct AgentWatcherExpandedTrailing: View {
    let state: AgentWatcherActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            if state.isWaiting {
                Text("\(state.waitingCount) 个任务")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.red)
                Text("等待处理")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                Text("\(state.activeCount) 个任务")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.green)
                Text("运行中")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct AgentWatcherExpandedBottom: View {
    let state: AgentWatcherActivityAttributes.ContentState

    var body: some View {
        VStack(spacing: 4) {
            if state.isWaiting {
                if let source = state.waitingSource, let project = state.waitingProject {
                    HStack {
                        Text(source)
                            .font(.caption.weight(.medium))
                        Text("•")
                        Text(project)
                            .font(.caption)
                            .lineLimit(1)
                        Spacer()
                    }
                }

                if let message = state.waitingMessage {
                    Text(message)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                if let waitingTime = state.formattedWaitingTime {
                    HStack {
                        Image(systemName: "clock")
                            .font(.caption2)
                        Text("等待 \(waitingTime)")
                            .font(.caption2)
                        Spacer()
                    }
                    .foregroundStyle(.orange)
                }
            } else {
                HStack {
                    Image(systemName: "checkmark.circle")
                        .font(.caption)
                        .foregroundColor(.green)
                    Text("所有任务运行正常")
                        .font(.caption)
                    Spacer()
                }
            }
        }
    }
}
#endif
