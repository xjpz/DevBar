import Foundation

public struct SubscriptionResponse: Codable, Sendable, Equatable {
    public let code: Int
    public let msg: String?
    public let data: [Subscription]?
    public let success: Bool?

    public init(code: Int, msg: String?, data: [Subscription]?, success: Bool?) {
        self.code = code
        self.msg = msg
        self.data = data
        self.success = success
    }
}

public struct Subscription: Codable, Sendable, Identifiable, Equatable {
    public var id: String { subscriptionId }

    public let subscriptionId: String
    public let productName: String
    public let description: String
    public let status: String
    public let valid: String
    public let autoRenew: Int
    public let actualPrice: Double
    public let renewPrice: Double
    public let currentPeriod: Int
    public let nextRenewTime: String
    public let billingCycle: String
    public let paymentType: String

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

    public init(
        subscriptionId: String,
        productName: String,
        description: String,
        status: String,
        valid: String,
        autoRenew: Int,
        actualPrice: Double,
        renewPrice: Double,
        currentPeriod: Int,
        nextRenewTime: String,
        billingCycle: String,
        paymentType: String
    ) {
        self.subscriptionId = subscriptionId
        self.productName = productName
        self.description = description
        self.status = status
        self.valid = valid
        self.autoRenew = autoRenew
        self.actualPrice = actualPrice
        self.renewPrice = renewPrice
        self.currentPeriod = currentPeriod
        self.nextRenewTime = nextRenewTime
        self.billingCycle = billingCycle
        self.paymentType = paymentType
    }

    public var isValid: Bool {
        status == "VALID"
    }

    public var formattedNextRenewDate: String {
        String(nextRenewTime.prefix(10))
    }

    public var formattedRenewPrice: String {
        String(format: "¥%.0f", renewPrice)
    }
}
