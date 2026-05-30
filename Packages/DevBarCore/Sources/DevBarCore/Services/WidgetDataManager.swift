import Foundation
import WidgetKit

@MainActor
public final class WidgetDataManager {
    public static let shared = WidgetDataManager()

    private let defaults: UserDefaults? = {
        UserDefaults(suiteName: DevBarCoreConstants.AppGroup.groupID)
    }()

    public init() {}

    public func saveSharedData(_ data: WidgetSharedData) {
        guard let defaults else { return }
        let key: String
        if let provider = data.provider {
            key = DevBarCoreConstants.AppGroup.sharedDataKey(for: provider.rawValue)
        } else {
            key = DevBarCoreConstants.AppGroup.sharedDataKey
        }
        do {
            let encoded = try JSONEncoder().encode(data)
            defaults.set(encoded, forKey: key)
        } catch {
            print("[DevBar] Failed to save widget data: \(error)")
        }
    }

    public func loadSharedData() -> WidgetSharedData? {
        guard let defaults,
              let data = defaults.data(forKey: DevBarCoreConstants.AppGroup.sharedDataKey) else {
            return nil
        }
        return try? JSONDecoder().decode(WidgetSharedData.self, from: data)
    }

    public func loadSharedData(for provider: String) -> WidgetSharedData? {
        guard let defaults else { return nil }
        let key = DevBarCoreConstants.AppGroup.sharedDataKey(for: provider)
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(WidgetSharedData.self, from: data)
    }

    public func clearSharedData() {
        guard let defaults else { return }
        defaults.removeObject(forKey: DevBarCoreConstants.AppGroup.sharedDataKey)
    }

    public func clearSharedData(for provider: String) {
        guard let defaults else { return }
        defaults.removeObject(forKey: DevBarCoreConstants.AppGroup.sharedDataKey(for: provider))
    }

    public func saveMacThemeSnapshot(_ snapshot: MacThemeWidgetSnapshot) {
        guard let defaults else { return }
        do {
            let encoded = try JSONEncoder().encode(snapshot)
            defaults.set(encoded, forKey: DevBarCoreConstants.AppGroup.macThemeWidgetSnapshotKey)
        } catch {
            print("[DevBar] Failed to save Mac theme widget snapshot: \(error)")
        }
    }

    public func loadMacThemeSnapshot() -> MacThemeWidgetSnapshot? {
        guard let defaults,
              let data = defaults.data(forKey: DevBarCoreConstants.AppGroup.macThemeWidgetSnapshotKey) else {
            return nil
        }
        return try? JSONDecoder().decode(MacThemeWidgetSnapshot.self, from: data)
    }

    public func clearMacThemeSnapshot() {
        guard let defaults else { return }
        defaults.removeObject(forKey: DevBarCoreConstants.AppGroup.macThemeWidgetSnapshotKey)
    }

    public func saveAndReload(_ data: WidgetSharedData) {
        saveSharedData(data)
        WidgetCenter.shared.reloadAllTimelines()
    }

    public func saveAndReload(_ data: WidgetSharedData, for provider: String) {
        guard let defaults else { return }
        let key = DevBarCoreConstants.AppGroup.sharedDataKey(for: provider)
        do {
            let encoded = try JSONEncoder().encode(data)
            defaults.set(encoded, forKey: key)
        } catch {
            print("[DevBar] Failed to save widget data: \(error)")
        }
        WidgetCenter.shared.reloadAllTimelines()
    }

    public func saveAndReload(_ snapshot: MacThemeWidgetSnapshot) {
        saveMacThemeSnapshot(snapshot)
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: - Agent Watcher Widget Data

    public func saveAgentWatcherData(_ data: AgentWatcherWidgetData) {
        guard let defaults else { return }
        do {
            let encoded = try JSONEncoder().encode(data)
            defaults.set(encoded, forKey: DevBarCoreConstants.AppGroup.agentWatcherWidgetKey)
        } catch {
            print("[DevBar] Failed to save agent watcher widget data: \(error)")
        }
    }

    public func loadAgentWatcherData() -> AgentWatcherWidgetData? {
        guard let defaults,
              let data = defaults.data(forKey: DevBarCoreConstants.AppGroup.agentWatcherWidgetKey) else {
            return nil
        }
        return try? JSONDecoder().decode(AgentWatcherWidgetData.self, from: data)
    }

    public func clearAgentWatcherData() {
        guard let defaults else { return }
        defaults.removeObject(forKey: DevBarCoreConstants.AppGroup.agentWatcherWidgetKey)
    }

    public func saveAndReloadAgentWatcher(_ data: AgentWatcherWidgetData) {
        saveAgentWatcherData(data)
        WidgetCenter.shared.reloadAllTimelines()
    }
}
