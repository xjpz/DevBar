import Foundation

struct AgentWatcherNotificationSummary: Equatable {
    let taskCount: Int
    let approvalCount: Int
    let stalledCount: Int
}

enum AgentWatcherNotificationLimitResult: Equatable {
    case allow
    case suppress
    case summary(AgentWatcherNotificationSummary)
}

struct AgentWatcherNotificationLimiter {
    private struct Record {
        let sessionId: String
        let eventType: AgentEventType
        let sentAt: Date
    }

    private var records: [Record] = []
    private var lastSummaryAt: Date?

    mutating func evaluate(
        sessionId: String,
        eventType: AgentEventType,
        now: Date = Date(),
        summary: AgentWatcherNotificationSummary
    ) -> AgentWatcherNotificationLimitResult {
        records.removeAll { now.timeIntervalSince($0.sentAt) >= 3600 }

        let matchingRecords = records.filter {
            $0.sessionId == sessionId && $0.eventType == eventType
        }
        if matchingRecords.contains(where: { now.timeIntervalSince($0.sentAt) < 120 }) {
            return .suppress
        }

        let globalMinuteCount = records.filter { now.timeIntervalSince($0.sentAt) < 60 }.count
        let globalTenMinuteCount = records.filter { now.timeIntervalSince($0.sentAt) < 600 }.count
        let sessionTenMinuteCount = matchingRecords.filter { now.timeIntervalSince($0.sentAt) < 600 }.count
        let sessionHourCount = matchingRecords.count

        records.append(Record(sessionId: sessionId, eventType: eventType, sentAt: now))

        let shouldSummarize = globalMinuteCount >= 2
            || globalTenMinuteCount >= 6
            || sessionTenMinuteCount >= 2
            || sessionHourCount >= 5

        guard shouldSummarize else { return .allow }
        guard lastSummaryAt.map({ now.timeIntervalSince($0) >= 120 }) ?? true else {
            return .suppress
        }

        lastSummaryAt = now
        return .summary(summary)
    }
}
