// SubscriptionResponse.swift
// DevBar

import Foundation

struct SubscriptionResponse: Codable, Sendable {
    let code: Int
    let msg: String?
    let data: [Subscription]?
    let success: Bool?
}

struct Subscription: Codable, Sendable, Identifiable {
    var id: String { subscriptionId }

    let subscriptionId: String
    let productName: String
    let description: String
    let status: String
    let valid: String
    let autoRenew: Int
    let actualPrice: Double
    let renewPrice: Double
    let currentPeriod: Int
    let nextRenewTime: String
    let billingCycle: String
    let paymentType: String

    enum CodingKeys: String, CodingKey {
        case subscriptionId = "id"
        case productName
        case description
        case status
        case valid
        case autoRenew
        case actualPrice
        case renewPrice
        case currentPeriod
        case nextRenewTime
        case billingCycle
        case paymentType
    }

    /// Whether this subscription is currently active
    var isValid: Bool {
        status == "VALID"
    }

    /// Formatted renewal date (e.g. "2027-03-16")
    var formattedNextRenewDate: String {
        String(nextRenewTime.prefix(10))
    }

    /// Formatted renewal price
    var formattedRenewPrice: String {
        String(format: "¥%.0f", renewPrice)
    }
}
