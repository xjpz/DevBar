import Foundation

public protocol ICloudSyncSettingsStore {
    func load() -> ICloudSyncSettings
    func save(_ settings: ICloudSyncSettings)
}

public protocol ICloudKeyValueStore: AnyObject {
    func data(forKey defaultName: String) -> Data?
    func set(_ value: Any?, forKey defaultName: String)
    @discardableResult func synchronize() -> Bool
}

extension NSUbiquitousKeyValueStore: ICloudKeyValueStore {}
extension UserDefaults: ICloudKeyValueStore {}

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

public struct UbiquitousICloudSyncSettingsStore: ICloudSyncSettingsStore {
    private let defaults: UserDefaults
    private let ubiquitousStore: any ICloudKeyValueStore
    private let settingsKey: String
    private let envelopeKey: String

    public init(
        defaults: UserDefaults = .standard,
        ubiquitousStore: any ICloudKeyValueStore = NSUbiquitousKeyValueStore.default,
        settingsKey: String = DevBarCoreConstants.Defaults.iCloudSyncSettingsKey,
        envelopeKey: String = DevBarCoreConstants.Defaults.iCloudSyncSettingsEnvelopeKey
    ) {
        self.defaults = defaults
        self.ubiquitousStore = ubiquitousStore
        self.settingsKey = settingsKey
        self.envelopeKey = envelopeKey
    }

    public func load() -> ICloudSyncSettings {
        _ = ubiquitousStore.synchronize()
        let localEnvelope = decodeEnvelope(defaults.data(forKey: envelopeKey))
        let cloudEnvelope = decodeEnvelope(ubiquitousStore.data(forKey: envelopeKey))
        if let resolved = [localEnvelope, cloudEnvelope].compactMap({ $0 }).max(by: { $0.updatedAt < $1.updatedAt }) {
            persist(resolved)
            return resolved.settings.normalizedForFirstVersion
        }

        guard defaults.data(forKey: settingsKey) != nil else { return .default }
        let legacySettings = UserDefaultsICloudSyncSettingsStore(defaults: defaults, key: settingsKey).load()
        let migrated = ICloudSyncSettingsEnvelope(settings: legacySettings, updatedAt: Date(timeIntervalSince1970: 0))
        persist(migrated)
        return legacySettings
    }

    public func save(_ settings: ICloudSyncSettings) {
        persist(ICloudSyncSettingsEnvelope(settings: settings.normalizedForFirstVersion, updatedAt: Date()))
    }

    private func decodeEnvelope(_ data: Data?) -> ICloudSyncSettingsEnvelope? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(ICloudSyncSettingsEnvelope.self, from: data)
    }

    private func persist(_ envelope: ICloudSyncSettingsEnvelope) {
        guard let data = try? JSONEncoder().encode(envelope),
              let settingsData = try? JSONEncoder().encode(envelope.settings.normalizedForFirstVersion) else {
            return
        }
        defaults.set(settingsData, forKey: settingsKey)
        defaults.set(data, forKey: envelopeKey)
        ubiquitousStore.set(data, forKey: envelopeKey)
        _ = ubiquitousStore.synchronize()
    }
}

private struct ICloudSyncSettingsEnvelope: Codable {
    var settings: ICloudSyncSettings
    var updatedAt: Date
}
