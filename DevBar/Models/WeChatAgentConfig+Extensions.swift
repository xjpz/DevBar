// WeChatAgentConfig+Extensions.swift
// DevBar

import Foundation

extension WeChatAgentRouter.AgentConfig {

    // MARK: - Built-in Aliases

    static let builtInAliases: [String: String] = [
        "cc": "claude",
        "cx": "codex",
    ]

    // MARK: - Detection Candidates

    struct DetectionCandidate: Sendable {
        let binaryName: String
        let agentName: String
        let type: WeChatAgentRouter.AgentConfig.AgentType
        let args: [String]?
        let priority: Int

        /// ACP=0 (highest), CLI=1
        var isACP: Bool { priority == 0 }
    }

    static let detectionCandidates: [DetectionCandidate] = [
        // Claude — ACP first, CLI fallback
        .init(binaryName: "claude-agent-acp", agentName: "claude", type: .acp, args: nil, priority: 0),
        .init(binaryName: "claude", agentName: "claude", type: .cli, args: nil, priority: 1),
        // Codex — ACP variants, CLI fallback
        .init(binaryName: "codex-acp", agentName: "codex", type: .acp, args: nil, priority: 0),
        .init(binaryName: "codex", agentName: "codex", type: .acp, args: ["app-server"], priority: 0),
        .init(binaryName: "codex", agentName: "codex", type: .cli, args: nil, priority: 1),
    ]

    // MARK: - Alias Resolution

    /// Resolve an agent name through: exact match → custom aliases → built-in aliases
    static func resolve(name: String, in agents: [WeChatAgentRouter.AgentConfig]) -> WeChatAgentRouter.AgentConfig? {
        if let exact = agents.first(where: { $0.name == name }) { return exact }
        if let byAlias = agents.first(where: { $0.aliases?.contains(name) == true }) { return byAlias }
        if let resolved = builtInAliases[name],
           let found = agents.first(where: { $0.name == resolved }) { return found }
        return nil
    }

    // MARK: - Built-in Command Names

    static let builtInCommandNames: Set<String> = ["/new", "/clear", "/help", "/info", "/cwd"]
}
