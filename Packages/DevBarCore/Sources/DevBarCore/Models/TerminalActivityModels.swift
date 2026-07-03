import Foundation

#if os(iOS) && canImport(ActivityKit)
import ActivityKit
import AppIntents

public enum TerminalActivityStatus: String, Codable, Hashable, Sendable {
    case connecting
    case connected
    case suspended
    case disconnected
    case failed

    public var title: String {
        switch self {
        case .connecting:
            return "Connecting"
        case .connected:
            return "Connected"
        case .suspended:
            return "Suspended"
        case .disconnected:
            return "Disconnected"
        case .failed:
            return "Failed"
        }
    }
}

public struct TerminalActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable, Sendable {
        public var status: TerminalActivityStatus
        public var statusText: String
        public var sessions: [TerminalActivitySessionSnapshot]
        public var selectedPage: Int
        public var updatedAt: Date

        public init(
            status: TerminalActivityStatus,
            statusText: String,
            sessions: [TerminalActivitySessionSnapshot] = [],
            selectedPage: Int = 0,
            updatedAt: Date = Date()
        ) {
            self.status = status
            self.statusText = statusText
            self.sessions = sessions
            self.selectedPage = selectedPage
            self.updatedAt = updatedAt
        }

        public var primarySession: TerminalActivitySessionSnapshot? {
            visibleSessions.first ?? sessions.first
        }

        public var activeSessionCount: Int {
            sessions.filter { $0.status != .disconnected }.count
        }

        public var pageSize: Int {
            2
        }

        public var pageCount: Int {
            max(1, (sessions.count + pageSize - 1) / pageSize)
        }

        public var clampedSelectedPage: Int {
            min(max(selectedPage, 0), pageCount - 1)
        }

        public var visibleSessions: [TerminalActivitySessionSnapshot] {
            guard !sessions.isEmpty else { return [] }
            let start = clampedSelectedPage * pageSize
            return Array(sessions.dropFirst(start).prefix(pageSize))
        }

        public var hasMultiplePages: Bool {
            pageCount > 1
        }

        public var pageIndicator: String {
            "\(clampedSelectedPage + 1)/\(pageCount)"
        }

        public func cyclingSessionGroup() -> Self {
            guard hasMultiplePages else { return self }
            var copy = self
            copy.selectedPage = (clampedSelectedPage + 1) % pageCount
            copy.updatedAt = Date()
            return copy
        }

        enum CodingKeys: String, CodingKey {
            case status
            case statusText
            case sessions
            case selectedPage
            case updatedAt
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            status = try container.decode(TerminalActivityStatus.self, forKey: .status)
            statusText = try container.decode(String.self, forKey: .statusText)
            sessions = try container.decodeIfPresent([TerminalActivitySessionSnapshot].self, forKey: .sessions) ?? []
            selectedPage = try container.decodeIfPresent(Int.self, forKey: .selectedPage) ?? 0
            updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
        }
    }

    public let serverID: String
    public let serverName: String
    public let address: String
    public let remoteOSFamilyRawValue: String

    public init(
        serverID: String = "terminal-aggregate",
        serverName: String = "Terminal",
        address: String = "",
        remoteOSFamilyRawValue: String = TerminalRemoteOSFamily.linux.rawValue
    ) {
        self.serverID = serverID
        self.serverName = serverName
        self.address = address
        self.remoteOSFamilyRawValue = remoteOSFamilyRawValue
    }
}

public struct TerminalActivitySessionSnapshot: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let serverName: String
    public let address: String
    public let remoteOSFamilyRawValue: String
    public let status: TerminalActivityStatus
    public let statusText: String
    public let updatedAt: Date

    public init(
        id: String,
        serverName: String,
        address: String,
        remoteOSFamilyRawValue: String,
        status: TerminalActivityStatus,
        statusText: String,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.serverName = serverName
        self.address = address
        self.remoteOSFamilyRawValue = remoteOSFamilyRawValue
        self.status = status
        self.statusText = statusText
        self.updatedAt = updatedAt
    }
}

public struct CycleTerminalSessionGroupIntent: LiveActivityIntent {
    public static var title: LocalizedStringResource { "Next SSH Group" }
    public static var description: IntentDescription { "Show the next group of SSH sessions in DevBar terminal live activity." }

    @Parameter(title: "Activity ID")
    public var activityID: String

    public init() {
        self.activityID = ""
    }

    public init(activityID: String) {
        self.activityID = activityID
    }

    public func perform() async throws -> some IntentResult {
        let activities = Activity<TerminalActivityAttributes>.activities
        guard let activity = activities.first(where: { $0.id == activityID }) ?? activities.first else {
            return .result()
        }
        let nextState = activity.content.state.cyclingSessionGroup()
        await activity.update(ActivityContent(state: nextState, staleDate: Calendar.current.date(byAdding: .minute, value: 30, to: .now)))
        return .result()
    }
}
#endif
