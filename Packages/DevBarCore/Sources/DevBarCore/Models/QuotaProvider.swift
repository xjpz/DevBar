import Foundation
import SwiftUI

public enum QuotaProvider: String, CaseIterable, Codable, Sendable {
    case glm
    case openai
    case mimo

    public var localizedName: String {
        switch self {
        case .glm: return "GLM"
        case .openai: return "OpenAI"
        case .mimo: return "MiMo"
        }
    }

    public var iconName: String {
        switch self {
        case .glm: return "sparkles"
        case .openai: return "circle.hexagon"
        case .mimo: return "bolt.hexagon"
        }
    }

    public var assetName: String {
        switch self {
        case .glm: return "GLM"
        case .openai: return "OpenAI"
        case .mimo: return "MiMO"
        }
    }

    public var accentColor: Color {
        switch self {
        case .glm: return Color(red: 0.14, green: 0.59, blue: 0.93)
        case .openai: return Color(red: 0.12, green: 0.69, blue: 0.54)
        case .mimo: return Color(red: 1.0, green: 0.42, blue: 0.08)
        }
    }
}

public struct AccountConfig: Codable, Sendable, Identifiable, Equatable {
    public var id: String { provider.rawValue }

    public let provider: QuotaProvider
    public var isEnabled: Bool
    public var order: Int

    public init(provider: QuotaProvider, isEnabled: Bool, order: Int) {
        self.provider = provider
        self.isEnabled = isEnabled
        self.order = order
    }
}

public struct OpenAIUsageResponse: Codable, Sendable, Equatable {
    public let planType: String?
    public let rateLimit: OpenAIRateLimit?

    enum CodingKeys: String, CodingKey {
        case planType = "plan_type"
        case rateLimit = "rate_limit"
    }

    public init(planType: String?, rateLimit: OpenAIRateLimit?) {
        self.planType = planType
        self.rateLimit = rateLimit
    }
}

public struct OpenAIRateLimit: Codable, Sendable, Equatable {
    public let allowed: Bool?
    public let limitReached: Bool?
    public let primaryWindow: OpenAIUsageWindow?
    public let secondaryWindow: OpenAIUsageWindow?

    enum CodingKeys: String, CodingKey {
        case allowed
        case limitReached = "limit_reached"
        case primaryWindow = "primary_window"
        case secondaryWindow = "secondary_window"
    }

    public init(
        allowed: Bool?,
        limitReached: Bool?,
        primaryWindow: OpenAIUsageWindow?,
        secondaryWindow: OpenAIUsageWindow?
    ) {
        self.allowed = allowed
        self.limitReached = limitReached
        self.primaryWindow = primaryWindow
        self.secondaryWindow = secondaryWindow
    }
}

public struct OpenAIUsageWindow: Codable, Sendable, Equatable {
    public let usedPercent: Int
    public let limitWindowSeconds: Int?
    public let resetAfterSeconds: Int?
    public let resetAt: Int?

    enum CodingKeys: String, CodingKey {
        case usedPercent = "used_percent"
        case limitWindowSeconds = "limit_window_seconds"
        case resetAfterSeconds = "reset_after_seconds"
        case resetAt = "reset_at"
    }

    public init(
        usedPercent: Int,
        limitWindowSeconds: Int?,
        resetAfterSeconds: Int?,
        resetAt: Int?
    ) {
        self.usedPercent = usedPercent
        self.limitWindowSeconds = limitWindowSeconds
        self.resetAfterSeconds = resetAfterSeconds
        self.resetAt = resetAt
    }

    public var displayName: String {
        guard let seconds = limitWindowSeconds else { return "" }
        let hours = seconds / 3600
        if hours >= 168 {
            return CoreL10n.text("openai_weekly")
        } else if hours >= 24 {
            return CoreL10n.text("openai_daily")
        } else {
            return String(format: CoreL10n.text("openai_session"), Int(hours))
        }
    }

    public var formattedResetTime: String? {
        guard let resetAt else { return nil }
        let date = Date(timeIntervalSince1970: TimeInterval(resetAt))
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd HH:mm"
        return formatter.string(from: date)
    }
}
