import Foundation
import Testing
@testable import DevBar

struct ClaudeTranscriptMonitorTests {
    private let dateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    @Test
    func pendingToolUseCreatesApprovalEventAfterGracePeriod() throws {
        let transcript = [
            #"{"type":"last-prompt","lastPrompt":"更新菜单配置","sessionId":"session-1"}"#,
            #"{"type":"permission-mode","permissionMode":"acceptEdits","sessionId":"session-1"}"#,
            #"{"type":"assistant","timestamp":"2026-06-04T05:10:30.000Z","cwd":"/Users/xjpz/Documents/workspace/ai/scala/lemonbus-x","sessionId":"session-1","message":{"content":[{"type":"tool_use","id":"tool-1","name":"Bash","input":{"command":"cat > app/models/SystemMenu.scala"}}]}}"#,
        ].joined(separator: "\n")

        let event = try #require(ClaudeTranscriptMonitor.pendingApprovalEvent(
            from: transcript,
            now: dateFormatter.date(from: "2026-06-04T05:10:36.000Z")!,
            gracePeriod: 5
        ))

        #expect(event.sessionId == "session-1")
        #expect(event.source == .claudeCode)
        #expect(event.eventType == .waitingUserInput)
        #expect(event.severity == .warning)
        #expect(event.cwd == "/Users/xjpz/Documents/workspace/ai/scala/lemonbus-x")
        #expect(event.taskTitle == "Bash confirmation")
        #expect(event.rawSnippet == "cat > app/models/SystemMenu.scala")
        #expect(event.requiresUserAction)
        #expect(event.canNotifyPhone)
    }

    @Test
    func completedToolUseDoesNotCreateApprovalEvent() throws {
        let transcript = [
            #"{"type":"assistant","timestamp":"2026-06-04T05:10:30.000Z","cwd":"/tmp/project","sessionId":"session-1","message":{"content":[{"type":"tool_use","id":"tool-1","name":"Bash","input":{"command":"ls"}}]}}"#,
            #"{"type":"user","timestamp":"2026-06-04T05:10:31.000Z","sessionId":"session-1","message":{"content":[{"type":"tool_result","tool_use_id":"tool-1","content":"ok"}]}}"#,
        ].joined(separator: "\n")

        let event = ClaudeTranscriptMonitor.pendingApprovalEvent(
            from: transcript,
            now: dateFormatter.date(from: "2026-06-04T05:10:40.000Z")!,
            gracePeriod: 5
        )

        #expect(event == nil)
    }

    @Test
    func olderUnfinishedToolUseCreatesCompletionAfterConversationContinues() throws {
        let transcript = [
            #"{"type":"assistant","timestamp":"2026-06-04T05:10:30.000Z","cwd":"/tmp/project","sessionId":"session-1","message":{"content":[{"type":"tool_use","id":"tool-1","name":"Bash","input":{"command":"sleep 30"}}]}}"#,
            #"{"type":"assistant","timestamp":"2026-06-04T05:10:50.000Z","cwd":"/tmp/project","sessionId":"session-1","message":{"content":[{"type":"text","text":"后续已经继续执行"}]}}"#,
        ].joined(separator: "\n")

        let event = try #require(ClaudeTranscriptMonitor.pendingApprovalEvent(
            from: transcript,
            now: dateFormatter.date(from: "2026-06-04T05:11:00.000Z")!,
            gracePeriod: 5
        ))

        #expect(event.eventType == .taskCompleted)
        #expect(event.requiresUserAction == false)
        #expect(event.canNotifyUser == false)
    }

    @Test
    func assistantChoicePromptCreatesWaitingInputEvent() throws {
        let transcript = [
            #"{"type":"user","timestamp":"2026-06-04T05:10:00.000Z","cwd":"/tmp/project","sessionId":"session-1","message":{"content":"提交代码"}}"#,
            #"{"type":"assistant","timestamp":"2026-06-04T05:10:30.000Z","cwd":"/tmp/project","sessionId":"session-1","uuid":"assistant-choice-1","message":{"content":[{"type":"text","text":"请选择处理方式：\n\n1. 提交所有更改 → git add . && git commit -m \"描述\" && git push\n2. 只提交代码文件（排除 ios/build/）→ git add . :!ios/build/ && git commit -m \"描述\" && git push\n3. 丢弃本地更改 → git checkout -- <文件> && git push\n\n你想用哪种方式？"}]}}"#,
        ].joined(separator: "\n")

        let event = try #require(ClaudeTranscriptMonitor.pendingApprovalEvent(
            from: transcript,
            now: dateFormatter.date(from: "2026-06-04T05:10:36.000Z")!,
            gracePeriod: 5
        ))

        #expect(event.id == "claude-transcript-choice-session-1-assistant-choice-1")
        #expect(event.eventType == .waitingUserInput)
        #expect(event.severity == .warning)
        #expect(event.message == "Claude Code 等待你选择处理方式")
        #expect(event.rawSnippet?.contains("请选择处理方式") == true)
        #expect(event.requiresUserAction)
        #expect(event.canNotifyPhone)
    }

    @Test
    func terminalProceedPromptWithCursorCreatesWaitingInputEvent() throws {
        let transcript = [
            #"{"type":"user","timestamp":"2026-06-04T05:10:00.000Z","cwd":"/Users/xjpz/Documents/workspace/ai/xcode/1panel","sessionId":"session-1","message":{"content":"提交并推送"}}"#,
            #"{"type":"assistant","timestamp":"2026-06-04T05:10:30.000Z","cwd":"/Users/xjpz/Documents/workspace/ai/xcode/1panel","sessionId":"session-1","uuid":"assistant-choice-2","message":{"content":[{"type":"text","text":"Do you want to proceed?\n ❯ 1. Yes\n  2. Yes, and don't ask again for git add, git commit, and git push commands in\n     /Users/xjpz/Documents/workspace/ai/xcode/1panel\n   3. No"}]}}"#,
        ].joined(separator: "\n")

        let event = try #require(ClaudeTranscriptMonitor.pendingApprovalEvent(
            from: transcript,
            now: dateFormatter.date(from: "2026-06-04T05:10:36.000Z")!,
            gracePeriod: 5
        ))

        #expect(event.eventType == .waitingUserInput)
        #expect(event.projectName == "1panel")
        #expect(event.rawSnippet?.contains("Do you want to proceed?") == true)
        #expect(event.rawSnippet?.contains("don't ask again") == true)
        #expect(event.requiresUserAction)
        #expect(event.canNotifyPhone)
    }

    @Test
    func recentToolUseWaitsForGracePeriod() throws {
        let transcript = #"{"type":"assistant","timestamp":"2026-06-04T05:10:30.000Z","cwd":"/tmp/project","sessionId":"session-1","message":{"content":[{"type":"tool_use","id":"tool-1","name":"Edit","input":{"file_path":"README.md"}}]}}"#

        let event = ClaudeTranscriptMonitor.pendingApprovalEvent(
            from: transcript,
            now: dateFormatter.date(from: "2026-06-04T05:10:32.000Z")!,
            gracePeriod: 5
        )

        #expect(event == nil)
    }
}
