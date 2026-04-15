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
    var id: String { type }

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
            return "Token 使用额度"
        case "TIME_LIMIT":
            return "MCP 每月额度"
        default:
            return type
        }
    }

    /// Description for the limit period
    var unitDescription: String? {
        switch type {
        case "TIME_LIMIT":
            return "每月"
        case "TOKENS_LIMIT":
            return "每小时"
        default:
            return nil
        }
    }

    /// Formatted reset time
    var formattedResetTime: String? {
        guard let nextResetTime else { return nil }
        return Date.formattedDateTime(from: nextResetTime)
    }
}
