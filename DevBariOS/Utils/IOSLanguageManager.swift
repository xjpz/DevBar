import Combine
import Foundation
import SwiftUI

enum IOSAppLanguage: String, CaseIterable, Identifiable {
    case system = "system"
    case zhHans = "zh-Hans"
    case en = "en"

    var id: String { rawValue }

    var locale: Locale {
        switch self {
        case .system:
            Locale.autoupdatingCurrent
        case .zhHans:
            Locale(identifier: "zh-Hans")
        case .en:
            Locale(identifier: "en")
        }
    }

    var appleLanguageId: String? {
        switch self {
        case .system:
            nil
        case .zhHans:
            "zh-Hans"
        case .en:
            "en"
        }
    }
}

@MainActor
final class IOSLanguageManager: ObservableObject {
    @Published var selectedLanguage: IOSAppLanguage {
        didSet {
            UserDefaults.standard.set(selectedLanguage.rawValue, forKey: "app_language")
            applyAppleLanguages()
        }
    }

    var currentLocale: Locale {
        selectedLanguage.locale
    }

    init() {
        let saved = UserDefaults.standard.string(forKey: "app_language") ?? IOSAppLanguage.system.rawValue
        selectedLanguage = IOSAppLanguage(rawValue: saved) ?? .system
        applyAppleLanguages()
    }

    private func applyAppleLanguages() {
        if let langId = selectedLanguage.appleLanguageId {
            UserDefaults.standard.set([langId], forKey: "AppleLanguages")
        } else {
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        }
    }
}
