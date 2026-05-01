import Foundation

public struct QuotaResponse: Codable, Sendable, Equatable {
    public let code: Int
    public let msg: String?
    public let data: QuotaData?
    public let success: Bool?

    public init(code: Int, msg: String?, data: QuotaData?, success: Bool?) {
        self.code = code
        self.msg = msg
        self.data = data
        self.success = success
    }
}

public struct QuotaData: Codable, Sendable, Equatable {
    public let limits: [QuotaLimit]?
    public let level: String?

    public init(limits: [QuotaLimit]?, level: String?) {
        self.limits = limits
        self.level = level
    }
}

public struct QuotaLimit: Codable, Sendable, Identifiable, Equatable {
    public var id: String { "\(type)_\(unit ?? -1)_\(number ?? -1)" }

    public let type: String
    public let unit: Int?
    public let number: Int?
    public let usage: Int?
    public let currentValue: Int?
    public let remaining: Int?
    public let percentage: Int
    public let nextResetTime: Int64?
    public let usageDetails: [UsageDetail]?

    public init(
        type: String,
        unit: Int?,
        number: Int?,
        usage: Int?,
        currentValue: Int?,
        remaining: Int?,
        percentage: Int,
        nextResetTime: Int64?,
        usageDetails: [UsageDetail]?
    ) {
        self.type = type
        self.unit = unit
        self.number = number
        self.usage = usage
        self.currentValue = currentValue
        self.remaining = remaining
        self.percentage = percentage
        self.nextResetTime = nextResetTime
        self.usageDetails = usageDetails
    }
}

public struct UsageDetail: Codable, Sendable, Identifiable, Equatable {
    public var id: String { modelCode }

    public let modelCode: String
    public let usage: Int

    public init(modelCode: String, usage: Int) {
        self.modelCode = modelCode
        self.usage = usage
    }
}

public extension QuotaLimit {
    var displayName: String {
        switch type {
        case "TOKENS_LIMIT":
            guard let unit else { return CoreL10n.text("token_quota") }
            switch unit {
            case 3:
                return String(format: CoreL10n.text("glm_session_quota"), number ?? 5)
            case 6:
                return CoreL10n.text("glm_weekly_quota")
            default:
                return CoreL10n.text("token_quota")
            }
        case "TIME_LIMIT":
            return CoreL10n.text("mcp_monthly_quota")
        default:
            return type
        }
    }

    var unitDescription: String? {
        nil
    }

    var formattedResetTime: String? {
        guard let nextResetTime else { return nil }
        return Date.formattedDateTime(from: nextResetTime)
    }

    func toWidgetLimit() -> WidgetQuotaLimit {
        WidgetQuotaLimit(
            type: type,
            displayName: displayName,
            percentage: percentage,
            unitDescription: unitDescription,
            formattedResetTime: formattedResetTime
        )
    }
}

public extension QuotaData {
    func toWidgetData(
        subscriptionName: String?,
        subscriptionPrice: String?,
        subscriptionExpireDate: String?
    ) -> WidgetSharedData {
        WidgetSharedData(
            provider: .glm,
            schemaVersion: WidgetSharedData.currentSchemaVersion,
            limits: limits?.map { $0.toWidgetLimit() } ?? [],
            level: level,
            subscriptionName: subscriptionName,
            subscriptionPrice: subscriptionPrice,
            subscriptionExpireDate: subscriptionExpireDate,
            lastUpdated: Date()
        )
    }
}
