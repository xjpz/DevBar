// QuotaProvider.swift
// DevBar

import Foundation
import SwiftUI

enum QuotaProvider: String, CaseIterable, Codable, Sendable {
    case glm
    case openai

    var localizedName: String {
        switch self {
        case .glm: return "GLM"
        case .openai: return "OpenAI"
        }
    }

    var iconName: String {
        switch self {
        case .glm: return "sparkles"
        case .openai: return "circle.hexagon"
        }
    }

    var assetName: String {
        switch self {
        case .glm: return "GLM"
        case .openai: return "OpenAI"
        }
    }

    var accentColor: Color {
        switch self {
        case .glm: return Color(red: 0.14, green: 0.59, blue: 0.93)
        case .openai: return Color(red: 0.12, green: 0.69, blue: 0.54)
        }
    }
}

struct AccountConfig: Codable, Sendable, Identifiable {
    var id: String { provider.rawValue }

    let provider: QuotaProvider
    var isEnabled: Bool
    var order: Int
}

// MARK: - OpenAI API Response Models

struct OpenAIUsageResponse: Codable, Sendable {
    let planType: String?
    let rateLimit: OpenAIRateLimit?

    enum CodingKeys: String, CodingKey {
        case planType = "plan_type"
        case rateLimit = "rate_limit"
    }
}

struct OpenAIRateLimit: Codable, Sendable {
    let allowed: Bool?
    let limitReached: Bool?
    let primaryWindow: OpenAIUsageWindow?
    let secondaryWindow: OpenAIUsageWindow?

    enum CodingKeys: String, CodingKey {
        case allowed
        case limitReached = "limit_reached"
        case primaryWindow = "primary_window"
        case secondaryWindow = "secondary_window"
    }
}

struct OpenAIUsageWindow: Codable, Sendable {
    let usedPercent: Int
    let limitWindowSeconds: Int?
    let resetAfterSeconds: Int?
    let resetAt: Int?

    enum CodingKeys: String, CodingKey {
        case usedPercent = "used_percent"
        case limitWindowSeconds = "limit_window_seconds"
        case resetAfterSeconds = "reset_after_seconds"
        case resetAt = "reset_at"
    }

    var displayName: String {
        guard let seconds = limitWindowSeconds else { return "" }
        let hours = seconds / 3600
        if hours >= 168 {
            return String(localized: "openai_weekly")
        } else if hours >= 24 {
            return String(localized: "openai_daily")
        } else {
            return String(format: String(localized: "openai_session"), Int(hours))
        }
    }

    var formattedResetTime: String? {
        guard let resetAt else { return nil }
        let date = Date(timeIntervalSince1970: TimeInterval(resetAt))
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd HH:mm"
        return formatter.string(from: date)
    }
}
