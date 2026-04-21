// QuotaResponse.swift
// DevBar

import Foundation

// MARK: - API Response

struct QuotaResponse: Codable, Sendable {
    let code: Int
    let msg: String?
    let data: QuotaData?
    let success: Bool?
}

struct QuotaData: Codable, Sendable {
    let limits: [QuotaLimit]?
    let level: String?
}

// MARK: - Quota Limit

struct QuotaLimit: Codable, Sendable, Identifiable {
    var id: String { "\(type)_\(unit ?? -1)_\(number ?? -1)" }

    let type: String
    let unit: Int?
    let number: Int?
    let usage: Int?
    let currentValue: Int?
    let remaining: Int?
    let percentage: Int
    let nextResetTime: Int64?
    let usageDetails: [UsageDetail]?
}

struct UsageDetail: Codable, Sendable, Identifiable {
    var id: String { modelCode }

    let modelCode: String
    let usage: Int
}

// MARK: - Display Helpers

extension QuotaLimit {
    /// Human-readable type name
    var displayName: String {
        switch type {
        case "TOKENS_LIMIT":
            guard let unit else { return String(localized: "token_quota") }
            switch unit {
            case 3:
                return String(format: String(localized: "glm_session_quota"), number ?? 5)
            case 6:
                return String(localized: "glm_weekly_quota")
            default:
                return String(localized: "token_quota")
            }
        case "TIME_LIMIT":
            return String(localized: "mcp_monthly_quota")
        default:
            return type
        }
    }

    /// Description for the limit period
    var unitDescription: String? {
        nil
    }

    /// Formatted reset time
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

// MARK: - Widget Data Conversion

extension QuotaData {
    func toWidgetData(subscriptionName: String?, subscriptionPrice: String?, subscriptionExpireDate: String?) -> WidgetSharedData {
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
