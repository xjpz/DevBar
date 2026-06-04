import Foundation
import Testing
@testable import DevBar

struct AgentWatcherNotificationLimiterTests {
    @Test func firstNotificationIsAllowed() {
        var limiter = AgentWatcherNotificationLimiter()
        let result = limiter.evaluate(
            sessionId: "session-1",
            eventType: .approvalRequired,
            now: Date(),
            summary: .init(taskCount: 1, approvalCount: 1, stalledCount: 0)
        )

        #expect(result == .allow)
    }

    @Test func repeatedSessionEventIsSuppressedForTwoMinutes() {
        var limiter = AgentWatcherNotificationLimiter()
        let now = Date()
        let summary = AgentWatcherNotificationSummary(taskCount: 1, approvalCount: 1, stalledCount: 0)

        _ = limiter.evaluate(sessionId: "session-1", eventType: .approvalRequired, now: now, summary: summary)
        let result = limiter.evaluate(
            sessionId: "session-1",
            eventType: .approvalRequired,
            now: now.addingTimeInterval(119),
            summary: summary
        )

        #expect(result == .suppress)
    }

    @Test func thirdGlobalNotificationBecomesSummary() {
        var limiter = AgentWatcherNotificationLimiter()
        let now = Date()
        let summary = AgentWatcherNotificationSummary(taskCount: 3, approvalCount: 2, stalledCount: 1)

        _ = limiter.evaluate(sessionId: "session-1", eventType: .approvalRequired, now: now, summary: summary)
        _ = limiter.evaluate(sessionId: "session-2", eventType: .taskStalled, now: now.addingTimeInterval(10), summary: summary)
        let result = limiter.evaluate(
            sessionId: "session-3",
            eventType: .loginRequired,
            now: now.addingTimeInterval(20),
            summary: summary
        )

        #expect(result == .summary(summary))
    }

    @Test func summaryIsThrottledForTwoMinutes() {
        var limiter = AgentWatcherNotificationLimiter()
        let now = Date()
        let summary = AgentWatcherNotificationSummary(taskCount: 4, approvalCount: 2, stalledCount: 1)

        _ = limiter.evaluate(sessionId: "session-1", eventType: .approvalRequired, now: now, summary: summary)
        _ = limiter.evaluate(sessionId: "session-2", eventType: .taskStalled, now: now.addingTimeInterval(10), summary: summary)
        _ = limiter.evaluate(sessionId: "session-3", eventType: .loginRequired, now: now.addingTimeInterval(20), summary: summary)
        let result = limiter.evaluate(
            sessionId: "session-4",
            eventType: .taskFailed,
            now: now.addingTimeInterval(30),
            summary: summary
        )

        #expect(result == .suppress)
    }
}
