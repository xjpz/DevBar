import Foundation

public enum DeviceRelayHomeScreenShortcutAction: String, Sendable, Hashable {
    case memo = "com.xjpz.DevBar.memo"
    case qrScan = "com.xjpz.DevBar.qr-scan"
    case apiClient = "com.xjpz.DevBar.api-client"
    case lockMac = "com.xjpz.DevBar.lock-mac"
    case wakeMacDisplay = "com.xjpz.DevBar.wake-mac-display"
    case sleepMacDisplay = "com.xjpz.DevBar.sleep-mac-display"
    case ocr = "com.xjpz.DevBar.ocr"

    public var requiresPairedMac: Bool {
        switch self {
        case .lockMac, .wakeMacDisplay, .sleepMacDisplay:
            return true
        case .memo, .qrScan, .apiClient, .ocr:
            return false
        }
    }
}

public enum DeviceRelayHomeScreenShortcutPolicy {
    public static let maxSelectedActions = 4

    public static let defaultActions: [DeviceRelayHomeScreenShortcutAction] = [
        .memo,
        .qrScan,
        .ocr,
        .lockMac,
    ]

    public static let allActions: [DeviceRelayHomeScreenShortcutAction] = [
        .memo,
        .qrScan,
        .ocr,
        .apiClient,
        .lockMac,
        .wakeMacDisplay,
        .sleepMacDisplay,
    ]

    public static func availableActions(hasPairedMac: Bool) -> [DeviceRelayHomeScreenShortcutAction] {
        allActions.filter { hasPairedMac || !$0.requiresPairedMac }
    }

    public static func normalizedSelection(
        _ selectedActions: [DeviceRelayHomeScreenShortcutAction],
        hasPairedMac: Bool
    ) -> [DeviceRelayHomeScreenShortcutAction] {
        let availableActions = Set(availableActions(hasPairedMac: hasPairedMac))
        var result: [DeviceRelayHomeScreenShortcutAction] = []

        for action in selectedActions where availableActions.contains(action) && !result.contains(action) {
            result.append(action)
            if result.count == maxSelectedActions {
                break
            }
        }

        return result
    }

    public static func defaultSelection(hasPairedMac: Bool) -> [DeviceRelayHomeScreenShortcutAction] {
        normalizedSelection(defaultActions, hasPairedMac: hasPairedMac)
    }
}
