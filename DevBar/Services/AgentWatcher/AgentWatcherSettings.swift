import Foundation
import Combine

// MARK: - Notification Mode

enum NotificationMode: String, Codable, CaseIterable {
    case smart          // 智能提醒
    case macOnly        // 只提醒 Mac
    case importantSync  // 重要事件同步 iPhone
    case fullSync       // 全量同步
    case quiet          // 安静模式

    var displayName: String {
        switch self {
        case .smart: return String(localized: "智能提醒")
        case .macOnly: return String(localized: "只提醒 Mac")
        case .importantSync: return String(localized: "重要事件同步 iPhone")
        case .fullSync: return String(localized: "全量同步")
        case .quiet: return String(localized: "安静模式")
        }
    }

    var description: String {
        switch self {
        case .smart:
            return String(localized: "重要事件立即提醒，普通事件只显示 Badge，重复事件节流")
        case .macOnly:
            return String(localized: "Mac 正常提醒，iPhone 不提醒")
        case .importantSync:
            return String(localized: "等待授权、登录失效、任务失败会推送到 iPhone")
        case .fullSync:
            return String(localized: "所有 Agent 事件都提醒 iPhone")
        case .quiet:
            return String(localized: "Mac 只显示 Badge，iPhone 不提醒")
        }
    }
}

// MARK: - Agent Watcher Settings

class AgentWatcherSettings: ObservableObject {
    static let shared = AgentWatcherSettings()

    private let defaults: UserDefaults

    // MARK: - Keys

    private enum Keys {
        static let isEnabled = "agentWatcher.isEnabled"
        static let claudeEnabled = "agentWatcher.claudeEnabled"
        static let codexEnabled = "agentWatcher.codexEnabled"
        static let claudeHookNotificationsEnabled = "agentWatcher.claudeHookNotificationsEnabled"
        static let codexHookNotificationsEnabled = "agentWatcher.codexHookNotificationsEnabled"
        static let notificationMode = "agentWatcher.notificationMode"
        static let idleMinutesForPhone = "agentWatcher.idleMinutesForPhone"
        static let approvalEscalationSeconds = "agentWatcher.approvalEscalationSeconds"
        static let repeatIntervalMinutes = "agentWatcher.repeatIntervalMinutes"
        static let stalledThresholdMinutes = "agentWatcher.stalledThresholdMinutes"
        static let notifyOnTaskComplete = "agentWatcher.notifyOnTaskComplete"
        static let notifyOnTaskFailure = "agentWatcher.notifyOnTaskFailure"
        static let notifyOnLoginExpired = "agentWatcher.notifyOnLoginExpired"
        static let showProjectName = "agentWatcher.showProjectName"
        static let showCommandSummary = "agentWatcher.showCommandSummary"
        static let uploadCwd = "agentWatcher.uploadCwd"
        static let uploadRawOutput = "agentWatcher.uploadRawOutput"
    }

    // MARK: - Published Properties

    @Published var isEnabled: Bool {
        didSet { defaults.set(isEnabled, forKey: Keys.isEnabled) }
    }

    @Published var claudeEnabled: Bool {
        didSet { defaults.set(claudeEnabled, forKey: Keys.claudeEnabled) }
    }

    @Published var codexEnabled: Bool {
        didSet { defaults.set(codexEnabled, forKey: Keys.codexEnabled) }
    }

    @Published var claudeHookNotificationsEnabled: Bool {
        didSet { defaults.set(claudeHookNotificationsEnabled, forKey: Keys.claudeHookNotificationsEnabled) }
    }

    @Published var codexHookNotificationsEnabled: Bool {
        didSet { defaults.set(codexHookNotificationsEnabled, forKey: Keys.codexHookNotificationsEnabled) }
    }

    @Published var notificationMode: NotificationMode {
        didSet { defaults.set(notificationMode.rawValue, forKey: Keys.notificationMode) }
    }

    @Published var idleMinutesForPhone: Int {
        didSet { defaults.set(idleMinutesForPhone, forKey: Keys.idleMinutesForPhone) }
    }

    @Published var approvalEscalationSeconds: Int {
        didSet { defaults.set(approvalEscalationSeconds, forKey: Keys.approvalEscalationSeconds) }
    }

    @Published var repeatIntervalMinutes: Int {
        didSet { defaults.set(repeatIntervalMinutes, forKey: Keys.repeatIntervalMinutes) }
    }

    @Published var stalledThresholdMinutes: Int {
        didSet { defaults.set(stalledThresholdMinutes, forKey: Keys.stalledThresholdMinutes) }
    }

    @Published var notifyOnTaskComplete: Bool {
        didSet { defaults.set(notifyOnTaskComplete, forKey: Keys.notifyOnTaskComplete) }
    }

    @Published var notifyOnTaskFailure: Bool {
        didSet { defaults.set(notifyOnTaskFailure, forKey: Keys.notifyOnTaskFailure) }
    }

    @Published var notifyOnLoginExpired: Bool {
        didSet { defaults.set(notifyOnLoginExpired, forKey: Keys.notifyOnLoginExpired) }
    }

    @Published var showProjectName: Bool {
        didSet { defaults.set(showProjectName, forKey: Keys.showProjectName) }
    }

    @Published var showCommandSummary: Bool {
        didSet { defaults.set(showCommandSummary, forKey: Keys.showCommandSummary) }
    }

    @Published var uploadCwd: Bool {
        didSet { defaults.set(uploadCwd, forKey: Keys.uploadCwd) }
    }

    @Published var uploadRawOutput: Bool {
        didSet { defaults.set(uploadRawOutput, forKey: Keys.uploadRawOutput) }
    }

    // MARK: - Initialization

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // 加载保存的设置或使用默认值
        self.isEnabled = defaults.object(forKey: Keys.isEnabled) as? Bool ?? true
        self.claudeEnabled = defaults.object(forKey: Keys.claudeEnabled) as? Bool ?? true
        self.codexEnabled = defaults.object(forKey: Keys.codexEnabled) as? Bool ?? true
        self.claudeHookNotificationsEnabled = defaults.object(forKey: Keys.claudeHookNotificationsEnabled) as? Bool ?? true
        self.codexHookNotificationsEnabled = defaults.object(forKey: Keys.codexHookNotificationsEnabled) as? Bool ?? true

        let modeString = defaults.string(forKey: Keys.notificationMode) ?? NotificationMode.smart.rawValue
        self.notificationMode = NotificationMode(rawValue: modeString) ?? .smart

        self.idleMinutesForPhone = defaults.object(forKey: Keys.idleMinutesForPhone) as? Int ?? 3
        self.approvalEscalationSeconds = defaults.object(forKey: Keys.approvalEscalationSeconds) as? Int ?? 120
        self.repeatIntervalMinutes = defaults.object(forKey: Keys.repeatIntervalMinutes) as? Int ?? 5
        self.stalledThresholdMinutes = defaults.object(forKey: Keys.stalledThresholdMinutes) as? Int ?? 10

        self.notifyOnTaskComplete = defaults.object(forKey: Keys.notifyOnTaskComplete) as? Bool ?? false
        self.notifyOnTaskFailure = defaults.object(forKey: Keys.notifyOnTaskFailure) as? Bool ?? true
        self.notifyOnLoginExpired = defaults.object(forKey: Keys.notifyOnLoginExpired) as? Bool ?? true

        self.showProjectName = defaults.object(forKey: Keys.showProjectName) as? Bool ?? true
        self.showCommandSummary = defaults.object(forKey: Keys.showCommandSummary) as? Bool ?? false
        self.uploadCwd = defaults.object(forKey: Keys.uploadCwd) as? Bool ?? false
        self.uploadRawOutput = defaults.object(forKey: Keys.uploadRawOutput) as? Bool ?? false
    }

    // MARK: - Notification Decision

    func shouldNotify(for event: AgentEvent, userActivity: UserActivityState) -> NotificationDecision {
        guard event.canNotifyUser else {
            return NotificationDecision(
                showInStatusCenter: true,
                updateMacBadge: event.requiresUserAction,
                sendMacNotification: false,
                sendPhoneNotification: false,
                reason: "event notifications suppressed"
            )
        }

        guard hookNotificationsEnabled(for: event.source) else {
            return NotificationDecision(
                showInStatusCenter: true,
                updateMacBadge: event.requiresUserAction,
                sendMacNotification: false,
                sendPhoneNotification: false,
                reason: "hook notifications disabled"
            )
        }

        // 安静模式
        if notificationMode == .quiet {
            return NotificationDecision(
                showInStatusCenter: true,
                updateMacBadge: event.requiresUserAction,
                sendMacNotification: false,
                sendPhoneNotification: false,
                reason: "quiet mode"
            )
        }

        // 基础决策
        var decision = NotificationDecision(
            showInStatusCenter: true,
            updateMacBadge: event.requiresUserAction,
            sendMacNotification: false,
            sendPhoneNotification: false,
            reason: ""
        )

        // Mac 通知决策
        if event.severity == .important || event.severity == .critical {
            decision.sendMacNotification = true
        }

        if event.eventType == .loginRequired && notifyOnLoginExpired {
            decision.sendMacNotification = true
        }

        if event.eventType == .waitingUserInput {
            decision.sendMacNotification = true
        }

        if event.eventType == .taskFailed && notifyOnTaskFailure {
            decision.sendMacNotification = true
        }

        if event.eventType == .taskCompleted && notifyOnTaskComplete {
            decision.sendMacNotification = true
        }

        // iPhone 通知决策
        if notificationMode == .macOnly {
            decision.reason = "mac only mode"
            return decision
        }

        // 登录失效立即推送
        if event.eventType == .loginRequired && notifyOnLoginExpired {
            decision.sendPhoneNotification = true
            decision.reason = "login required"
            return decision
        }

        // Critical 事件立即推送
        if event.severity == .critical {
            decision.sendPhoneNotification = true
            decision.reason = "critical event"
            return decision
        }

        // Mac 锁屏时推送
        if userActivity.isMacLocked {
            decision.sendPhoneNotification = true
            decision.reason = "mac locked"
            return decision
        }

        // Mac 空闲超时推送
        if userActivity.idleMinutes >= idleMinutesForPhone {
            decision.sendPhoneNotification = true
            decision.reason = "mac idle"
            return decision
        }

        // 等待授权延迟推送
        if event.eventType == .approvalRequired || event.eventType == .permissionRequest {
            decision.delayPhoneNotificationSeconds = approvalEscalationSeconds
            decision.reason = "delayed escalation"
        }

        // 重要事件同步模式
        if notificationMode == .importantSync && event.severity == .important {
            decision.sendPhoneNotification = true
            decision.reason = "important event sync"
        }

        // 全量同步模式
        if notificationMode == .fullSync {
            decision.sendPhoneNotification = true
            decision.reason = "full sync mode"
        }

        return decision
    }

    func hookNotificationsEnabled(for source: AgentSource) -> Bool {
        switch source {
        case .claudeCode:
            return claudeHookNotificationsEnabled
        case .codexCLI, .codexAppServer:
            return codexHookNotificationsEnabled
        case .unknown:
            return true
        }
    }

    // MARK: - Reset

    func resetToDefaults() {
        isEnabled = true
        claudeEnabled = true
        codexEnabled = true
        claudeHookNotificationsEnabled = true
        codexHookNotificationsEnabled = true
        notificationMode = .smart
        idleMinutesForPhone = 3
        approvalEscalationSeconds = 120
        repeatIntervalMinutes = 5
        stalledThresholdMinutes = 10
        notifyOnTaskComplete = false
        notifyOnTaskFailure = true
        notifyOnLoginExpired = true
        showProjectName = true
        showCommandSummary = false
        uploadCwd = false
        uploadRawOutput = false
    }
}

// MARK: - User Activity State

struct UserActivityState {
    var isMacLocked: Bool = false
    var isMacSleeping: Bool = false
    var idleMinutes: Int = 0
    var isPhonePaired: Bool = false
    var isPhoneOnline: Bool = false
}

// MARK: - Notification Decision

struct NotificationDecision {
    var showInStatusCenter: Bool
    var updateMacBadge: Bool
    var sendMacNotification: Bool
    var sendPhoneNotification: Bool
    var delayPhoneNotificationSeconds: Int?
    var reason: String

    static func statusOnly(reason: String) -> NotificationDecision {
        NotificationDecision(
            showInStatusCenter: true,
            updateMacBadge: false,
            sendMacNotification: false,
            sendPhoneNotification: false,
            reason: reason
        )
    }

    static func badgeOnly(reason: String) -> NotificationDecision {
        NotificationDecision(
            showInStatusCenter: true,
            updateMacBadge: true,
            sendMacNotification: false,
            sendPhoneNotification: false,
            reason: reason
        )
    }
}
