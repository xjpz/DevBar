import Foundation

// MARK: - Agent Source

enum AgentSource: String, Codable, CaseIterable {
    case claudeCode
    case codexCLI
    case codexAppServer
    case unknown

    var displayName: String {
        switch self {
        case .claudeCode: return "Claude Code"
        case .codexCLI: return "Codex CLI"
        case .codexAppServer: return "Codex App Server"
        case .unknown: return "Unknown"
        }
    }
}

// MARK: - Agent Event Type

enum AgentEventType: String, Codable {
    // Claude Code hooks
    case notification              // Claude Notification hook
    case stop                      // Claude Stop hook
    case error                     // Claude Error hook

    // Codex hooks
    case permissionRequest         // Codex PermissionRequest hook
    case sessionStart              // Codex SessionStart hook
    case preToolUse                // Codex PreToolUse hook
    case postToolUse               // Codex PostToolUse hook
    case userPromptSubmit          // Codex UserPromptSubmit hook

    // 通用事件（由 hook payload 推断）
    case approvalRequired          // 需要审批
    case commandConfirmationRequired // 命令确认
    case filePermissionRequired    // 文件权限
    case networkPermissionRequired // 网络权限
    case mcpPermissionRequired     // MCP 工具权限
    case loginRequired             // 需要登录
    case waitingUserInput          // 等待用户输入
    case taskCompleted             // 任务完成
    case taskFailed                // 任务失败
    case taskStalled               // 任务卡住
    case quotaWarning              // 配额警告
    case unknown                   // 未知事件

    var requiresUserAction: Bool {
        switch self {
        case .permissionRequest, .approvalRequired, .commandConfirmationRequired,
             .filePermissionRequired, .networkPermissionRequired, .mcpPermissionRequired,
             .loginRequired, .waitingUserInput:
            return true
        default:
            return false
        }
    }

    var displayName: String {
        switch self {
        case .notification: return "通知"
        case .stop: return "停止"
        case .error: return "错误"
        case .permissionRequest: return "权限请求"
        case .sessionStart: return "会话开始"
        case .preToolUse: return "工具执行前"
        case .postToolUse: return "工具执行后"
        case .userPromptSubmit: return "用户输入"
        case .approvalRequired: return "等待授权"
        case .commandConfirmationRequired: return "命令确认"
        case .filePermissionRequired: return "文件权限"
        case .networkPermissionRequired: return "网络权限"
        case .mcpPermissionRequired: return "MCP 权限"
        case .loginRequired: return "需要登录"
        case .waitingUserInput: return "等待输入"
        case .taskCompleted: return "任务完成"
        case .taskFailed: return "任务失败"
        case .taskStalled: return "任务卡住"
        case .quotaWarning: return "配额警告"
        case .unknown: return "未知"
        }
    }
}

// MARK: - Agent Severity

enum AgentSeverity: String, Codable {
    case info       // 普通信息
    case warning    // 警告
    case important  // 重要
    case critical   // 紧急

    var priority: Int {
        switch self {
        case .info: return 0
        case .warning: return 1
        case .important: return 2
        case .critical: return 3
        }
    }
}

// MARK: - Agent Event

struct AgentEvent: Codable, Identifiable {
    let id: String
    let source: AgentSource
    let eventType: AgentEventType
    let severity: AgentSeverity

    let projectName: String?
    let cwd: String?
    let sessionId: String?
    let taskTitle: String?

    let message: String
    let rawSnippet: String?

    let createdAt: Date
    let detectedAt: Date

    let requiresUserAction: Bool
    let canResolveOnMac: Bool
    let canNotifyPhone: Bool
    let canNotifyUser: Bool

    init(
        id: String = UUID().uuidString,
        source: AgentSource,
        eventType: AgentEventType,
        severity: AgentSeverity,
        projectName: String? = nil,
        cwd: String? = nil,
        sessionId: String? = nil,
        taskTitle: String? = nil,
        message: String,
        rawSnippet: String? = nil,
        createdAt: Date = Date(),
        detectedAt: Date = Date(),
        requiresUserAction: Bool = false,
        canResolveOnMac: Bool = true,
        canNotifyPhone: Bool = false,
        canNotifyUser: Bool = true
    ) {
        self.id = id
        self.source = source
        self.eventType = eventType
        self.severity = severity
        self.projectName = projectName
        self.cwd = cwd
        self.sessionId = sessionId
        self.taskTitle = taskTitle
        self.message = message
        self.rawSnippet = rawSnippet
        self.createdAt = createdAt
        self.detectedAt = detectedAt
        self.requiresUserAction = requiresUserAction
        self.canResolveOnMac = canResolveOnMac
        self.canNotifyPhone = canNotifyPhone
        self.canNotifyUser = canNotifyUser
    }
}

// MARK: - Codex Hook Payload

struct CodexHookPayload: Decodable {
    let sessionId: String?
    let cwd: String?
    let hookEventName: String?
    let model: String?
    let turnId: String?
    let toolName: String?
    let toolUseId: String?
    let toolInput: ToolInput?
    let permissionMode: String?
    let approvalsReviewer: String?

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case cwd
        case hookEventName = "hook_event_name"
        case model
        case turnId = "turn_id"
        case toolName = "tool_name"
        case toolUseId = "tool_use_id"
        case toolInput = "tool_input"
        case permissionMode = "permission_mode"
        case permissionModeCamel = "permissionMode"
        case approvalsReviewer = "approvals_reviewer"
        case approvalsReviewerCamel = "approvalsReviewer"
        case approvalPolicy = "approval_policy"
        case approvalPolicyCamel = "approvalPolicy"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sessionId = try container.decodeIfPresent(String.self, forKey: .sessionId)
        cwd = try container.decodeIfPresent(String.self, forKey: .cwd)
        hookEventName = try container.decodeIfPresent(String.self, forKey: .hookEventName)
        model = try container.decodeIfPresent(String.self, forKey: .model)
        turnId = try container.decodeIfPresent(String.self, forKey: .turnId)
        toolName = try container.decodeIfPresent(String.self, forKey: .toolName)
        toolUseId = try container.decodeIfPresent(String.self, forKey: .toolUseId)
        toolInput = try container.decodeIfPresent(ToolInput.self, forKey: .toolInput)
        permissionMode = Self.decodeFirstString(
            from: container,
            keys: [.permissionMode, .permissionModeCamel]
        )
        approvalsReviewer = Self.decodeFirstString(
            from: container,
            keys: [.approvalsReviewer, .approvalsReviewerCamel, .approvalPolicy, .approvalPolicyCamel]
        )
    }

    private static func decodeFirstString(
        from container: KeyedDecodingContainer<CodingKeys>,
        keys: [CodingKeys]
    ) -> String? {
        for key in keys {
            if let value = try? container.decode(String.self, forKey: key) {
                return value
            }
        }
        return nil
    }
}

struct ToolInput: Codable {
    let command: String?
}

// MARK: - Claude Hook Payload

struct ClaudeHookPayload: Codable {
    let sessionId: String?
    let cwd: String?
    let transcriptPath: String?
    let hookEventName: String?
    let permissionMode: String?
    let toolName: String?
    let toolInput: ToolInput?
    let toolUseId: String?
    let message: String?
    let title: String?
    let notificationType: String?

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case cwd
        case transcriptPath = "transcript_path"
        case hookEventName = "hook_event_name"
        case permissionMode = "permission_mode"
        case toolName = "tool_name"
        case toolInput = "tool_input"
        case toolUseId = "tool_use_id"
        case message
        case title
        case notificationType = "notification_type"
    }
}
