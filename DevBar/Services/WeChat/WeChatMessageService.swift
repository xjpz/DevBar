// WeChatMessageService.swift
// DevBar

import Combine
import Foundation

@MainActor
final class WeChatMessageService: ObservableObject {
    @Published var isRunning = false
    @Published var logLines: [LogEntry] = []

    struct LogEntry: Identifiable {
        let id = UUID()
        let time: Date
        let message: String
    }

    private var clients: [String: ILinkClient] = [:]
    private var pollTasks: [String: Task<Void, Never>] = [:]
    private var agentRouter: WeChatAgentRouter?
    private let dedup = WeChatMessageDedup()

    func start(accounts: [ILinkCredentials], router: WeChatAgentRouter?) {
        stop()
        self.agentRouter = router

        for account in accounts {
            let client = ILinkClient(credentials: account)
            clients[account.ilinkBotID] = client

            let task = Task { [weak self] in
                await self?.runPollLoop(client: client, botID: account.ilinkBotID)
            } as Task<Void, Never>
            pollTasks[account.ilinkBotID] = task
        }

        isRunning = true
        addLog("Started polling \(accounts.count) account(s)")
        print("[WeChat:Poll] started, accounts=\(accounts.map(\.ilinkBotID)), hasRouter=\(router != nil), agents=\(router?.agents.count ?? 0)")
    }

    func stop() {
        for (_, task) in pollTasks { task.cancel() }
        pollTasks.removeAll()
        clients.removeAll()
        agentRouter = nil
        isRunning = false
        addLog("Stopped")
        print("[WeChat:Poll] stopped")
    }

    // MARK: - Poll Loop

    private func runPollLoop(client: ILinkClient, botID: String) async {
        var buf = ""
        var consecutiveErrors = 0
        var pollCount = 0

        print("[WeChat:Poll:\(botID)] loop started")

        while !Task.isCancelled {
            do {
                pollCount += 1
                if pollCount <= 3 || pollCount % 10 == 0 {
                    addLog("Poll #\(pollCount) buf=\(buf.prefix(16))...")
                }

                let response = try await client.getUpdates(buf: buf)
                consecutiveErrors = 0

                print("[WeChat:Poll:\(botID)] getUpdates ret=\(response.ret) errcode=\(response.errcode.map { String($0) } ?? "nil") msgs=\(response.msgs.map { "\($0.count)" } ?? "nil") buf=\(response.getUpdatesBuf?.prefix(16) ?? "nil")")

                if response.isSessionExpired {
                    addLog("Session expired for \(botID)")
                    break
                }
                if !response.isSuccess {
                    addLog("getUpdates error: ret=\(response.ret) \(response.errmsg ?? "unknown")")
                    try? await Task.sleep(nanoseconds: 5_000_000_000)
                    continue
                }

                buf = response.getUpdatesBuf ?? buf

                if let msgs = response.msgs {
                    print("[WeChat:Poll:\(botID)] received \(msgs.count) message(s)")
                    for msg in msgs {
                        print("[WeChat:Poll:\(botID)] msg seq=\(msg.seq?.description ?? "nil") type=\(msg.messageType?.description ?? "nil") from=\(msg.fromUserID?.description ?? "nil") isUser=\(msg.isFromUser) text=\(msg.textContent.map { String($0.prefix(40)) } ?? "nil")")
                        if msg.isFromUser {
                            await handleMessage(msg, client: client, botID: botID)
                        }
                    }
                } else {
                    // Normal: long-poll timeout returns no msgs
                    if pollCount <= 3 {
                        print("[WeChat:Poll:\(botID)] no msgs (long-poll timeout or empty)")
                    }
                }
            } catch is CancellationError {
                print("[WeChat:Poll:\(botID)] cancelled")
                break
            } catch {
                consecutiveErrors += 1
                let nsError = error as NSError
                let isTimeout = nsError.code == NSURLErrorTimedOut ||
                                nsError.code == NSURLErrorNetworkConnectionLost
                print("[WeChat:Poll:\(botID)] error domain=\(nsError.domain) code=\(nsError.code) timeout=\(isTimeout) msg=\(error.localizedDescription)")
                if isTimeout { continue }
                let delay = min(3 * consecutiveErrors, 30)
                addLog("Poll error (\(consecutiveErrors)): \(error.localizedDescription)")
                try? await Task.sleep(nanoseconds: UInt64(delay) * 1_000_000_000)
            }
        }

        print("[WeChat:Poll:\(botID)] loop ended, polls=\(pollCount)")
    }

    // MARK: - Message Handling

    private func handleMessage(_ msg: WeixinMessage, client: ILinkClient, botID: String) async {
        guard let text = msg.textContent, !text.isEmpty else {
            print("[WeChat:Msg] skipped: no text content")
            return
        }
        guard let fromID = msg.fromUserID else {
            print("[WeChat:Msg] skipped: no fromUserID")
            return
        }

        // Message dedup (seq-based + content-based)
        let msgKey = "\(botID)-\(msg.seq ?? 0)"
        let isDuplicate = await dedup.checkAndMark(msgKey)
        if isDuplicate {
            print("[WeChat:Msg] skipped: duplicate \(msgKey)")
            return
        }
        let isContentDup = await dedup.isContentDuplicate(userID: fromID, text: text)
        if isContentDup {
            print("[WeChat:Msg] skipped: content duplicate from \(fromID)")
            return
        }

        addLog("From \(fromID): \(text.prefix(50))")

        guard let router = agentRouter else {
            addLog("No agent router configured")
            print("[WeChat:Msg] ERROR: no agent router")
            return
        }

        // 1. Check built-in commands
        if WeChatBuiltInCommands.isBuiltIn(text) {
            print("[WeChat:Msg] built-in command: \(text)")
            if let reply = await WeChatBuiltInCommands.handle(
                text, userID: fromID, agentRouter: router,
                conversationStore: router.conversationStore
            ) {
                addLog("Reply (builtin): \(reply.prefix(40))")
                await sendReply(reply, client: client, from: botID, to: fromID, token: msg.contextToken)
            }
            return
        }

        // 2. Parse command
        let (agentNames, message) = parseCommand(text)
        let targetAgent = agentNames?.first ?? router.defaultAgent
        print("[WeChat:Msg] routing: target=\(targetAgent) names=\(agentNames?.description ?? "nil") msg=\(message.prefix(40))")

        do {
            let reply: String
            if let names = agentNames, names.count > 1 {
                // Multi-agent broadcast
                reply = await router.routeToMultiple(
                    agentNames: names, userID: fromID, message: message
                )
            } else {
                reply = try await router.route(
                    agentName: agentNames?.first, userID: fromID, message: message
                )
            }

            addLog("Reply: \(reply.prefix(60))")
            await sendReply(reply, client: client, from: botID, to: fromID, token: msg.contextToken)
        } catch {
            addLog("Agent error: \(error.localizedDescription)")
            print("[WeChat:Msg] agent error: \(error)")
        }
    }

    // MARK: - Command Parsing

    /// Supports: `@agent msg`, `/agent msg`, `@a1 @a2 msg`, plain text
    private func parseCommand(_ text: String) -> (agentNames: [String]?, message: String) {
        // @agent @agent2 msg — multi-agent broadcast
        if text.hasPrefix("@") {
            let parts = text.split(separator: " ", omittingEmptySubsequences: true)
            var agents: [String] = []
            var messageStart = 0
            for (i, part) in parts.enumerated() {
                if part.hasPrefix("@") {
                    agents.append(String(part.dropFirst()))
                    messageStart = i + 1
                } else {
                    break
                }
            }
            let message = parts[messageStart...].joined(separator: " ")
            return (agents.isEmpty ? nil : agents, message.isEmpty ? text : message)
        }

        // /agent msg — single agent (exclude built-in commands)
        if text.hasPrefix("/") {
            let firstWord = text.split(separator: " ").first.map(String.init) ?? ""
            let withoutSlash = String(firstWord.dropFirst())
            if !WeChatAgentRouter.AgentConfig.builtInCommandNames.contains(firstWord) && !withoutSlash.isEmpty {
                let parts = text.dropFirst().split(separator: " ", maxSplits: 1)
                guard parts.count >= 1 else { return (nil, text) }
                let agentName = String(parts[0])
                let message = parts.count > 1 ? String(parts[1]) : ""
                return ([agentName], message)
            }
        }

        // Default agent
        return (nil, text)
    }

    // MARK: - Helpers

    private func sendReply(_ text: String, client: ILinkClient, from: String, to: String, token: String?) async {
        do {
            let response = try await client.sendText(from: from, to: to, text: text, contextToken: token)
            if response.isSuccess {
                addLog("Reply sent to \(to)")
            } else {
                addLog("Send failed: \(response.errmsg ?? "unknown")")
                print("[WeChat:Send] failed: ret=\(response.ret) \(response.errmsg ?? "")")
            }
        } catch {
            addLog("Send error: \(error.localizedDescription)")
            print("[WeChat:Send] error: \(error)")
        }
    }

    private func addLog(_ message: String) {
        let entry = LogEntry(time: Date(), message: message)
        logLines.append(entry)
        if logLines.count > 200 {
            logLines.removeFirst(logLines.count - 200)
        }
    }
}
