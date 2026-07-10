import Foundation

public protocol ICloudSyncSettingsStore {
    func load() -> ICloudSyncSettings
    func save(_ settings: ICloudSyncSettings)
}

public struct UserDefaultsICloudSyncSettingsStore: ICloudSyncSettingsStore {
    private let defaults: UserDefaults
    private let key: String

    public init(
        defaults: UserDefaults = .standard,
        key: String = DevBarCoreConstants.Defaults.iCloudSyncSettingsKey
    ) {
        self.defaults = defaults
        self.key = key
    }

    public func load() -> ICloudSyncSettings {
        guard let data = defaults.data(forKey: key),
              let settings = try? JSONDecoder().decode(ICloudSyncSettings.self, from: data) else {
            return .default
        }
        return settings.normalizedForFirstVersion
    }

    public func save(_ settings: ICloudSyncSettings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: key)
    }
}
