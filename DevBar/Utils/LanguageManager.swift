// LanguageManager.swift
// DevBar

import SwiftUI
import Combine

enum AppLanguage: String, CaseIterable, Codable {
    case system = "system"
    case zhHans = "zh-Hans"
    case en = "en"

    var displayName: String {
        switch self {
        case .system: String(localized: "follow_system")
        case .zhHans: "简体中文"
        case .en: "English"
        }
    }

    var locale: Locale {
        switch self {
        case .system: Locale.current
        case .zhHans: Locale(identifier: "zh-Hans")
        case .en: Locale(identifier: "en")
        }
    }

    /// AppleLanguages identifier for UserDefaults
    var appleLanguageId: String? {
        switch self {
        case .system: nil
        case .zhHans: "zh-Hans"
        case .en: "en"
        }
    }
}

@MainActor
final class LanguageManager: ObservableObject {
    @Published var selectedLanguage: AppLanguage {
        didSet {
            UserDefaults.standard.set(selectedLanguage.rawValue, forKey: "app_language")
            applyAppleLanguages()
        }
    }

    var currentLocale: Locale {
        selectedLanguage.locale
    }

    init() {
        let saved = UserDefaults.standard.string(forKey: "app_language") ?? "system"
        self.selectedLanguage = AppLanguage(rawValue: saved) ?? .system
    }

    /// Persist language to AppleLanguages so String(localized:) picks it up
    private func applyAppleLanguages() {
        if let langId = selectedLanguage.appleLanguageId {
            UserDefaults.standard.set([langId], forKey: "AppleLanguages")
        } else {
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        }
    }

    /// Restart app to apply language change system-wide
    func restartToApplyLanguage() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            Process.launchedProcess(launchPath: "/usr/bin/open", arguments: ["-n", Bundle.main.bundlePath])
            NSApp.terminate(nil)
        }
    }
}
