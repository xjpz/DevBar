import Foundation

public struct NotificationSettings: Sendable, Equatable {
    public var lowQuotaEnabled: Bool
    public var lowQuotaThreshold: Double
    public var exhaustedEnabled: Bool
    public var resetEnabled: Bool

    public init(
        lowQuotaEnabled: Bool = false,
        lowQuotaThreshold: Double = 20,
        exhaustedEnabled: Bool = false,
        resetEnabled: Bool = false
    ) {
        self.lowQuotaEnabled = lowQuotaEnabled
        self.lowQuotaThreshold = lowQuotaThreshold
        self.exhaustedEnabled = exhaustedEnabled
        self.resetEnabled = resetEnabled
    }

    public static let thresholdOptions: [(Double, String)] = [
        (10, "10%"),
        (20, "20%"),
        (30, "30%"),
        (50, "50%"),
    ]
}
