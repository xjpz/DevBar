// WidgetSharedData.swift
// DevBarWidget

import Foundation

struct WidgetSharedData: Codable, Sendable {
    let schemaVersion: Int
    let limits: [WidgetQuotaLimit]
    let level: String?
    let subscriptionName: String?
    let subscriptionPrice: String?
    let subscriptionExpireDate: String?
    let lastUpdated: Date

    static let currentSchemaVersion = 3

    static let placeholder = WidgetSharedData(
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
    var id: String { type }
    let type: String
    let displayName: String
    let percentage: Int
    let unitDescription: String?
    let formattedResetTime: String?
}
