import Foundation

public final class LiveActivitySettingsStore {
    private let defaults: UserDefaults?
    private let key: String

    public init(
        defaults: UserDefaults? = UserDefaults(suiteName: DevBarCoreConstants.AppGroup.groupID),
        key: String = DevBarCoreConstants.Defaults.liveActivitySettingsKey
    ) {
        self.defaults = defaults
        self.key = key
    }

    public func load() -> LiveActivitySettings {
        guard let data = defaults?.data(forKey: key),
              let settings = try? JSONDecoder().decode(LiveActivitySettings.self, from: data) else {
            return .defaults
        }
        return settings
    }

    public func save(_ settings: LiveActivitySettings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults?.set(data, forKey: key)
    }
}
