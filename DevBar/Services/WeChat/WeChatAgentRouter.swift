// WeChatAgentRouter.swift
// DevBar

import Combine
import Foundation

private final class CLIPipeBuffer: @unchecked Sendable {
    private let lock = NSLock()
    nonisolated(unsafe) private var data = Data()

    nonisolated func append(_ chunk: Data) {
        guard !chunk.isEmpty else { return }
        lock.lock()
        data.append(chunk)
        lock.unlock()
    }

    nonisolated var stringValue: String {
        lock.lock()
        let snapshot = data
        lock.unlock()
        return String(data: snapshot, encoding: .utf8) ?? ""
    }
}

private final class ProcessExitWaiter: @unchecked Sendable {
    private let lock = NSLock()
    nonisolated(unsafe) private var didResume = false
    nonisolated(unsafe) private var continuation: CheckedContinuation<Bool, Never>?

    nonisolated func wait(for process: Process, timeoutSeconds: UInt64) async -> Bool {
        await withCheckedContinuation { continuation in
            lock.lock()
            self.continuation = continuation
            lock.unlock()

            process.terminationHandler = { [weak self] _ in
                self?.resume(true)
            }

            Task.detached { [weak self] in
                try? await Task.sleep(nanoseconds: timeoutSeconds * 1_000_000_000)
                guard process.isRunning else { return }
                process.terminate()
                self?.resume(false)
            }
        }
    }

    nonisolated private func resume(_ completed: Bool) {
        lock.lock()
        guard !didResume else {
            lock.unlock()
            return
        }
        didResume = true
        let continuation = continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(returning: completed)
    }
}

@MainActor
final class WeChatAgentRouter: ObservableObject {
    @Published var agents: [AgentConfig] = []
    @Published var defaultAgent: String = ""

    let conversationStore = WeChatConversationStore()
    let approvalCoordinator = WeChatApprovalCoordinator()
    let authorizedDirectoryStore = WeChatAuthorizedDirectoryStore()

    struct AgentConfig: Codable, Identifiable, Sendable {
        var id: String { name }
        let name: String
        let type: AgentType
        let command: String?
        let args: [String]?
        let cwd: String?
        let env: [String: String]?
        let model: String?
        let systemPrompt: String?
        let aliases: [String]?
        let endpoint: String?
        let apiKey: String?
        let headers: [String: String]?
        let maxHistory: Int?
        let approvalPolicy: ApprovalPolicy?
        let approvalTimeoutSeconds: Int?
        let allowWechatConfirmForLowRisk: Bool?
        let allowWechatConfirmForHighRisk: Bool?

        enum AgentType: String, Codable, Sendable {
            case acp, cli, http
        }

        enum ApprovalPolicy: String, Codable, Sendable, CaseIterable, Identifiable {
            case never
            case wechatConfirm
            case macConfirm
            case trusted

            var id: String { rawValue }

            var displayName: String {
                switch self {
                case .never: return "拒绝高风险"
                case .wechatConfirm: return "微信确认"
                case .macConfirm: return "Mac 确认"
                case .trusted: return "信任"
                }
            }
        }

        var effectiveApprovalPolicy: ApprovalPolicy {
            approvalPolicy ?? .macConfirm
        }

        var effectiveApprovalTimeoutSeconds: Int {
            max(30, approvalTimeoutSeconds ?? 120)
        }

        var canWechatApproveLowRisk: Bool {
            allowWechatConfirmForLowRisk ?? true
        }

        var canWechatApproveHighRisk: Bool {
            allowWechatConfirmForHighRisk ?? false
        }

        func allowsWechatApproval(for risk: WeChatApprovalRequest.Risk) -> Bool {
            guard effectiveApprovalPolicy == .wechatConfirm else { return false }
            return risk != .high || canWechatApproveHighRisk
        }
    }

    private struct WeClawConfig: Codable, Sendable {
        let defaultAgent: String?
        let agents: [String: AgentConfig]?

        enum CodingKeys: String, CodingKey {
            case defaultAgent = "default_agent"
            case agents
        }
    }

    // MARK: - ACP Client Pool

    private var acpClients: [String: ACPClient] = [:]
    private var acpDirectoryAccess: [String: WeChatAuthorizedDirectoryAccess] = [:]

    // MARK: - Config I/O

    func loadFromWeClawConfig() {
        let configURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".weclaw/config.json")

        guard let data = try? Data(contentsOf: configURL) else { return }
        guard let config = try? JSONDecoder().decode(WeClawConfig.self, from: data) else { return }

        defaultAgent = config.defaultAgent ?? ""
        agents = config.agents?.map { _, value in value } ?? []
    }

    func addHTTPAgent(name: String, endpoint: String, apiKey: String?, model: String?) {
        let agent = AgentConfig(
            name: name, type: .http, command: nil, args: nil,
            cwd: nil, env: nil, model: model, systemPrompt: nil,
            aliases: nil, endpoint: endpoint, apiKey: apiKey,
            headers: nil, maxHistory: nil,
            approvalPolicy: nil, approvalTimeoutSeconds: nil,
            allowWechatConfirmForLowRisk: nil, allowWechatConfirmForHighRisk: nil
        )
        agents.append(agent)
        if defaultAgent.isEmpty { defaultAgent = name }
        saveToWeClawConfig()
    }

    func addAgent(_ agent: AgentConfig) {
        agents.append(agent)
        if defaultAgent.isEmpty { defaultAgent = agent.name }
        saveToWeClawConfig()
    }

    func deleteAgent(_ agent: AgentConfig) {
        agents.removeAll { $0.name == agent.name }
        if defaultAgent == agent.name {
            defaultAgent = agents.first?.name ?? ""
        }
        // Stop ACP client if running
        if let client = acpClients.removeValue(forKey: agent.name) {
            let directoryAccess = acpDirectoryAccess.removeValue(forKey: agent.name)
            Task {
                await client.stop()
                directoryAccess?.stop()
            }
        }
        saveToWeClawConfig()
    }

    func updateAgentWorkingDirectory(_ agent: AgentConfig, cwd: String?) {
        guard let index = agents.firstIndex(where: { $0.name == agent.name }) else { return }
        let trimmed = cwd?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        agents[index] = agent.updating(cwd: trimmed.isEmpty ? nil : trimmed)
        if let client = acpClients.removeValue(forKey: agent.name) {
            let directoryAccess = acpDirectoryAccess.removeValue(forKey: agent.name)
            Task {
                await client.stop()
                directoryAccess?.stop()
            }
        }
        saveToWeClawConfig()
    }

    func updateAgentApprovalPolicy(_ agent: AgentConfig, policy: AgentConfig.ApprovalPolicy) {
        guard let index = agents.firstIndex(where: { $0.name == agent.name }) else { return }
        agents[index] = agent.updating(approvalPolicy: policy)
        saveToWeClawConfig()
    }

    func updateAgentHighRiskWechatApproval(_ agent: AgentConfig, isAllowed: Bool) {
        guard let index = agents.firstIndex(where: { $0.name == agent.name }) else { return }
        agents[index] = agent.updating(allowWechatConfirmForHighRisk: isAllowed)
        saveToWeClawConfig()
    }

    func saveToWeClawConfig() {
        let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".weclaw")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        var agentsDict: [String: AgentConfig] = [:]
        for agent in agents { agentsDict[agent.name] = agent }

        let config = WeClawConfig(defaultAgent: defaultAgent.isEmpty ? nil : defaultAgent, agents: agentsDict)
        guard let data = try? JSONEncoder().encode(config) else { return }

        let configURL = dir.appendingPathComponent("config.json")
        try? data.write(to: configURL, options: .atomic)
    }

    // MARK: - Routing

    func route(
        agentName: String?,
        userID: String,
        message: String,
        approvalNotifier: ((String) async -> Void)? = nil
    ) async throws -> String {
        let targetName = agentName ?? defaultAgent
        guard !targetName.isEmpty else {
            return String(localized: "wechat_no_agent_configured")
        }

        guard let agent = AgentConfig.resolve(name: targetName, in: agents) else {
            return String(format: String(localized: "wechat_agent_not_found"), targetName)
        }

        let trimmedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedMessage.isEmpty else {
            let isDefault = agent.name == defaultAgent
            let hint = isDefault
                ? "\(agent.name) is the default agent. Just send a message directly."
                : "Current default agent: \(defaultAgent.isEmpty ? "none" : defaultAgent). Use /\(agent.name) <message> to route."
            return "Usage: /\(agent.name) <message>\n\(hint)"
        }

        print("[WeChat:Route] agent=\(agent.name) type=\(agent.type) msg=\(trimmedMessage.prefix(40))")

        switch agent.type {
        case .http:
            return try await callHTTPAgent(agent, userID: userID, message: trimmedMessage)
        case .cli:
            return try await callCLIAgent(agent, userID: userID, message: trimmedMessage, approvalNotifier: approvalNotifier)
        case .acp:
            return try await callACPAgent(agent, userID: userID, message: trimmedMessage)
        }
    }

    func routeToMultiple(agentNames: [String], userID: String, message: String) async -> String {
        var replies: [(String, String)] = []

        await withTaskGroup(of: (String, String?).self) { group in
            for name in agentNames {
                group.addTask {
                    do {
                        let reply = try await self.route(agentName: name, userID: userID, message: message)
                        return (name, reply)
                    } catch {
                        return (name, "Error: \(error.localizedDescription)")
                    }
                }
            }
            for await (name, reply) in group {
                if let reply { replies.append((name, reply)) }
            }
        }

        return replies.map { "[\($0.0)] \($0.1)" }.joined(separator: "\n---\n")
    }

    func handleApprovalReply(_ text: String, userID: String) -> String? {
        let parts = text.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard parts.count == 2 else { return nil }
        let decision = parts[0].lowercased()
        guard decision == "y" || decision == "yes" || decision == "n" || decision == "no" else { return nil }

        let id = parts[1]
        guard let request = approvalCoordinator.pendingRequest(id: id, userID: userID) else {
            return "未找到待处理授权 \(id)。"
        }

        let approved = decision == "y" || decision == "yes"
        if approved {
            guard request.allowsWechatApproval else {
                return "授权 \(request.id) 需要在 Mac 端 DevBar 确认。"
            }
        }

        return approvalCoordinator.resolve(
            id: request.id,
            userID: userID,
            approved: approved,
            source: .wechat
        )
    }

    // MARK: - HTTP Agent

    private func callHTTPAgent(_ agent: AgentConfig, userID: String, message: String) async throws -> String {
        guard let endpoint = agent.endpoint else {
            return "Agent \(agent.name): no endpoint configured"
        }

        // Build message array with history
        var messages: [[String: String]] = []
        if let prompt = agent.systemPrompt, !prompt.isEmpty {
            messages.append(["role": "system", "content": prompt])
        }

        let session = await conversationStore.getOrCreateSession(userID: userID, agentName: agent.name)
        for msg in session.httpHistory {
            messages.append(["role": msg.role.rawValue, "content": msg.content])
        }
        messages.append(["role": "user", "content": message])

        guard let url = URL(string: endpoint), url.scheme != nil else {
            return "Agent \(agent.name): invalid endpoint URL"
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let apiKey = agent.apiKey {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        if let headers = agent.headers {
            for (key, value) in headers { request.setValue(value, forHTTPHeaderField: key) }
        }

        let body: [String: Any] = [
            "model": agent.model ?? "default",
            "messages": messages,
            "max_tokens": 4096,
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw ILinkError.httpError(code)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let first = choices.first,
              let msg = first["message"] as? [String: Any],
              let content = msg["content"] as? String else {
            return String(localized: "wechat_invalid_agent_response")
        }

        // Save to history
        await conversationStore.appendHTTPHistory(
            userID: userID, agentName: agent.name,
            user: message, assistant: content
        )

        return content
    }

    // MARK: - CLI Agent

    private func callCLIAgent(
        _ agent: AgentConfig,
        userID: String,
        message: String,
        approvalNotifier: ((String) async -> Void)?
    ) async throws -> String {
        guard let command = agent.command else {
            return "Agent \(agent.name): no command configured"
        }

        let session = await conversationStore.getOrCreateSession(userID: userID, agentName: agent.name)

        let process = Process()
        let pipe = Pipe()
        let stderrPipe = Pipe()
        let stdoutBuffer = CLIPipeBuffer()
        let stderrBuffer = CLIPipeBuffer()

        var args = agent.args ?? []
        let isClaude = agent.name == "claude" || command.hasSuffix("claude")
        let isCodex = agent.name == "codex" || command.hasSuffix("codex")
        if isClaude {
            args += ["-p", message, "--output-format", "json"]
            if let sid = session.cliSessionID {
                args += ["--resume", sid]
            }
        } else if isCodex {
            args += ["exec", "--skip-git-repo-check"]
            let cwd = Self.effectiveWorkingDirectory(for: agent)
            args += ["--cd", cwd]
            args += [message]
        } else {
            args += [message]
        }

        // Resolve shebang: for scripts with #!/usr/bin/env, find interpreter and run directly.
        // This avoids relying on zsh login shell (which fails in GUI context due to nvm init issues).
        let (resolvedExec, resolvedArgs) = Self.resolveShebang(command: command, args: args)
        let cwd = Self.effectiveWorkingDirectory(for: agent)

        if let approvalResult = await requestCLIApprovalIfNeeded(
            agent: agent,
            userID: userID,
            message: message,
            command: resolvedExec,
            arguments: resolvedArgs,
            cwd: cwd,
            approvalNotifier: approvalNotifier
        ), !approvalResult.allowed {
            return approvalResult.message
        }

        let directoryAccess: WeChatAuthorizedDirectoryAccess?
        do {
            directoryAccess = try authorizedDirectoryStore.accessHandle(for: cwd)
        } catch {
            return error.localizedDescription
        }
        defer {
            directoryAccess?.stop()
        }

        process.executableURL = URL(fileURLWithPath: resolvedExec)
        process.arguments = resolvedArgs

        process.standardOutput = pipe
        process.standardError = stderrPipe

        process.currentDirectoryURL = URL(fileURLWithPath: cwd)

        // Build environment: start with the app environment, then enrich PATH dynamically.
        var envDict = ProcessInfo.processInfo.environment
        if let extra = agent.env {
            envDict.merge(extra) { _, new in new }
        }
        // Do not leak Xcode/App debug malloc logging into CLI agents; it pollutes stderr.
        for key in envDict.keys where key.hasPrefix("Malloc") || key.hasPrefix("DYLD_") {
            envDict.removeValue(forKey: key)
        }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        envDict["HOME"] = home
        envDict["PATH"] = WeChatShellEnvironment.buildPATH(environment: envDict)
        process.environment = envDict

        let inputPipe = Pipe()
        process.standardInput = inputPipe
        try inputPipe.fileHandleForWriting.close()

        pipe.fileHandleForReading.readabilityHandler = { handle in
            stdoutBuffer.append(handle.availableData)
        }
        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            stderrBuffer.append(handle.availableData)
        }

        print("[WeChat:CLI] exec=\(process.executableURL?.path ?? "?") args=\(process.arguments ?? [])")
        try process.run()
        print("[WeChat:CLI] pid=\(process.processIdentifier) started")

        let timeoutSeconds: UInt64 = isCodex ? 180 : 120
        let completed = await ProcessExitWaiter().wait(for: process, timeoutSeconds: timeoutSeconds)

        pipe.fileHandleForReading.readabilityHandler = nil
        stderrPipe.fileHandleForReading.readabilityHandler = nil

        if completed {
            stdoutBuffer.append(pipe.fileHandleForReading.readDataToEndOfFile())
            stderrBuffer.append(stderrPipe.fileHandleForReading.readDataToEndOfFile())
        } else {
            print("[WeChat:CLI] timeout after \(timeoutSeconds)s, terminated pid=\(process.processIdentifier)")
        }

        let output = stdoutBuffer.stringValue
        let stderr = stderrBuffer.stringValue

        if !completed {
            let partial = parseCodexOutput(stdout: output, stderr: stderr)
            if isCodex, !partial.isEmpty {
                return partial
            }
            return "\(agent.name) timed out after \(timeoutSeconds)s"
        }

        print("[WeChat:CLI] exit=\(process.terminationStatus) stdout=\(output.prefix(200))")
        print("[WeChat:CLI] stderr=\(stderr.prefix(800))")

        if isClaude {
            // Parse JSON output: {"type":"result","session_id":"...","result":"..."}
            if let data = output.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let sid = json["session_id"] as? String {
                    await conversationStore.updateSession(userID: userID, agentName: agent.name) { s in
                        s.cliSessionID = sid
                    }
                }
                if let result = json["result"] as? String, !result.isEmpty {
                    return result
                }
            }

            // Fallback: try stream-json parsing (in case output is multi-line)
            let parsed = parseClaudeOutput(from: output)
            if !parsed.isEmpty { return parsed }

            if process.terminationStatus != 0 {
                let reason = cleanCLIError(stderr)
                if !reason.isEmpty {
                    return "Claude exited with code \(process.terminationStatus):\n\(reason)"
                }
                return "Claude exited with code \(process.terminationStatus)"
            }
            return "Claude returned empty response"
        }

        // Codex CLI prints the final answer to stdout. stderr is mostly runtime logs.
        if isCodex {
            if process.terminationStatus != 0 {
                let reason = cleanCLIError(stderr)
                if !reason.isEmpty {
                    return "Codex exited with code \(process.terminationStatus):\n\(reason)"
                }
                return "Codex exited with code \(process.terminationStatus)"
            }
            let reply = parseCodexOutput(stdout: output, stderr: "")
            if !reply.isEmpty { return reply }
            let stderrFallback = parseCodexOutput(stdout: "", stderr: stderr)
            if !stderrFallback.isEmpty { return stderrFallback }
            return "Codex returned empty response"
        }

        // Generic CLI: return raw output
        return output
    }

    /// Parse Codex CLI output. Current Codex prints final text to stdout; older variants may
    /// put transcript-style output in stderr, so stderr parsing remains as a fallback.
    private func parseCodexOutput(stdout: String, stderr: String) -> String {
        let cleanStdout = cleanCodexReply(stdout)
        if !cleanStdout.isEmpty {
            return cleanStdout
        }

        let combined = [stdout, stderr]
            .filter { !$0.isEmpty }
            .joined(separator: "\n")

        if let reply = codexReplyAfterMarker(in: combined, marker: "codex") {
            return reply
        }
        if let reply = codexReplyAfterMarker(in: combined, marker: "assistant") {
            return reply
        }

        let lines = combined.components(separatedBy: "\n")

        // Find the AI response after the last "--------" separator and "user" line
        var afterSeparator = false
        var responseLines: [String] = []

        for line in lines {
            if line.hasPrefix("--------") {
                afterSeparator = true
                responseLines.removeAll()
                continue
            }
            if afterSeparator {
                // Skip the "user" prompt line and codex banner lines
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed == "user" || trimmed.isEmpty { continue }
                // Skip known codex metadata lines
                if trimmed.hasPrefix("Reading additional") ||
                   trimmed.hasPrefix("OpenAI Codex v") ||
                   trimmed.hasPrefix("workdir:") ||
                   trimmed.hasPrefix("model:") ||
                   trimmed.hasPrefix("provider:") ||
                   trimmed.hasPrefix("approval:") ||
                   trimmed.hasPrefix("sandbox:") ||
                   trimmed.hasPrefix("reasoning") ||
                   trimmed.hasPrefix("session id:") { continue }
                responseLines.append(line)
            }
        }

        // If no structured output found, try returning everything after "assistant" marker
        if responseLines.isEmpty {
            if let assistantRange = combined.range(of: "\nassistant\n") {
                let afterAssistant = combined[assistantRange.upperBound...]
                let text = cleanCodexReply(String(afterAssistant))
                if !text.isEmpty { return text }
            }
            // Fallback: return the combined output trimmed
            let trimmed = cleanCodexReply(combined)
            if !trimmed.isEmpty { return trimmed }
        }

        return cleanCodexReply(responseLines.joined(separator: "\n"))
    }

    private func codexReplyAfterMarker(in output: String, marker: String) -> String? {
        guard let range = output.range(of: "\n\(marker)\n", options: .backwards) else {
            return nil
        }
        let reply = cleanCodexReply(String(output[range.upperBound...]))
        return reply.isEmpty ? nil : reply
    }

    private func cleanCodexReply(_ output: String) -> String {
        var lines: [String] = []
        for rawLine in output.components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line == "tokens used" { break }
            if line.hasPrefix("ERROR: Reconnecting") { continue }
            if line.range(of: #"^\d{4}-\d{2}-\d{2}T.*\sERROR\s"#, options: .regularExpression) != nil { continue }
            if line.hasPrefix("Reading additional input from stdin") { continue }
            if line.hasPrefix("OpenAI Codex v") { continue }
            if line.hasPrefix("workdir:") ||
               line.hasPrefix("model:") ||
               line.hasPrefix("provider:") ||
               line.hasPrefix("approval:") ||
               line.hasPrefix("sandbox:") ||
               line.hasPrefix("reasoning") ||
               line.hasPrefix("session id:") { continue }
            if line == "user" || line == "codex" || line == "assistant" { continue }
            if line.hasPrefix("--------") { continue }
            if !line.isEmpty { lines.append(rawLine) }
        }
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func cleanCLIError(_ stderr: String) -> String {
        stderr
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { line in
                guard !line.isEmpty else { return false }
                if line.contains("MallocStackLogging") { return false }
                if line.hasPrefix("Reading additional input from stdin") { return false }
                return true
            }
            .joined(separator: "\n")
    }

    /// Resolve shebang: if executable has `#!/usr/bin/env <interp>`, find the interpreter
    /// and return (interpreter_path, [script_path] + args). Otherwise return original.
    private static func resolveShebang(command: String, args: [String]) -> (exec: String, args: [String]) {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: command), options: .mappedIfSafe),
              let firstLine = String(data: data.prefix(256), encoding: .utf8),
              firstLine.hasPrefix("#!/usr/bin/env ") else {
            return (command, args)
        }

        let shebangLine = String(firstLine.prefix(while: { $0 != "\n" && $0 != "\r" }))
        let interpName = String(shebangLine.dropFirst("#!/usr/bin/env ".count))
            .split(separator: " ").first.map(String.init) ?? ""

        if let path = WeChatShellEnvironment.findExecutable(named: interpName, inPATH: WeChatShellEnvironment.buildPATH()) {
            print("[WeChat:CLI] resolved shebang: \(interpName) -> \(path)")
            return (path, [command] + args)
        }
        return (command, args)
    }

    // MARK: - ACP Agent

    private func callACPAgent(_ agent: AgentConfig, userID: String, message: String) async throws -> String {
        let clientKey = agent.name

        // Get or create ACP client
        if acpClients[clientKey] == nil {
            let variant: ACPProtocolVariant
            if agent.name == "codex" || (agent.args?.contains("app-server") == true) {
                variant = .codexApp
            } else {
                variant = .legacyACP
            }

            let client = ACPClient(
                executable: agent.command ?? agent.name,
                arguments: agent.args ?? [],
                variant: variant,
                workingDirectory: Self.effectiveWorkingDirectory(for: agent),
                environment: agent.env
            )
            let directoryAccess = try authorizedDirectoryStore.accessHandle(for: Self.effectiveWorkingDirectory(for: agent))
            do {
                try await client.start()
            } catch {
                directoryAccess?.stop()
                throw error
            }
            acpClients[clientKey] = client
            acpDirectoryAccess[clientKey] = directoryAccess
        }

        let client = acpClients[clientKey]!

        // Get or create session
        let session = await conversationStore.getOrCreateSession(userID: userID, agentName: agent.name)
        let sessionID: String
        if let existing = session.acpSessionID {
            sessionID = existing
        } else {
            sessionID = try await client.createSession()
            await conversationStore.updateSession(userID: userID, agentName: agent.name) { s in
                s.acpSessionID = sessionID
            }
        }

        let reply = try await client.sendPrompt(message: message, sessionID: sessionID)
        return reply
    }

    // MARK: - Cleanup

    func stopAllClients() {
        for (_, client) in acpClients {
            Task { await client.stop() }
        }
        acpClients.removeAll()
        for (_, directoryAccess) in acpDirectoryAccess {
            directoryAccess.stop()
        }
        acpDirectoryAccess.removeAll()
    }

    // MARK: - CLI Approval

    private struct CLIApprovalResult {
        let allowed: Bool
        let message: String
    }

    private func requestCLIApprovalIfNeeded(
        agent: AgentConfig,
        userID: String,
        message: String,
        command: String,
        arguments: [String],
        cwd: String,
        approvalNotifier: ((String) async -> Void)?
    ) async -> CLIApprovalResult? {
        let risk = assessCLIRisk(agent: agent, command: command, arguments: arguments, message: message)

        switch agent.effectiveApprovalPolicy {
        case .trusted:
            return nil
        case .never:
            guard risk == .low else {
                return CLIApprovalResult(
                    allowed: false,
                    message: "已拒绝执行：\(agent.name) 的授权策略为拒绝高风险，当前风险=\(risk.displayName)。"
                )
            }
            return nil
        case .macConfirm, .wechatConfirm:
            guard risk != .low else { return nil }
        }

        let request = approvalCoordinator.makeRequest(
            agentName: agent.name,
            userID: userID,
            message: message,
            command: command,
            arguments: arguments,
            cwd: cwd,
            risk: risk,
            allowsWechatApproval: agent.allowsWechatApproval(for: risk),
            timeoutSeconds: agent.effectiveApprovalTimeoutSeconds
        )

        let approvalTask = Task { @MainActor in
            await approvalCoordinator.requestApproval(request)
        }
        await approvalNotifier?(request.wechatPrompt)
        let approved = await approvalTask.value
        if approved {
            return nil
        }
        return CLIApprovalResult(
            allowed: false,
            message: "授权 \(request.id) 已拒绝或超时，任务未执行。"
        )
    }

    private func assessCLIRisk(
        agent: AgentConfig,
        command: String,
        arguments: [String],
        message: String
    ) -> WeChatApprovalRequest.Risk {
        let lowerMessage = message.lowercased()
        let riskyMessageHints = [
            "修改", "写", "删除", "移除", "安装", "运行", "执行", "提交", "重置",
            "edit", "write", "delete", "remove", "install", "run", "execute", "commit", "reset", "apply patch"
        ]
        if riskyMessageHints.contains(where: { lowerMessage.contains($0) }) {
            return .high
        }

        let executable = URL(fileURLWithPath: command).lastPathComponent.lowercased()
        let argText = arguments.joined(separator: " ").lowercased()
        let highRiskCommands = ["rm", "sudo", "curl", "wget", "chmod", "chown", "brew", "npm", "pnpm", "yarn", "pip", "gem"]
        if highRiskCommands.contains(executable) || highRiskCommands.contains(where: { argText.contains($0 + " ") }) {
            return .high
        }

        if executable == "codex" || command.hasSuffix("/codex") {
            if argText.contains("danger-full-access") || argText.contains("workspace-write") {
                return .high
            }
            return .low
        }

        if executable == "claude" || command.hasSuffix("/claude") {
            return .medium
        }

        return agent.type == .cli ? .medium : .low
    }

    // MARK: - CLI Output Parsing

    private func parseClaudeSessionID(from output: String) -> String? {
        for line in output.split(separator: "\n") {
            guard let data = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let sid = json["session_id"] as? String else { continue }
            return sid
        }
        return nil
    }

    private func parseClaudeOutput(from output: String) -> String {
        var textParts: [String] = []
        var resultText: String?

        for line in output.split(separator: "\n") {
            guard let data = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let type = json["type"] as? String else { continue }

            // Skip system events (hooks, init, etc.)
            guard type != "system" else { continue }

            switch type {
            case "assistant":
                // Claude stream-json assistant message
                if let msg = json["message"] as? [String: Any],
                   let content = msg["content"] as? [[String: Any]] {
                    for block in content {
                        if block["type"] as? String == "text", let text = block["text"] as? String {
                            textParts.append(text)
                        }
                    }
                }
            case "result":
                // Final result
                if let result = json["result"] as? String {
                    resultText = result
                } else if let content = json["result"] as? [[String: Any]] {
                    for block in content {
                        if block["type"] as? String == "text", let text = block["text"] as? String {
                            resultText = text
                        }
                    }
                }
            default:
                break
            }
        }

        // Prefer result text, then collected text parts
        if let resultText, !resultText.isEmpty { return resultText }
        let combined = textParts.joined().trimmingCharacters(in: .whitespacesAndNewlines)
        return combined
    }
}

private extension WeChatAgentRouter.AgentConfig {
    func updating(cwd: String?) -> Self {
        .init(
            name: name,
            type: type,
            command: command,
            args: args,
            cwd: cwd,
            env: env,
            model: model,
            systemPrompt: systemPrompt,
            aliases: aliases,
            endpoint: endpoint,
            apiKey: apiKey,
            headers: headers,
            maxHistory: maxHistory,
            approvalPolicy: approvalPolicy,
            approvalTimeoutSeconds: approvalTimeoutSeconds,
            allowWechatConfirmForLowRisk: allowWechatConfirmForLowRisk,
            allowWechatConfirmForHighRisk: allowWechatConfirmForHighRisk
        )
    }

    func updating(approvalPolicy: ApprovalPolicy) -> Self {
        .init(
            name: name,
            type: type,
            command: command,
            args: args,
            cwd: cwd,
            env: env,
            model: model,
            systemPrompt: systemPrompt,
            aliases: aliases,
            endpoint: endpoint,
            apiKey: apiKey,
            headers: headers,
            maxHistory: maxHistory,
            approvalPolicy: approvalPolicy,
            approvalTimeoutSeconds: approvalTimeoutSeconds,
            allowWechatConfirmForLowRisk: allowWechatConfirmForLowRisk,
            allowWechatConfirmForHighRisk: allowWechatConfirmForHighRisk
        )
    }

    func updating(allowWechatConfirmForHighRisk: Bool) -> Self {
        .init(
            name: name,
            type: type,
            command: command,
            args: args,
            cwd: cwd,
            env: env,
            model: model,
            systemPrompt: systemPrompt,
            aliases: aliases,
            endpoint: endpoint,
            apiKey: apiKey,
            headers: headers,
            maxHistory: maxHistory,
            approvalPolicy: approvalPolicy,
            approvalTimeoutSeconds: approvalTimeoutSeconds,
            allowWechatConfirmForLowRisk: allowWechatConfirmForLowRisk,
            allowWechatConfirmForHighRisk: allowWechatConfirmForHighRisk
        )
    }
}

private extension WeChatAgentRouter {
    nonisolated static func effectiveWorkingDirectory(for agent: AgentConfig) -> String {
        WeChatWorkingDirectoryPolicy.effectiveDirectory(for: agent.cwd)
    }
}
