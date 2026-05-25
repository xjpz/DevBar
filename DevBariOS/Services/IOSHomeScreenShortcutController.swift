import DevBarCore
import UIKit

enum IOSHomeScreenShortcutController {
    @MainActor
    static func apply(selectedActions: [DeviceRelayHomeScreenShortcutAction], hasPairedMac: Bool) {
        let actions = DeviceRelayHomeScreenShortcutPolicy.normalizedSelection(
            selectedActions,
            hasPairedMac: hasPairedMac
        )
        UIApplication.shared.shortcutItems = actions.map(shortcutItem(for:))
    }

    static func action(for shortcutType: String) -> DeviceRelayHomeScreenShortcutAction? {
        DeviceRelayHomeScreenShortcutAction(rawValue: shortcutType)
    }

    private static func shortcutItem(for action: DeviceRelayHomeScreenShortcutAction) -> UIApplicationShortcutItem {
        UIApplicationShortcutItem(
            type: action.rawValue,
            localizedTitle: title(for: action),
            localizedSubtitle: nil,
            icon: UIApplicationShortcutIcon(systemImageName: iconName(for: action)),
            userInfo: nil
        )
    }

    private static func title(for action: DeviceRelayHomeScreenShortcutAction) -> String {
        String(localized: String.LocalizationValue(titleKey(for: action)), bundle: .main)
    }

    static func titleKey(for action: DeviceRelayHomeScreenShortcutAction) -> String {
        switch action {
        case .memo: return "ios_home_shortcut_memo"
        case .qrScan: return "ios_home_shortcut_scan"
        case .ocr: return "ios_home_shortcut_ocr"
        case .apiClient: return "ios_home_shortcut_api_client"
        case .lockMac: return "ios_home_shortcut_lock_mac"
        case .wakeMacDisplay: return "ios_home_shortcut_wake_mac"
        case .sleepMacDisplay: return "ios_home_shortcut_sleep_mac_display"
        }
    }

    private static func iconName(for action: DeviceRelayHomeScreenShortcutAction) -> String {
        switch action {
        case .memo: return "note.text"
        case .qrScan: return "qrcode.viewfinder"
        case .ocr: return "text.viewfinder"
        case .apiClient: return "globe"
        case .lockMac: return "lock.fill"
        case .wakeMacDisplay: return "sun.max.fill"
        case .sleepMacDisplay: return "display"
        }
    }
}

enum IOSHomeScreenShortcutPreferences {
    private static let selectedActionsKey = "ios_homeScreenShortcutActions"

    static func loadSelectedActions() -> [DeviceRelayHomeScreenShortcutAction]? {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: selectedActionsKey) != nil else {
            return nil
        }
        return defaults.stringArray(forKey: selectedActionsKey)?
            .compactMap(DeviceRelayHomeScreenShortcutAction.init(rawValue:)) ?? []
    }

    static func saveSelectedActions(_ actions: [DeviceRelayHomeScreenShortcutAction]) {
        UserDefaults.standard.set(actions.map(\.rawValue), forKey: selectedActionsKey)
    }
}
