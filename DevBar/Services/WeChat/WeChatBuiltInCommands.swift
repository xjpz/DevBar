// WeChatBuiltInCommands.swift
// DevBar

import Foundation

struct WeChatBuiltInCommands {
    static let commandNames: Set<String> = ["/new", "/clear", "/help", "/info", "/status", "/model", "/cwd", "/default", "/pending", "/cancel"]

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

        case "/status":
            return statusText(agentRouter: agentRouter)

        case "/model":
            return await handleModelCommand(parts: parts, userID: userID, agentRouter: agentRouter, conversationStore: conversationStore)

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

        case "/pending":
            return agentRouter.approvalCoordinator.pendingSummary(userID: userID)

        case "/cancel":
            guard parts.count > 1 else {
                return "[DevBar] 用法: /cancel <授权ID>"
            }
            let id = String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
            return agentRouter.approvalCoordinator.cancelPending(id: id, userID: userID)

        case "/cwd":
            if parts.count > 1 {
                let rawPath = String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
                if rawPath.lowercased() == "list" {
                    let agent = WeChatAgentRouter.AgentConfig.resolve(name: agentRouter.defaultAgent, in: agentRouter.agents)
                    return agentRouter.authorizedDirectoryStore.remoteListText(currentAgent: agent)
                }

                let path = normalizedInputPath(rawPath)
                guard let agent = WeChatAgentRouter.AgentConfig.resolve(name: agentRouter.defaultAgent, in: agentRouter.agents) else {
                    return "[DevBar] 当前没有默认 agent，无法设置工作目录。请先使用 /default <agent_name> 设置默认 agent。"
                }

                guard agentRouter.authorizedDirectoryStore.isPathAllowedRemotely(path) else {
                    return "[DevBar] 工作目录设置失败: \(agentRouter.authorizedDirectoryStore.unauthorizedRemoteMessage(for: path))"
                }

                let directoryAccess: WeChatAuthorizedDirectoryAccess?
                do {
                    directoryAccess = try agentRouter.authorizedDirectoryStore.accessHandle(for: path)
                } catch {
                    return "[DevBar] 工作目录设置失败: \(error.localizedDescription)"
                }
                defer {
                    directoryAccess?.stop()
                }

                let access = WeChatWorkingDirectoryPolicy.validateAccess(for: path)
                guard access.isAccessible else {
                    return "[DevBar] 工作目录设置失败: \(access.path)\n\(access.message ?? String(localized: "wechat_cwd_access_failed"))"
                }

                agentRouter.updateAgentWorkingDirectory(agent, cwd: access.path)
                await conversationStore.clearSession(userID: userID, agentName: agent.name)
                return "[DevBar] \(agent.name) 工作目录已设为: \(access.path)"
            }
            if let agent = WeChatAgentRouter.AgentConfig.resolve(name: agentRouter.defaultAgent, in: agentRouter.agents) {
                return "[DevBar] \(agent.name) 当前工作目录: \(WeChatWorkingDirectoryPolicy.effectiveDirectory(for: agent.cwd))"
            }
            return "[DevBar] 当前工作目录: \(WeChatWorkingDirectoryPolicy.ensureDefaultDirectory())"

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
            "  /status   - 显示当前 agent 状态",
            "  /model [name] - 查看/切换当前 agent model",
            "  /default  - 查看/切换默认 agent",
            "  /pending  - 查看待授权请求",
            "  /cancel <id> - 取消待授权请求",
            "  /cwd [path] - 查看/设置工作目录",
            "  /cwd list - 查看远程可用目录",
            "",
            "调用 agent:",
            "  @agent_name 消息   (指定 agent)",
            "  /agent_name 消息   (指定 agent)",
            "  /agent_name /命令   (把 slash 命令发给指定 agent)",
            "  直接发消息         (使用默认 agent)",
            "  未知 /命令         (发送给默认 agent)",
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

    private static func statusText(agentRouter: WeChatAgentRouter) -> String {
        let defaultName = agentRouter.defaultAgent
        var lines: [String] = ["[DevBar] 状态:"]
        lines.append("默认 agent: \(defaultName.isEmpty ? "未设置" : defaultName)")

        if let agent = WeChatAgentRouter.AgentConfig.resolve(name: defaultName, in: agentRouter.agents) {
            lines.append("当前 agent: \(agent.name) (\(agent.type.rawValue))")
            if let model = agent.model, !model.isEmpty {
                lines.append("model: \(model)")
            } else {
                lines.append("model: 默认")
            }
            lines.append("cwd: \(WeChatWorkingDirectoryPolicy.effectiveDirectory(for: agent.cwd))")
            lines.append("授权: \(agent.effectiveApprovalPolicy.displayName)")
            if agent.type == .acp {
                lines.append("沙盒: \(agent.effectiveCodexSandbox.displayName)")
            }
        } else if !defaultName.isEmpty {
            lines.append("当前 agent: 未找到 \(defaultName)")
        }

        lines.append("已配置 agent: \(agentRouter.agents.count)")
        return lines.joined(separator: "\n")
    }

    private static func handleModelCommand(
        parts: [Substring],
        userID: String,
        agentRouter: WeChatAgentRouter,
        conversationStore: WeChatConversationStore
    ) async -> String {
        guard let agent = WeChatAgentRouter.AgentConfig.resolve(name: agentRouter.defaultAgent, in: agentRouter.agents) else {
            return "[DevBar] 当前没有默认 agent，无法查看或设置 model。请先使用 /default <agent_name> 设置默认 agent。"
        }

        guard parts.count > 1 else {
            let model = agent.model?.isEmpty == false ? agent.model! : "默认"
            return "[DevBar] \(agent.name) 当前 model: \(model)\n用法: /model <model_name>"
        }

        let rawModel = String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
        if rawModel.lowercased() == "default" || rawModel.lowercased() == "reset" {
            agentRouter.updateAgentModel(agent, model: nil)
            await conversationStore.clearSession(userID: userID, agentName: agent.name)
            return "[DevBar] \(agent.name) model 已恢复默认"
        }

        guard !rawModel.isEmpty else {
            return "[DevBar] 用法: /model <model_name>"
        }

        agentRouter.updateAgentModel(agent, model: rawModel)
        await conversationStore.clearSession(userID: userID, agentName: agent.name)
        return "[DevBar] \(agent.name) model 已切换为: \(rawModel)"
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

    private static func normalizedInputPath(_ path: String) -> String {
        if path.hasPrefix("/") || path.hasPrefix("~") {
            return path
        }
        if path.hasPrefix("Users/") {
            return "/" + path
        }
        return path
    }
}
