// ACPClient.swift
// DevBar

import Foundation

// MARK: - Protocol Variant

enum ACPProtocolVariant: Sendable {
    case legacyACP     // Claude Code (claude-agent-acp)
    case codexApp      // Codex (codex app-server)
}

// MARK: - Errors

enum ACPError: LocalizedError, Sendable {
    case processLaunchFailed(String)
    case handshakeTimeout
    case sessionError(String)
    case responseTimeout
    case processTerminated(Int32)
    case invalidResponse(String)
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .processLaunchFailed(let msg): return "ACP launch failed: \(msg)"
        case .handshakeTimeout: return "ACP handshake timed out"
        case .sessionError(let msg): return "ACP session error: \(msg)"
        case .responseTimeout: return "ACP response timed out"
        case .processTerminated(let code): return "ACP process exited (\(code))"
        case .invalidResponse(let msg): return "ACP invalid response: \(msg)"
        case .emptyResponse: return "ACP agent returned empty response"
        }
    }
}

// MARK: - JSON-RPC Types

private struct RPCRequest {
    let jsonrpc = "2.0"
    let id: Int
    let method: String
    let params: AnyJSON?

    nonisolated func encode() throws -> Data {
        var obj: [String: Any] = ["jsonrpc": jsonrpc, "id": id, "method": method]
        if let params { obj["params"] = params.value }
        return try JSONSerialization.data(withJSONObject: obj)
    }
}

private struct RPCNotification {
    let jsonrpc = "2.0"
    let method: String
    let params: AnyJSON?

    nonisolated func encode() throws -> Data {
        var obj: [String: Any] = ["jsonrpc": jsonrpc, "method": method]
        if let params { obj["params"] = params.value }
        return try JSONSerialization.data(withJSONObject: obj)
    }
}

/// Type-erased JSON wrapper for dynamic request/response handling.
struct AnyJSON: @unchecked Sendable {
    nonisolated(unsafe) let value: Any

    nonisolated init(_ value: Any) { self.value = value }

    nonisolated static func dictionary(_ dict: [String: Any]) -> AnyJSON {
        .init(dict)
    }

    nonisolated static func array(_ arr: [Any]) -> AnyJSON {
        .init(arr)
    }

    nonisolated static func string(_ str: String) -> AnyJSON {
        .init(str)
    }

    nonisolated static func int(_ n: Int) -> AnyJSON {
        .init(n)
    }

    /// Extract a string from the JSON value.
    nonisolated var stringValue: String? { value as? String }

    /// Extract a dictionary from the JSON value.
    nonisolated var dictValue: [String: Any]? { value as? [String: Any] }

    /// Extract an array from the JSON value.
    nonisolated var arrayValue: [Any]? { value as? [Any] }
}

// MARK: - ACP Client

actor ACPClient {
    private let executable: String
    private let arguments: [String]
    let variant: ACPProtocolVariant
    private let workingDirectory: String?
    private let environment: [String: String]?

    private var process: Process?
    private var stdinPipe: Pipe?

    private var nextRequestID = 1
    private var pendingRequests: [Int: CheckedContinuation<AnyJSON?, Error>] = [:]

    // Notification channels: sessionID -> AsyncStream
    private var notifyChannels: [String: AsyncStream<AnyJSON>.Continuation] = [:]
    // Codex turn channels: threadID -> AsyncStream
    private var turnChannels: [String: AsyncStream<AnyJSON>.Continuation] = [:]

    private var isInitialized = false

    private let readQueue = DispatchQueue(label: "devbar.acp.read")
    private var readBuffer = Data()

    // MARK: - Init

    init(executable: String, arguments: [String] = [], variant: ACPProtocolVariant,
         workingDirectory: String? = nil, environment: [String: String]? = nil) {
        self.executable = executable
        self.arguments = arguments
        self.variant = variant
        self.workingDirectory = workingDirectory
        self.environment = environment
    }

    // MARK: - Lifecycle

    func start() async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        if let cwd = workingDirectory {
            process.currentDirectoryURL = URL(fileURLWithPath: cwd)
        }

        var env = ProcessInfo.processInfo.environment
        if let extra = environment {
            env.merge(extra) { _, new in new }
        }
        env["PATH"] = WeChatShellEnvironment.buildPATH(environment: env)
        process.environment = env

        // Capture stderr for debugging
        let stderrPipe = Pipe()
        process.standardError = stderrPipe

        print("[ACP] starting: \(executable) \(arguments.joined(separator: " "))")

        let stdin = Pipe()
        let stdout = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        // stderr already set to stderrPipe above

        process.terminationHandler = { [weak self = self] proc in
            Task { [weak self] in
                await self?.handleTermination(status: proc.terminationStatus)
            }
        }

        try process.run()
        self.process = process
        self.stdinPipe = stdin

        startReadingStdout(stdout.fileHandleForReading)

        // Handshake with timeout
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask { try await self.performHandshake() }
            group.addTask {
                try await Task.sleep(nanoseconds: 30_000_000_000)
                throw ACPError.handshakeTimeout
            }
            try await group.next()!
            group.cancelAll()
        }

        isInitialized = true
    }

    func stop() {
        if let pipe = stdinPipe {
            try? pipe.fileHandleForWriting.close()
        }
        process?.terminate()
        process = nil
        stdinPipe = nil
        isInitialized = false
    }

    deinit {
        process?.terminate()
    }

    // MARK: - Session Management

    func createSession() async throws -> String {
        let params: AnyJSON
        switch variant {
        case .codexApp:
            let dict: [String: Any] = [
                "approvalPolicy": "never",
                "cwd": workingDirectory ?? FileManager.default.currentDirectoryPath,
                "sandbox": "read-only",
            ]
            params = .dictionary(dict)
            let result = try await sendRequest(method: "thread/start", params: params)
            if let dict = result?.dictValue,
               let thread = dict["thread"] as? [String: Any],
               let id = thread["id"] as? String {
                return id
            }
        case .legacyACP:
            params = .dictionary([
                "cwd": workingDirectory ?? FileManager.default.currentDirectoryPath,
                "mcpServers": [],
            ])
            let result = try await sendRequest(method: "session/new", params: params)
            if let dict = result?.dictValue,
               let id = dict["sessionId"] as? String {
                return id
            }
        }
        throw ACPError.sessionError("Failed to parse session/thread ID from response")
    }

    // MARK: - Chat

    func sendPrompt(message: String, sessionID: String) async throws -> String {
        guard isInitialized else {
            throw ACPError.sessionError("Client not initialized")
        }

        switch variant {
        case .codexApp:
            return try await codexPrompt(message: message, threadID: sessionID)
        case .legacyACP:
            return try await legacyPrompt(message: message, sessionID: sessionID)
        }
    }

    // MARK: - Legacy ACP Prompt (Claude)

    private func legacyPrompt(message: String, sessionID: String) async throws -> String {
        // Register notification channel
        let (stream, cont) = AsyncStream<AnyJSON>.makeStream()
        notifyChannels[sessionID] = cont
        defer { notifyChannels.removeValue(forKey: sessionID) }

        let params = AnyJSON.dictionary([
            "sessionId": sessionID,
            "prompt": [["type": "text", "text": message]],
        ])

        // Send prompt asynchronously
        let (streamResult, streamContinuation) = AsyncStream<Result<AnyJSON?, Error>>.makeStream()
        Task {
            let result: Result<AnyJSON?, Error>
            do {
                let value = try await sendRequest(method: "session/prompt", params: params)
                result = .success(value)
            } catch {
                result = .failure(error)
            }
            streamContinuation.yield(result)
            streamContinuation.finish()
        }

        // Collect text chunks from notifications
        var textParts: [String] = []

        var promptDone = false
        var promptResult: Result<AnyJSON?, Error>?

        for await awaitable in mergePromptsAndNotifications(
            promptStream: streamResult,
            notifyStream: stream
        ) {
            switch awaitable {
            case .promptResult(let result):
                promptDone = true
                promptResult = result
            case .notification(let update):
                if let text = extractChunkText(update) {
                    textParts.append(text)
                }
            }

            if promptDone { break }
        }

        if let result = promptResult {
            let reply = try result.get()
            var combined = textParts.joined().trimmingCharacters(in: .whitespacesAndNewlines)
            if combined.isEmpty, let text = extractPromptResultText(reply) {
                combined = text
            }
            if combined.isEmpty { throw ACPError.emptyResponse }
            return combined
        }
        throw ACPError.responseTimeout
    }

    // MARK: - Codex App-Server Prompt

    private func codexPrompt(message: String, threadID: String) async throws -> String {
        let (turnStream, turnCont) = AsyncStream<AnyJSON>.makeStream()
        turnChannels[threadID] = turnCont
        defer { turnChannels.removeValue(forKey: threadID) }

        let params: [String: Any] = [
            "threadId": threadID,
            "approvalPolicy": "never",
            "input": [["type": "text", "text": message]],
            "sandboxPolicy": ["type": "readOnly"],
            "cwd": workingDirectory ?? FileManager.default.currentDirectoryPath,
        ]

        _ = try await sendRequest(method: "turn/start", params: .dictionary(params))

        // Collect deltas until completed
        var textParts: [String] = []

        for await event in turnStream {
            if let kind = event.dictValue?["kind"] as? String, kind == "completed" {
                break
            }
            if let delta = event.dictValue?["delta"] as? String, !delta.isEmpty {
                textParts.append(delta)
            }
            if let text = event.dictValue?["text"] as? String, !text.isEmpty {
                textParts.append(text)
            }
        }

        let combined = textParts.joined().trimmingCharacters(in: .whitespacesAndNewlines)
        if combined.isEmpty { throw ACPError.emptyResponse }
        return combined
    }

    // MARK: - JSON-RPC Communication

    private func performHandshake() async throws {
        let params: AnyJSON
        switch variant {
        case .codexApp:
            params = .dictionary(["clientInfo": ["name": "DevBar", "version": "1.0"]])
            _ = try await sendRequest(method: "initialize", params: params)
            // codex expects initialized notification
            try sendNotification(method: "initialized", params: nil)
        case .legacyACP:
            params = .dictionary([
                "protocolVersion": 1,
                "clientCapabilities": ["fs": ["readTextFile": true, "writeTextFile": true]],
            ])
            _ = try await sendRequest(method: "initialize", params: params)
        }
    }

    private func sendRequest(method: String, params: AnyJSON?) async throws -> AnyJSON? {
        let id = nextRequestID
        nextRequestID += 1

        let request = RPCRequest(id: id, method: method, params: params)
        let data = try request.encode()
        try writeToStdin(data)

        return try await withCheckedThrowingContinuation { continuation in
            pendingRequests[id] = continuation
        }
    }

    private func sendNotification(method: String, params: AnyJSON?) throws {
        let notification = RPCNotification(method: method, params: params)
        let data = try notification.encode()
        try writeToStdin(data)
    }

    private func writeToStdin(_ data: Data) throws {
        guard let pipe = stdinPipe else {
            throw ACPError.processLaunchFailed("stdin pipe not available")
        }
        var line = data
        line.append(0x0A) // newline delimiter
        try pipe.fileHandleForWriting.write(contentsOf: line)
    }

    // MARK: - Stdout Reading

    private func startReadingStdout(_ handle: FileHandle) {
        let fd = handle.fileDescriptor
        readQueue.async { [weak self] in
            let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 4096)
            defer { buffer.deallocate() }
            while true {
                let bytesRead = read(fd, buffer, 4096)
                if bytesRead <= 0 { break }
                let chunk = Data(bytes: buffer, count: bytesRead)
                Task { [weak self] in
                    await self?.processReadData(chunk)
                }
            }
        }
    }

    private func processReadData(_ data: Data) {
        readBuffer.append(data)

        while let newlineIdx = readBuffer.firstIndex(of: 0x0A) {
            let lineData = readBuffer[..<newlineIdx]
            readBuffer = readBuffer[(newlineIdx + 1)...]
            guard !lineData.isEmpty else { continue }
            handleLine(lineData)
        }
    }

    private func handleLine(_ data: Data) {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

        // Response to a pending request
        if let id = obj["id"] as? Int, obj["method"] == nil {
            let error = (obj["error"] as? [String: Any]).map { AnyJSON.dictionary($0) }
            let result = obj["result"].map { AnyJSON($0) }

            if let continuation = pendingRequests.removeValue(forKey: id) {
                if let error {
                    let msg = error.dictValue?["message"] as? String ?? "unknown error"
                    continuation.resume(throwing: ACPError.sessionError(msg))
                } else {
                    continuation.resume(returning: result)
                }
            }
            return
        }

        // Notification or request from agent
        guard let method = obj["method"] as? String else { return }
        let params = obj["params"].map { AnyJSON($0) }

        switch method {
        case "session/update":
            handleSessionUpdate(params)
        case "session/request_permission":
            handlePermissionRequest(obj)
        // Codex events
        case "codex/event/agent_message_delta":
            handleCodexDelta(params)
        case "item/agentMessage/delta":
            handleCodexItemDelta(params)
        case "item/started":
            handleCodexItemStarted(params)
        case "turn/started", "turn/completed":
            handleCodexTurnEvent(method, params: params)
        case "turn/approval/request":
            handlePermissionRequest(obj)
        default:
            break
        }
    }

    // MARK: - Notification Handlers

    private func handleSessionUpdate(_ params: AnyJSON?) {
        guard let dict = params?.dictValue,
              let sessionID = dict["sessionId"] as? String,
              let update = dict["update"] as? [String: Any] else { return }

        let cont = notifyChannels[sessionID]
        cont?.yield(AnyJSON(update))
    }

    private func handlePermissionRequest(_ rawObj: [String: Any]) {
        guard let id = rawObj["id"],
              let params = rawObj["params"] as? [String: Any],
              let options = params["options"] as? [[String: Any]] else { return }

        let preferred = options.first { $0["kind"] as? String == "deny" }
            ?? options.first { ($0["optionId"] as? String)?.localizedCaseInsensitiveContains("deny") == true }
            ?? options.first
        let optionID = preferred?["optionId"] as? String ?? "deny"

        let response: [String: Any] = [
            "jsonrpc": "2.0",
            "id": id,
            "result": ["outcome": ["outcome": "selected", "optionId": optionID]],
        ]

        guard let data = try? JSONSerialization.data(withJSONObject: response) else { return }
        try? writeToStdin(data)
    }

    // MARK: - Codex Event Handlers

    private func handleCodexDelta(_ params: AnyJSON?) {
        guard let dict = params?.dictValue,
              let msg = dict["msg"] as? [String: Any],
              let delta = msg["delta"] as? String, !delta.isEmpty else { return }

        // Dispatch to any active turn channel
        for (_, cont) in turnChannels {
            cont.yield(AnyJSON.dictionary(["delta": delta]))
        }
    }

    private func handleCodexItemDelta(_ params: AnyJSON?) {
        guard let dict = params?.dictValue,
              let delta = dict["delta"] as? String, !delta.isEmpty else { return }
        let threadID = dict["threadId"] as? String ?? ""

        if let cont = turnChannels[threadID] {
            cont.yield(AnyJSON.dictionary(["delta": delta]))
        } else {
            for (_, cont) in turnChannels {
                cont.yield(AnyJSON.dictionary(["delta": delta]))
            }
        }
    }

    private func handleCodexItemStarted(_ params: AnyJSON?) {
        guard let dict = params?.dictValue,
              let item = dict["item"] as? [String: Any],
              item["type"] as? String == "agentMessage",
              let content = item["content"] as? [[String: Any]] else { return }

        let threadID = dict["threadId"] as? String ?? ""
        for c in content {
            if c["type"] as? String == "text", let text = c["text"] as? String, !text.isEmpty {
                dispatchToTurn(threadID: threadID, event: AnyJSON.dictionary(["text": text]))
            }
        }
    }

    private func handleCodexTurnEvent(_ method: String, params: AnyJSON?) {
        guard let dict = params?.dictValue else { return }
        let threadID = dict["threadId"] as? String ?? ""

        if method == "turn/completed" {
            dispatchToTurn(threadID: threadID, event: AnyJSON.dictionary(["kind": "completed"]))
        }
    }

    private func dispatchToTurn(threadID: String, event: AnyJSON) {
        if let cont = turnChannels[threadID] {
            cont.yield(event)
        } else {
            for (_, cont) in turnChannels {
                cont.yield(event)
            }
        }
    }

    // MARK: - Helpers

    private func extractChunkText(_ update: AnyJSON) -> String? {
        guard let dict = update.dictValue else { return nil }
        if dict["sessionUpdate"] as? String == "agent_message_chunk" {
            return dict["text"] as? String
        }
        return nil
    }

    private func extractPromptResultText(_ result: AnyJSON?) -> String? {
        guard let dict = result?.dictValue,
              let content = dict["content"] as? [[String: Any]] else { return nil }
        return content.compactMap { $0["type"] as? String == "text" ? $0["text"] as? String : nil }
            .joined()
    }

    private enum PromptOrNotification {
        case promptResult(Result<AnyJSON?, Error>)
        case notification(AnyJSON)
    }

    private func mergePromptsAndNotifications(
        promptStream: AsyncStream<Result<AnyJSON?, Error>>,
        notifyStream: AsyncStream<AnyJSON>
    ) -> AsyncStream<PromptOrNotification> {
        AsyncStream { continuation in
            let promptTask = Task {
                for await result in promptStream {
                    continuation.yield(.promptResult(result))
                }
            }
            let notifyTask = Task {
                for await update in notifyStream {
                    continuation.yield(.notification(update))
                }
            }
            // Finish when prompt is done
            Task {
                await promptTask.value
                notifyTask.cancel()
                continuation.finish()
            }
        }
    }

    private func handleTermination(status: Int32) {
        // Read stderr for debugging
        if let proc = process,
           let stderrHandle = (proc.standardError as? Pipe)?.fileHandleForReading {
            let stderrData = stderrHandle.readDataToEndOfFile()
            if let stderr = String(data: stderrData, encoding: .utf8), !stderr.isEmpty {
                print("[ACP] stderr: \(stderr.prefix(300))")
            }
        }
        print("[ACP] process terminated with status \(status)")
        for (_, cont) in pendingRequests {
            cont.resume(throwing: ACPError.processTerminated(status))
        }
        pendingRequests.removeAll()
        for (_, cont) in notifyChannels { cont.finish() }
        notifyChannels.removeAll()
        for (_, cont) in turnChannels { cont.finish() }
        turnChannels.removeAll()
        isInitialized = false
    }

}
