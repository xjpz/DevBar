import SwiftUI
import Combine

struct AgentWatcherView: View {
    @StateObject private var watcherService = AgentWatcherService.shared
    @StateObject private var settings = AgentWatcherSettings.shared
    @StateObject private var hookDetector = HookConfigDetectorViewModel()

    var body: some View {
        VStack(spacing: 0) {
            // 状态栏
            AgentWatcherStatusBar(
                isServerRunning: watcherService.isServerRunning,
                waitingCount: watcherService.sessionStore.waitingSessions.count,
                activeCount: watcherService.sessionStore.activeSessions.count
            )

            Divider()

            // 主内容
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Hook 配置状态
                    HookConfigSection(viewModel: hookDetector)

                    Divider()

                    // 等待中的会话
                    if !watcherService.sessionStore.waitingSessions.isEmpty {
                        WaitingSessionsSection(
                            sessions: watcherService.sessionStore.waitingSessions,
                            onResolve: { sessionId in
                                watcherService.resolveSession(sessionId)
                            },
                            onMute: { sessionId in
                                watcherService.muteSession(sessionId, duration: 30 * 60)
                            }
                        )

                        Divider()
                    }

                    // 最近事件
                    RecentEventsSection(
                        sessions: watcherService.sessionStore.recentSessions
                    )

                    Divider()

                    // 快速设置
                    QuickSettingsSection(settings: settings)
                }
                .padding()
            }
        }
        .frame(width: 320)
        .onAppear {
            hookDetector.detectConfigs()
            if watcherService.isEnabled && !watcherService.isServerRunning {
                watcherService.startServer()
            }
        }
    }
}

// MARK: - Status Bar

struct AgentWatcherStatusBar: View {
    let isServerRunning: Bool
    let waitingCount: Int
    let activeCount: Int

    var body: some View {
        HStack {
            Circle()
                .fill(isServerRunning ? Color.green : Color.red)
                .frame(width: 8, height: 8)

            Text("Agent Watcher")
                .font(.headline)

            Spacer()

            if waitingCount > 0 {
                Badge(count: waitingCount, color: .red)
            }

            if activeCount > 0 {
                Badge(count: activeCount, color: .blue)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(NSColor.controlBackgroundColor))
    }
}

struct Badge: View {
    let count: Int
    let color: Color

    var body: some View {
        Text("\(count)")
            .font(.caption)
            .fontWeight(.bold)
            .foregroundColor(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color)
            .cornerRadius(8)
    }
}

// MARK: - Hook Config Section

struct HookConfigSection: View {
    @ObservedObject var viewModel: HookConfigDetectorViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("接入状态")
                .font(.subheadline)
                .fontWeight(.medium)

            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Claude Code")
                        .font(.caption)
                    Text(viewModel.claudeStatus.displayName)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                Spacer()

                if !viewModel.claudeStatus.isConfigured {
                    Button("配置") {
                        viewModel.installClaudeConfig()
                    }
                    .buttonStyle(.link)
                    .font(.caption)
                }
            }

            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Codex CLI")
                        .font(.caption)
                    Text(viewModel.codexStatus.displayName)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                Spacer()

                if !viewModel.codexStatus.isConfigured {
                    Button("配置") {
                        viewModel.installCodexConfig()
                    }
                    .buttonStyle(.link)
                    .font(.caption)
                }
            }

            Button("重新检测") {
                viewModel.detectConfigs()
            }
            .buttonStyle(.link)
            .font(.caption)
        }
    }
}

// MARK: - Waiting Sessions Section

struct WaitingSessionsSection: View {
    let sessions: [AgentSession]
    let onResolve: (String) -> Void
    let onMute: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("等待处理")
                .font(.subheadline)
                .fontWeight(.medium)

            ForEach(sessions) { session in
                WaitingSessionCard(session: session, onResolve: {
                    onResolve(session.id)
                }, onMute: {
                    onMute(session.id)
                })
            }
        }
    }
}

struct WaitingSessionCard: View {
    let session: AgentSession
    let onResolve: () -> Void
    let onMute: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(session.source.displayName)
                    .font(.caption)
                    .fontWeight(.medium)

                Spacer()

                Text(session.state.displayName)
                    .font(.caption2)
                    .foregroundColor(.orange)
            }

            if let projectName = session.projectName {
                Text(projectName)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            if let waitingTime = session.formattedWaitingTime {
                Text("等待: \(waitingTime)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            if let message = session.lastEvent?.message {
                Text(message)
                    .font(.caption2)
                    .lineLimit(2)
                    .foregroundColor(.secondary)
            }

            HStack {
                Button("标记已处理") {
                    onResolve()
                }
                .buttonStyle(.link)
                .font(.caption)

                Spacer()

                Button("静音") {
                    onMute()
                }
                .buttonStyle(.link)
                .font(.caption)
            }
        }
        .padding(8)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }
}

// MARK: - Recent Events Section

struct RecentEventsSection: View {
    let sessions: [AgentSession]

    var recentEvents: [AgentEvent] {
        sessions
            .flatMap { $0.recentEvents }
            .sorted { $0.createdAt > $1.createdAt }
            .prefix(10)
            .map { $0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("最近事件")
                .font(.subheadline)
                .fontWeight(.medium)

            if recentEvents.isEmpty {
                Text("暂无事件")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                ForEach(recentEvents) { event in
                    EventRow(event: event)
                }
            }
        }
    }
}

struct EventRow: View {
    let event: AgentEvent

    var body: some View {
        HStack {
            Circle()
                .fill(colorForSeverity(event.severity))
                .frame(width: 6, height: 6)

            VStack(alignment: .leading, spacing: 2) {
                Text(event.message)
                    .font(.caption2)
                    .lineLimit(1)

                HStack {
                    Text(event.source.displayName)
                        .font(.caption2)
                        .foregroundColor(.secondary)

                    if let project = event.projectName {
                        Text("•")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text(project)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }

            Spacer()

            Text(timeAgo(event.createdAt))
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }

    private func colorForSeverity(_ severity: AgentSeverity) -> Color {
        switch severity {
        case .info: return .blue
        case .warning: return .yellow
        case .important: return .orange
        case .critical: return .red
        }
    }

    private func timeAgo(_ date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        if interval < 60 {
            return "刚刚"
        } else if interval < 3600 {
            return "\(Int(interval / 60))分钟前"
        } else {
            return "\(Int(interval / 3600))小时前"
        }
    }
}

// MARK: - Quick Settings Section

struct QuickSettingsSection: View {
    @ObservedObject var settings: AgentWatcherSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("快速设置")
                .font(.subheadline)
                .fontWeight(.medium)

            Toggle("启用 Agent Watcher", isOn: $settings.isEnabled)
                .font(.caption)

            Toggle("Claude Code", isOn: $settings.claudeEnabled)
                .font(.caption)
                .disabled(!settings.isEnabled)

            Toggle("Codex CLI", isOn: $settings.codexEnabled)
                .font(.caption)
                .disabled(!settings.isEnabled)

            Picker("通知模式", selection: $settings.notificationMode) {
                ForEach(NotificationMode.allCases, id: \.self) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .font(.caption)
            .disabled(!settings.isEnabled)
        }
    }
}

// MARK: - ViewModel

class HookConfigDetectorViewModel: ObservableObject {
    @Published var claudeStatus: HookConfigStatus = .notDetected
    @Published var codexStatus: HookConfigStatus = .notDetected

    private let detector = HookConfigDetector()

    func detectConfigs() {
        claudeStatus = detector.detectClaudeConfig()
        codexStatus = detector.detectCodexConfig()
    }

    func installClaudeConfig() {
        if detector.installClaudeConfig() {
            claudeStatus = .detected
        }
    }

    func installCodexConfig() {
        if detector.installCodexConfig() {
            codexStatus = .detected
        }
    }
}
