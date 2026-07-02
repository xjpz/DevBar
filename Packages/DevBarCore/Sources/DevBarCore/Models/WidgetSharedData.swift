import Foundation

public enum WidgetProvider: String, CaseIterable, Codable, Sendable {
    case glm
    case openai
    case mimo
    case deepseek
}

public struct WidgetSharedData: Codable, Sendable, Equatable {
    public let provider: WidgetProvider?
    public let schemaVersion: Int
    public let limits: [WidgetQuotaLimit]
    public let level: String?
    public let subscriptionName: String?
    public let subscriptionPrice: String?
    public let subscriptionExpireDate: String?
    public let availableResetCount: Int?
    public let lastUpdated: Date

    public static let currentSchemaVersion = 5

    public static let placeholder = WidgetSharedData(
        provider: nil,
        schemaVersion: currentSchemaVersion,
        limits: [],
        level: nil,
        subscriptionName: nil,
        subscriptionPrice: nil,
        subscriptionExpireDate: nil,
        availableResetCount: nil,
        lastUpdated: .distantPast
    )

    public init(
        provider: WidgetProvider?,
        schemaVersion: Int,
        limits: [WidgetQuotaLimit],
        level: String?,
        subscriptionName: String?,
        subscriptionPrice: String?,
        subscriptionExpireDate: String?,
        availableResetCount: Int? = nil,
        lastUpdated: Date
    ) {
        self.provider = provider
        self.schemaVersion = schemaVersion
        self.limits = limits
        self.level = level
        self.subscriptionName = subscriptionName
        self.subscriptionPrice = subscriptionPrice
        self.subscriptionExpireDate = subscriptionExpireDate
        self.availableResetCount = availableResetCount
        self.lastUpdated = lastUpdated
    }
}

public struct WidgetQuotaLimit: Codable, Sendable, Identifiable, Equatable {
    public var id: String { "\(type)_\(displayName)" }

    public let type: String
    public let displayName: String
    public let percentage: Int
    public let unitDescription: String?
    public let formattedResetTime: String?

    public init(
        type: String,
        displayName: String,
        percentage: Int,
        unitDescription: String?,
        formattedResetTime: String?
    ) {
        self.type = type
        self.displayName = displayName
        self.percentage = percentage
        self.unitDescription = unitDescription
        self.formattedResetTime = formattedResetTime
    }
}

public struct ProviderQuotaSnapshot: Codable, Sendable, Identifiable, Equatable {
    public var id: String { accountID }

    public let accountID: String
    public let provider: QuotaProvider
    public let displayName: String
    public let limits: [WidgetQuotaLimit]
    public let level: String?
    public let subscriptionName: String?
    public let subscriptionExpireDate: String?
    public let availableResetCount: Int?
    public let fetchedAt: Date
    public let sourceDeviceID: String?
    public let revision: Int

    public init(
        accountID: String,
        provider: QuotaProvider,
        displayName: String,
        limits: [WidgetQuotaLimit],
        level: String?,
        subscriptionName: String?,
        subscriptionExpireDate: String?,
        availableResetCount: Int? = nil,
        fetchedAt: Date = Date(),
        sourceDeviceID: String? = nil,
        revision: Int = 1
    ) {
        self.accountID = accountID
        self.provider = provider
        self.displayName = displayName
        self.limits = limits
        self.level = level
        self.subscriptionName = subscriptionName
        self.subscriptionExpireDate = subscriptionExpireDate
        self.availableResetCount = availableResetCount
        self.fetchedAt = fetchedAt
        self.sourceDeviceID = sourceDeviceID
        self.revision = revision
    }

    public var widgetData: WidgetSharedData {
        WidgetSharedData(
            provider: WidgetProvider(rawValue: provider.rawValue),
            schemaVersion: WidgetSharedData.currentSchemaVersion,
            limits: limits,
            level: level,
            subscriptionName: subscriptionName,
            subscriptionPrice: nil,
            subscriptionExpireDate: subscriptionExpireDate,
            availableResetCount: availableResetCount,
            lastUpdated: fetchedAt
        )
    }

    public func shouldReplace(_ existing: ProviderQuotaSnapshot?) -> Bool {
        shouldReplace(existing: existing, localLastUpdated: nil)
    }

    public func shouldReplace(existing: ProviderQuotaSnapshot?, localLastUpdated: Date?) -> Bool {
        if let localLastUpdated, fetchedAt < localLastUpdated {
            return false
        }
        guard let existing else { return true }
        if revision != existing.revision {
            return revision > existing.revision
        }
        return fetchedAt >= existing.fetchedAt
    }
}

// MARK: - Agent Watcher Widget Data

public struct AgentWatcherWidgetData: Codable, Sendable, Equatable {
    public let waitingCount: Int
    public let activeCount: Int
    public let lastUpdated: Date
    public let waitingSessions: [AgentWatcherSessionInfo]

    public init(
        waitingCount: Int,
        activeCount: Int,
        lastUpdated: Date,
        waitingSessions: [AgentWatcherSessionInfo]
    ) {
        self.waitingCount = waitingCount
        self.activeCount = activeCount
        self.lastUpdated = lastUpdated
        self.waitingSessions = waitingSessions
    }

    public static let placeholder = AgentWatcherWidgetData(
        waitingCount: 0,
        activeCount: 0,
        lastUpdated: .distantPast,
        waitingSessions: []
    )
}

public struct AgentWatcherSessionInfo: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let source: String
    public let projectName: String
    public let state: String
    public let waitingSince: Date?
    public let message: String

    public init(
        id: String,
        source: String,
        projectName: String,
        state: String,
        waitingSince: Date?,
        message: String
    ) {
        self.id = id
        self.source = source
        self.projectName = projectName
        self.state = state
        self.waitingSince = waitingSince
        self.message = message
    }
}
