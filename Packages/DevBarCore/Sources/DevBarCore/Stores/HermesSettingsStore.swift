import Foundation

public protocol HermesSettingsStore {
    func load() -> HermesSettings
    func save(_ settings: HermesSettings)
    func loadQuickStartItems(defaults defaultItems: [HermesQuickStartItem]) -> [HermesQuickStartItem]
    func saveQuickStartItems(_ items: [HermesQuickStartItem])
    func resetQuickStartItems()
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
            hermesModel: defaults.string(forKey: DevBarCoreConstants.Defaults.hermesModelKey) ?? HermesSettings.defaults.hermesModel,
            hermesProvider: defaults.string(forKey: DevBarCoreConstants.Defaults.hermesProviderKey) ?? HermesSettings.defaults.hermesProvider,
            isStreamingEnabled: defaults.object(forKey: DevBarCoreConstants.Defaults.hermesStreamingEnabledKey) as? Bool
                ?? HermesSettings.defaults.isStreamingEnabled,
            chatTabProvider: ChatBotProviderKind(
                rawValue: defaults.string(forKey: DevBarCoreConstants.Defaults.hermesChatTabProviderKey) ?? ""
            ) ?? HermesSettings.defaults.chatTabProvider,
            hermesChatRemark: defaults.string(forKey: DevBarCoreConstants.Defaults.hermesChatHermesRemarkKey)
                ?? HermesSettings.defaults.hermesChatRemark,
            hermesChatTag: defaults.string(forKey: DevBarCoreConstants.Defaults.hermesChatHermesTagKey)
                ?? HermesSettings.defaults.hermesChatTag
        )
    }

    public func save(_ settings: HermesSettings) {
        persist(settings)
        markCloudSettingsModified()
    }

    public func loadCloudSyncState() -> ICloudPreferenceState<HermesCloudSyncSnapshot>? {
        let settings = load()
        if let updatedAt = cloudSettingsUpdatedAt {
            return ICloudPreferenceState(value: HermesCloudSyncSnapshot(settings: settings), updatedAt: updatedAt)
        }
        guard settings != .defaults else { return nil }
        let migratedAt = Date(timeIntervalSince1970: 0)
        setCloudSettingsUpdatedAt(migratedAt)
        return ICloudPreferenceState(value: HermesCloudSyncSnapshot(settings: settings), updatedAt: migratedAt)
    }

    @discardableResult
    public func applyCloudSyncState(_ state: ICloudPreferenceState<HermesCloudSyncSnapshot>) -> Bool {
        guard state.value.schemaVersion == HermesCloudSyncSnapshot.schemaVersion else { return false }
        if let localUpdatedAt = cloudSettingsUpdatedAt, localUpdatedAt > state.updatedAt {
            return false
        }
        persist(state.value.settings)
        setCloudSettingsUpdatedAt(state.updatedAt)
        return true
    }

    private func persist(_ settings: HermesSettings) {
        defaults.set(
            settings.apiBaseURL.trimmingCharacters(in: .whitespacesAndNewlines),
            forKey: DevBarCoreConstants.Defaults.hermesAPIBaseURLKey
        )
        defaults.set(
            settings.hermesModel.trimmingCharacters(in: .whitespacesAndNewlines),
            forKey: DevBarCoreConstants.Defaults.hermesModelKey
        )
        defaults.set(
            settings.hermesProvider.trimmingCharacters(in: .whitespacesAndNewlines),
            forKey: DevBarCoreConstants.Defaults.hermesProviderKey
        )
        defaults.set(
            settings.isStreamingEnabled,
            forKey: DevBarCoreConstants.Defaults.hermesStreamingEnabledKey
        )
        defaults.set(
            settings.normalizedChatTabProvider.rawValue,
            forKey: DevBarCoreConstants.Defaults.hermesChatTabProviderKey
        )
        defaults.set(
            settings.hermesChatRemark.trimmingCharacters(in: .whitespacesAndNewlines),
            forKey: DevBarCoreConstants.Defaults.hermesChatHermesRemarkKey
        )
        defaults.set(
            settings.hermesChatTag.trimmingCharacters(in: .whitespacesAndNewlines),
            forKey: DevBarCoreConstants.Defaults.hermesChatHermesTagKey
        )
    }

    private var cloudSettingsUpdatedAt: Date? {
        guard defaults.object(forKey: DevBarCoreConstants.Defaults.hermesSettingsCloudUpdatedAtKey) != nil else {
            return nil
        }
        return Date(
            timeIntervalSince1970: defaults.double(
                forKey: DevBarCoreConstants.Defaults.hermesSettingsCloudUpdatedAtKey
            )
        )
    }

    private func markCloudSettingsModified() {
        setCloudSettingsUpdatedAt(Date())
    }

    private func setCloudSettingsUpdatedAt(_ date: Date) {
        defaults.set(
            date.timeIntervalSince1970,
            forKey: DevBarCoreConstants.Defaults.hermesSettingsCloudUpdatedAtKey
        )
    }

    public func loadQuickStartItems(defaults defaultItems: [HermesQuickStartItem]) -> [HermesQuickStartItem] {
        guard let data = defaults.data(forKey: DevBarCoreConstants.Defaults.hermesQuickStartItemsKey) else {
            return defaultItems.compactMap(\.normalized)
        }
        guard let items = try? JSONDecoder().decode([HermesQuickStartItem].self, from: data) else {
            return defaultItems.compactMap(\.normalized)
        }
        return items.compactMap(\.normalized)
    }

    public func saveQuickStartItems(_ items: [HermesQuickStartItem]) {
        let normalizedItems = items.compactMap(\.normalized)
        guard let data = try? JSONEncoder().encode(normalizedItems) else {
            return
        }
        defaults.set(data, forKey: DevBarCoreConstants.Defaults.hermesQuickStartItemsKey)
    }

    public func resetQuickStartItems() {
        defaults.removeObject(forKey: DevBarCoreConstants.Defaults.hermesQuickStartItemsKey)
    }

    public func loadWebKitTabEnabled() -> Bool {
        defaults.object(forKey: DevBarCoreConstants.Defaults.iosWebKitTabEnabledKey) as? Bool ?? true
    }

    public func saveWebKitTabEnabled(_ isEnabled: Bool) {
        defaults.set(isEnabled, forKey: DevBarCoreConstants.Defaults.iosWebKitTabEnabledKey)
    }
}
