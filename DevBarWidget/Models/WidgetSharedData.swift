// WidgetSharedData.swift
// DevBarWidget

import Foundation

enum WidgetProvider: String, Codable, Sendable {
    case glm
    case openai
}

struct WidgetSharedData: Codable, Sendable {
    let provider: WidgetProvider?
    let schemaVersion: Int
    let limits: [WidgetQuotaLimit]
    let level: String?
    let subscriptionName: String?
    let subscriptionPrice: String?
    let subscriptionExpireDate: String?
    let lastUpdated: Date

    static let currentSchemaVersion = 4

    static let placeholder = WidgetSharedData(
        provider: nil,
        schemaVersion: currentSchemaVersion,
        limits: [],
        level: nil,
        subscriptionName: nil,
        subscriptionPrice: nil,
        subscriptionExpireDate: nil,
        lastUpdated: .distantPast
    )
}

struct WidgetQuotaLimit: Codable, Sendable, Identifiable {
    var id: String { "\(type)_\(displayName)" }
    let type: String
    let displayName: String
    let percentage: Int
    let unitDescription: String?
    let formattedResetTime: String?
}
