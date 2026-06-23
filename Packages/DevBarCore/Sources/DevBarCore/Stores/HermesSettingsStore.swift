import Foundation

public protocol HermesSettingsStore {
    func load() -> HermesSettings
    func save(_ settings: HermesSettings)
    func loadWebKitTabEnabled() -> Bool
    func saveWebKitTabEnabled(_ isEnabled: Bool)
}

public struct UserDefaultsHermesSettingsStore: HermesSettingsStore {
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load() -> HermesSettings {
        HermesSettings(
            apiBaseURL: defaults.string(forKey: DevBarCoreConstants.Defaults.hermesAPIBaseURLKey) ?? HermesSettings.defaults.apiBaseURL,
            isStreamingEnabled: defaults.object(forKey: DevBarCoreConstants.Defaults.hermesStreamingEnabledKey) as? Bool
                ?? HermesSettings.defaults.isStreamingEnabled
        )
    }

    public func save(_ settings: HermesSettings) {
        defaults.set(
            settings.apiBaseURL.trimmingCharacters(in: .whitespacesAndNewlines),
            forKey: DevBarCoreConstants.Defaults.hermesAPIBaseURLKey
        )
        defaults.set(
            settings.isStreamingEnabled,
            forKey: DevBarCoreConstants.Defaults.hermesStreamingEnabledKey
        )
    }

    public func loadWebKitTabEnabled() -> Bool {
        defaults.object(forKey: DevBarCoreConstants.Defaults.iosWebKitTabEnabledKey) as? Bool ?? true
    }

    public func saveWebKitTabEnabled(_ isEnabled: Bool) {
        defaults.set(isEnabled, forKey: DevBarCoreConstants.Defaults.iosWebKitTabEnabledKey)
    }
}
