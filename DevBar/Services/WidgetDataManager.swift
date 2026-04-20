// WidgetDataManager.swift
// DevBar

import Foundation
import WidgetKit

// MARK: - WidgetDataManager

final class WidgetDataManager {
    static let shared = WidgetDataManager()

    private let defaults: UserDefaults? = {
        UserDefaults(suiteName: Constants.AppGroup.groupID)
    }()

    private init() {}

    func saveSharedData(_ data: WidgetSharedData) {
        guard let defaults else { return }
        do {
            let encoded = try JSONEncoder().encode(data)
            defaults.set(encoded, forKey: Constants.AppGroup.sharedDataKey)
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

    func clearSharedData() {
        guard let defaults else { return }
        defaults.removeObject(forKey: Constants.AppGroup.sharedDataKey)
    }

    func saveAndReload(_ data: WidgetSharedData) {
        saveSharedData(data)
        WidgetCenter.shared.reloadAllTimelines()
    }
}
