// NotificationSettings.swift
// DevBar

import Foundation

struct NotificationSettings {
    var lowQuotaEnabled: Bool
    var lowQuotaThreshold: Double // Percentage (0-100)
    var exhaustedEnabled: Bool
    var resetEnabled: Bool

    init(
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

    static let thresholdOptions: [(Double, String)] = [
        (10, "10%"),
        (20, "20%"),
        (30, "30%"),
        (50, "50%"),
    ]
}
