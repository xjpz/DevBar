import Foundation

public enum WidgetProvider: String, CaseIterable, Codable, Sendable {
    case glm
    case openai
    case mimo
}

public struct WidgetSharedData: Codable, Sendable, Equatable {
    public let provider: WidgetProvider?
    public let schemaVersion: Int
    public let limits: [WidgetQuotaLimit]
    public let level: String?
    public let subscriptionName: String?
    public let subscriptionPrice: String?
    public let subscriptionExpireDate: String?
    public let lastUpdated: Date

    public static let currentSchemaVersion = 4

    public static let placeholder = WidgetSharedData(
        provider: nil,
        schemaVersion: currentSchemaVersion,
        limits: [],
        level: nil,
        subscriptionName: nil,
        subscriptionPrice: nil,
        subscriptionExpireDate: nil,
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
        lastUpdated: Date
    ) {
        self.provider = provider
        self.schemaVersion = schemaVersion
        self.limits = limits
        self.level = level
        self.subscriptionName = subscriptionName
        self.subscriptionPrice = subscriptionPrice
        self.subscriptionExpireDate = subscriptionExpireDate
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
