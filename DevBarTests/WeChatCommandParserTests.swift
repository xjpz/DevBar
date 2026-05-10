import Testing
@testable import DevBar

struct WeChatCommandParserTests {
    private let agents: [WeChatAgentRouter.AgentConfig] = [
        agent(name: "codex", command: "codex", aliases: ["cx"]),
        agent(name: "claude", command: "claude", aliases: ["cc"])
    ]

    @Test func unknownSlashCommandPassesThroughToDefaultAgent() {
        let parsed = WeChatCommandParser.parse("/status", agents: agents)

        #expect(parsed.agentNames == nil)
        #expect(parsed.message == "/status")
    }

    @Test func unknownSlashCommandWithArgumentsPassesThroughToDefaultAgent() {
        let parsed = WeChatCommandParser.parse("/model gpt-5.2", agents: agents)

        #expect(parsed.agentNames == nil)
        #expect(parsed.message == "/model gpt-5.2")
    }

    @Test func slashAliasStillSelectsAgentAndAllowsAgentSlashCommand() {
        let parsed = WeChatCommandParser.parse("/cx /status", agents: agents)

        #expect(parsed.agentNames == ["cx"])
        #expect(parsed.message == "/status")
    }

    private static func agent(
        name: String,
        command: String,
        aliases: [String]
    ) -> WeChatAgentRouter.AgentConfig {
        .init(
            name: name,
            type: .acp,
            command: command,
            args: nil,
            cwd: nil,
            env: nil,
            model: nil,
            systemPrompt: nil,
            aliases: aliases,
            endpoint: nil,
            apiKey: nil,
            headers: nil,
            maxHistory: nil,
            approvalPolicy: nil,
            approvalTimeoutSeconds: nil,
            allowWechatConfirmForLowRisk: nil,
            allowWechatConfirmForHighRisk: nil,
            codexSandbox: nil
        )
    }
}
