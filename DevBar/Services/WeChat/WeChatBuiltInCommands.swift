// WeChatBuiltInCommands.swift
// DevBar

import Foundation

struct WeChatBuiltInCommands {
    static let commandNames: Set<String> = ["/new", "/clear", "/help", "/info", "/cwd", "/default"]

    static func isBuiltIn(_ text: String) -> Bool {
        let word = text.split(separator: " ").first.map(String.init) ?? ""
        return commandNames.contains(word)
    }

    static func handle(
        _ text: String,
        userID: String,
        agentRouter: WeChatAgentRouter,
        conversationStore: WeChatConversationStore
    ) async -> String? {
        let parts = text.split(separator: " ", maxSplits: 1)
        let command = String(parts[0])

        switch command {
        case "/new":
            await conversationStore.clearAllSessions(userID: userID)
            return "[DevBar] 已开始新对话"

        case "/clear":
            await conversationStore.clearAllSessions(userID: userID)
            return "[DevBar] 对话已清除"

        case "/help":
            return helpText(agents: agentRouter.agents)

        case "/info":
            return infoText(agents: agentRouter.agents, defaultAgent: agentRouter.defaultAgent)

        case "/default":
            if parts.count > 1 {
                let name = String(parts[1]).trimmingCharacters(in: .whitespaces)
                let resolved = WeChatAgentRouter.AgentConfig.resolve(name: name, in: agentRouter.agents)
                if let resolved {
                    agentRouter.defaultAgent = resolved.name
                    agentRouter.saveToWeClawConfig()
                    return "[DevBar] 默认 agent 已切换为: \(resolved.name)"
                }
                return "[DevBar] 未找到 agent: \(name)。使用 /info 查看可用 agent"
            }
            return "[DevBar] 当前默认 agent: \(agentRouter.defaultAgent.isEmpty ? "未设置" : agentRouter.defaultAgent)\n用法: /default <agent_name>"

        case "/cwd":
            if parts.count > 1 {
                let path = String(parts[1]).trimmingCharacters(in: .whitespaces)
                return "[DevBar] 工作目录已设为: \(path)"
            }
            return "[DevBar] 当前工作目录: \(FileManager.default.currentDirectoryPath)"

        default:
            return nil
        }
    }

    // MARK: - Formatters

    private static func helpText(agents: [WeChatAgentRouter.AgentConfig]) -> String {
        var lines: [String] = [
            "[DevBar] 可用命令:",
            "  /new      - 开始新对话",
            "  /clear    - 清除对话历史",
            "  /help     - 显示此帮助",
            "  /info     - 显示 agent 信息",
            "  /default  - 查看/切换默认 agent",
            "  /cwd [path] - 查看/设置工作目录",
            "",
            "调用 agent:",
            "  @agent_name 消息   (指定 agent)",
            "  /agent_name 消息   (指定 agent)",
            "  直接发消息         (使用默认 agent)",
            "",
            "广播:",
            "  @a1 @a2 消息       (同时发给多个 agent)",
        ]

        if !agents.isEmpty {
            lines.append("")
            lines.append("已配置的 agent:")
            for agent in agents {
                let aliases = agent.aliases ?? []
                let aliasStr = aliases.isEmpty ? "" : " (别名: \(aliases.joined(separator: ", ")))"
                lines.append("  \(agent.name) [\(agent.type.rawValue)]\(aliasStr)")
            }
        }

        lines.append("")
        lines.append("内置别名: cc→claude, cx→codex")

        return lines.joined(separator: "\n")
    }

    private static func infoText(agents: [WeChatAgentRouter.AgentConfig], defaultAgent: String) -> String {
        var lines: [String] = [
            "[DevBar] 系统信息:",
            "默认 agent: \(defaultAgent.isEmpty ? "未设置" : defaultAgent)",
            "已配置 \(agents.count) 个 agent:",
        ]
        for agent in agents {
            var detail = "  \(agent.name) (\(agent.type.rawValue))"
            if let cmd = agent.command { detail += " cmd=\(cmd)" }
            if let ep = agent.endpoint { detail += " endpoint=\(ep)" }
            lines.append(detail)
        }
        return lines.joined(separator: "\n")
    }
}
