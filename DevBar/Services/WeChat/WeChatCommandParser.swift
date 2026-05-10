// WeChatCommandParser.swift
// DevBar

import Foundation

struct WeChatCommandParser {
    struct ParsedCommand: Equatable {
        let agentNames: [String]?
        let message: String
    }

    /// Supports: `@agent msg`, `/agent msg`, `@a1 @a2 msg`, plain text.
    /// Unknown slash commands are passed through to the default agent unchanged.
    static func parse(
        _ text: String,
        agents configuredAgents: [WeChatAgentRouter.AgentConfig]
    ) -> ParsedCommand {
        // @agent @agent2 msg - multi-agent broadcast
        if text.hasPrefix("@") {
            let parts = text.split(separator: " ", omittingEmptySubsequences: true)
            var agents: [String] = []
            var messageStart = 0
            for (index, part) in parts.enumerated() {
                if part.hasPrefix("@") {
                    agents.append(String(part.dropFirst()))
                    messageStart = index + 1
                } else {
                    break
                }
            }
            let message = parts[messageStart...].joined(separator: " ")
            return ParsedCommand(agentNames: agents.isEmpty ? nil : agents, message: message.isEmpty ? text : message)
        }

        // /agent msg - single agent only when the slash head resolves to a configured agent or alias.
        if text.hasPrefix("/") {
            let firstWord = text.split(separator: " ").first.map(String.init) ?? ""
            let withoutSlash = String(firstWord.dropFirst())
            if !WeChatAgentRouter.AgentConfig.builtInCommandNames.contains(firstWord),
               !withoutSlash.isEmpty,
               WeChatAgentRouter.AgentConfig.resolve(name: withoutSlash, in: configuredAgents) != nil {
                let parts = text.dropFirst().split(separator: " ", maxSplits: 1)
                guard parts.count >= 1 else { return ParsedCommand(agentNames: nil, message: text) }
                let agentName = String(parts[0])
                let message = parts.count > 1 ? String(parts[1]) : ""
                return ParsedCommand(agentNames: [agentName], message: message)
            }
        }

        return ParsedCommand(agentNames: nil, message: text)
    }
}
