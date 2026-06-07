import Foundation

final class ClaudeTranscriptMonitor {
    private let projectsDirectory: URL
    private let gracePeriod: TimeInterval
    private let pollInterval: TimeInterval
    private let onPendingApproval: (AgentEvent) -> Void
    private let hookManagedSessionIds: () -> Set<String>
    private let maxTailBytes = 128 * 1024
    private let recentFileInterval: TimeInterval = 6 * 60 * 60

    private var timer: Timer?
    private var reportedToolUses: Set<String> = []

    init(
        projectsDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects", isDirectory: true),
        gracePeriod: TimeInterval = 5,
        pollInterval: TimeInterval = 3,
        hookManagedSessionIds: @escaping () -> Set<String> = { [] },
        onPendingApproval: @escaping (AgentEvent) -> Void
    ) {
        self.projectsDirectory = projectsDirectory
        self.gracePeriod = gracePeriod
        self.pollInterval = pollInterval
        self.hookManagedSessionIds = hookManagedSessionIds
        self.onPendingApproval = onPendingApproval
    }

    func start() {
        guard timer == nil else { return }
        poll()
        timer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            self?.poll()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        reportedToolUses.removeAll()
    }

    func poll(now: Date = Date()) {
        let managedIds = hookManagedSessionIds()
        for transcriptURL in recentTranscriptURLs(now: now) {
            guard let tail = readTail(from: transcriptURL),
                  let event = Self.pendingApprovalEvent(from: tail, now: now, gracePeriod: gracePeriod)
            else { continue }

            // When hooks are active for this session, skip false task-completion
            // signals from transcript (hooks provide authoritative Stop events).
            if event.eventType == .taskCompleted,
               let sessionId = event.sessionId,
               managedIds.contains(sessionId) {
                continue
            }

            let key = Self.reportKey(for: event)
            guard !reportedToolUses.contains(key) else { continue }
            reportedToolUses.insert(key)
            onPendingApproval(event)
        }
    }

    static func pendingApprovalEvent(
        from transcript: String,
        now: Date = Date(),
        gracePeriod: TimeInterval = 5
    ) -> AgentEvent? {
        let lines = transcript.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        guard !lines.isEmpty else { return nil }

        var latestSessionId: String?
        var latestCwd: String?

        for line in lines {
            guard let object = decodeJSONObject(from: line) else { continue }
            latestSessionId = stringValue(object["sessionId"]) ?? latestSessionId
            latestCwd = stringValue(object["cwd"]) ?? latestCwd
        }

        guard let latestObject = lines.reversed()
            .compactMap({ decodeJSONObject(from: $0) })
            .first(where: isActionableTranscriptObject)
        else { return nil }

        guard stringValue(latestObject["type"]) == "assistant" else { return nil }

        let timestamp = parseTimestamp(from: latestObject) ?? now
        guard now.timeIntervalSince(timestamp) >= gracePeriod else { return nil }

        let sessionId = stringValue(latestObject["sessionId"]) ?? latestSessionId
        let cwd = stringValue(latestObject["cwd"]) ?? latestCwd

        let latestMessageId = stringValue(latestObject["uuid"])
            ?? stringValue((latestObject["message"] as? [String: Any])?["id"])
            ?? "\(Int(timestamp.timeIntervalSince1970))"

        if messageContent(from: latestObject).contains(where: { stringValue($0["type"]) == "tool_use" }) {
            return nil
        }

        if let text = assistantText(from: latestObject) {
            if isWaitingForUserChoice(text) {
                return AgentEvent(
                    id: "claude-transcript-choice-\(sessionId ?? "unknown")-\(latestMessageId)",
                    source: .claudeCode,
                    eventType: .waitingUserInput,
                    severity: .warning,
                    projectName: cwd.flatMap { projectName(from: $0) },
                    cwd: cwd,
                    sessionId: sessionId,
                    taskTitle: "Claude Code waiting for choice",
                    message: "Claude Code 等待你选择处理方式",
                    rawSnippet: textSnippet(from: text),
                    createdAt: timestamp,
                    detectedAt: now,
                    requiresUserAction: true,
                    canResolveOnMac: true,
                    canNotifyPhone: true
                )
            }

            return AgentEvent(
                id: "claude-transcript-complete-\(sessionId ?? "unknown")-\(latestMessageId)",
                source: .claudeCode,
                eventType: .taskCompleted,
                severity: .info,
                projectName: cwd.flatMap { projectName(from: $0) },
                cwd: cwd,
                sessionId: sessionId,
                taskTitle: "Claude Code response complete",
                message: "Claude Code 回复已完成",
                rawSnippet: textSnippet(from: text),
                createdAt: timestamp,
                detectedAt: now,
                requiresUserAction: false,
                canResolveOnMac: true,
                canNotifyPhone: false,
                canNotifyUser: false
            )
        }

        return nil
    }

    private func recentTranscriptURLs(now: Date) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: projectsDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        let cutoff = now.addingTimeInterval(-recentFileInterval)
        var candidates: [(url: URL, modifiedAt: Date)] = []

        for case let url as URL in enumerator where url.pathExtension == "jsonl" {
            guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey]),
                  values.isRegularFile == true,
                  let modifiedAt = values.contentModificationDate,
                  modifiedAt >= cutoff
            else { continue }
            candidates.append((url, modifiedAt))
        }

        return candidates
            .sorted { $0.modifiedAt > $1.modifiedAt }
            .prefix(20)
            .map(\.url)
    }

    private func readTail(from url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        let size = (try? handle.seekToEnd()) ?? 0
        let offset = size > UInt64(maxTailBytes) ? size - UInt64(maxTailBytes) : 0
        try? handle.seek(toOffset: offset)
        let data = handle.readDataToEndOfFile()
        guard let text = String(data: data, encoding: .utf8) else { return nil }

        if offset == 0 {
            return text
        }
        return text.split(separator: "\n", omittingEmptySubsequences: false).dropFirst().joined(separator: "\n")
    }

    private static func reportKey(for event: AgentEvent) -> String {
        "\(event.sessionId ?? "unknown")|\(event.id)"
    }

    private static func decodeJSONObject(from line: String) -> [String: Any]? {
        guard let data = line.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return object
    }

    private static func messageContent(from object: [String: Any]) -> [[String: Any]] {
        guard let message = object["message"] as? [String: Any] else { return [] }
        if let content = message["content"] as? [[String: Any]] {
            return content
        }
        if let content = message["content"] as? [Any] {
            return content.compactMap { $0 as? [String: Any] }
        }
        return []
    }

    private static func assistantText(from object: [String: Any]) -> String? {
        let textParts = messageContent(from: object).compactMap { content -> String? in
            guard stringValue(content["type"]) == "text" else { return nil }
            return stringValue(content["text"])
        }
        guard !textParts.isEmpty else { return nil }
        return textParts.joined(separator: "\n")
    }

    private static func isWaitingForUserChoice(_ text: String) -> Bool {
        let lowercased = text.lowercased()

        // Binary yes/no questions: no numbered list required
        let binaryPrompts = [
            "是否继续", "要继续吗", "是否要", "确认吗", "是否",
            "(y/n)", "y/n", "yes or no",
        ]
        if binaryPrompts.contains(where: { lowercased.contains($0) }) {
            return true
        }

        // Multi-choice phrases require at least two numbered/lettered options
        let choicePhrases = [
            "请选择", "你想用哪种", "你希望", "您想", "哪种方式",
            "如何处理", "选择哪种", "哪个方案", "选择一种", "选择方式",
            "do you want", "which option", "please choose", "choose an option",
            "how would you like", "would you like", "which approach",
            "which would you prefer", "let me know which", "what would you like",
            "pick one", "select one",
        ]
        let hasChoicePhrase = choicePhrases.contains { lowercased.contains($0) }
        return hasChoicePhrase && hasNumberedOptions(text)
    }

    private static func hasNumberedOptions(_ text: String) -> Bool {
        let lines = text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        let optionLines = lines.filter { line in
            line.range(of: #"^(?:[^\dA-Za-z]*)?\d+[.)、]\s+.+"#, options: .regularExpression) != nil
        }
        return optionLines.count >= 2
    }

    private static func textSnippet(from text: String) -> String {
        let collapsed = text
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        return String(collapsed.prefix(500))
    }

    nonisolated private static func isActionableTranscriptObject(_ object: [String: Any]) -> Bool {
        switch stringValue(object["type"]) {
        case "assistant", "user":
            return true
        default:
            return false
        }
    }

    nonisolated private static func stringValue(_ value: Any?) -> String? {
        value as? String
    }

    private static func parseTimestamp(from object: [String: Any]) -> Date? {
        guard let timestamp = stringValue(object["timestamp"]) else { return nil }
        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractionalFormatter.date(from: timestamp) {
            return date
        }
        return ISO8601DateFormatter().date(from: timestamp)
    }

    private static func projectName(from path: String) -> String {
        path.split(separator: "/").last.map(String.init) ?? path
    }
}
