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
}
