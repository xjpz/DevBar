import Testing
@testable import DevBar

@MainActor
struct WeChatBuiltInCommandsTests {
    @Test func statusIsRecognizedAsBuiltInCommand() {
        #expect(WeChatBuiltInCommands.isBuiltIn("/status"))
    }

    @Test func modelCommandUpdatesDefaultAgentModel() async {
        let router = WeChatAgentRouter()
        router.shouldPersistConfig = false
        let agent = Self.agent(name: "codex", command: "codex", aliases: ["cx"], model: nil)
        router.agents = [agent]
        router.defaultAgent = "codex"

        let reply = await WeChatBuiltInCommands.handle(
            "/model gpt-5.2",
            userID: "user-1",
            agentRouter: router,
            conversationStore: router.conversationStore
        )

        #expect(reply == "[DevBar] codex model 已切换为: gpt-5.2")
        #expect(router.agents.first?.model == "gpt-5.2")
    }

    private static func agent(
        name: String,
        command: String,
        aliases: [String],
        model: String?
    ) -> WeChatAgentRouter.AgentConfig {
        .init(
            name: name,
            type: .acp,
            command: command,
            args: nil,
            cwd: nil,
            env: nil,
            model: model,
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
