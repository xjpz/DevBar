import Foundation

public struct QuotaRowItem: Identifiable, Sendable, Equatable {
    public var id: String { name }

    public let name: String
    public let percentage: Int
    public let resetTime: String?
    public let unitDescription: String?

    public init(name: String, percentage: Int, resetTime: String?, unitDescription: String?) {
        self.name = name
        self.percentage = percentage
        self.resetTime = resetTime
        self.unitDescription = unitDescription
    }
}
