// WidgetDataManager.swift
// DevBar

import Foundation
import WidgetKit

final class WidgetDataManager {
    static let shared = WidgetDataManager()

    private let defaults: UserDefaults? = {
        UserDefaults(suiteName: Constants.AppGroup.groupID)
    }()

    private init() {}

    func saveSharedData(_ data: WidgetSharedData) {
        guard let defaults else { return }
        let key: String
        if let provider = data.provider {
            key = Constants.AppGroup.sharedDataKey(for: provider.rawValue)
        } else {
            key = Constants.AppGroup.sharedDataKey
        }
        do {
            let encoded = try JSONEncoder().encode(data)
            defaults.set(encoded, forKey: key)
        } catch {
            print("[DevBar] Failed to save widget data: \(error)")
        }
    }

    func loadSharedData() -> WidgetSharedData? {
        guard let defaults,
              let data = defaults.data(forKey: Constants.AppGroup.sharedDataKey) else {
            return nil
        }
        return try? JSONDecoder().decode(WidgetSharedData.self, from: data)
    }

    func loadSharedData(for provider: String) -> WidgetSharedData? {
        guard let defaults else { return nil }
        let key = Constants.AppGroup.sharedDataKey(for: provider)
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(WidgetSharedData.self, from: data)
    }

    func clearSharedData() {
        guard let defaults else { return }
        defaults.removeObject(forKey: Constants.AppGroup.sharedDataKey)
    }

    func clearSharedData(for provider: String) {
        guard let defaults else { return }
        defaults.removeObject(forKey: Constants.AppGroup.sharedDataKey(for: provider))
    }

    func saveAndReload(_ data: WidgetSharedData) {
        saveSharedData(data)
        WidgetCenter.shared.reloadAllTimelines()
    }

    func saveAndReload(_ data: WidgetSharedData, for provider: String) {
        guard let defaults else { return }
        let key = Constants.AppGroup.sharedDataKey(for: provider)
        do {
            let encoded = try JSONEncoder().encode(data)
            defaults.set(encoded, forKey: key)
        } catch {
            print("[DevBar] Failed to save widget data: \(error)")
        }
        WidgetCenter.shared.reloadAllTimelines()
    }
}
