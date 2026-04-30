import Combine
import SwiftUI
import UIKit

private struct ThemeTokensKey: EnvironmentKey {
    static let defaultValue = IOSThemeTokens.light
}

extension EnvironmentValues {
    var themeTokens: IOSThemeTokens {
        get { self[ThemeTokensKey.self] }
        set { self[ThemeTokensKey.self] = newValue }
    }
}

@MainActor
final class IOSThemeManager: ObservableObject {
    @Published var selectedMode: IOSThemeMode {
        didSet {
            UserDefaults.standard.set(selectedMode.rawValue, forKey: "app_theme_mode")
        }
    }

    @Published var selectedFont: IOSAppFont {
        didSet {
            UserDefaults.standard.set(selectedFont.rawValue, forKey: "app_font_choice")
        }
    }

    @Published var developerGreeting: String {
        didSet {
            UserDefaults.standard.set(developerGreeting, forKey: "app_developer_greeting")
        }
    }

    @Published var systemColorScheme: ColorScheme = .light

    static let defaultGreeting = "Hello, Developer!\nReady to ship some code today?\n>_"

    var resolvedTokens: IOSThemeTokens {
        switch selectedMode {
        case .system:
            switch systemColorScheme {
            case .dark: return .dark.applying(font: selectedFont)
            default: return .light.applying(font: selectedFont)
            }
        case .light: return .light.applying(font: selectedFont)
        case .dark: return .dark.applying(font: selectedFont)
        case .geek: return .geek.applying(font: selectedFont)
        }
    }

    var preferredColorScheme: ColorScheme? {
        switch selectedMode {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        case .geek: return .dark
        }
    }

    init() {
        let saved = UserDefaults.standard.string(forKey: "app_theme_mode") ?? IOSThemeMode.system.rawValue
        selectedMode = IOSThemeMode(rawValue: saved) ?? .system
        let savedFont = UserDefaults.standard.string(forKey: "app_font_choice") ?? IOSAppFont.system.rawValue
        selectedFont = IOSAppFont(rawValue: savedFont) ?? .system
        developerGreeting = UserDefaults.standard.string(forKey: "app_developer_greeting") ?? Self.defaultGreeting
    }

    func updateBarAppearance() {
        let tokens = resolvedTokens
        let bgColor = tokens.uiBackgroundPrimary
        let primaryText = UIColor(tokens.textPrimary)

        let standardAppearance = UINavigationBarAppearance()
        standardAppearance.configureWithOpaqueBackground()
        standardAppearance.backgroundColor = bgColor
        standardAppearance.shadowColor = .clear
        standardAppearance.shadowImage = UIImage()
        standardAppearance.titleTextAttributes = [
            .foregroundColor: primaryText,
            .font: tokens.appFont.uiFont(textStyle: .headline, weight: .semibold, monospaced: tokens.isGeek),
        ]
        standardAppearance.largeTitleTextAttributes = [
            .foregroundColor: primaryText,
            .font: tokens.appFont.uiFont(textStyle: .largeTitle, weight: .bold, monospaced: tokens.isGeek),
        ]

        let scrollEdgeAppearance = UINavigationBarAppearance()
        scrollEdgeAppearance.configureWithTransparentBackground()
        scrollEdgeAppearance.backgroundColor = .clear
        scrollEdgeAppearance.shadowColor = .clear
        scrollEdgeAppearance.shadowImage = UIImage()
        scrollEdgeAppearance.titleTextAttributes = [
            .foregroundColor: primaryText,
            .font: tokens.appFont.uiFont(textStyle: .headline, weight: .semibold, monospaced: tokens.isGeek),
        ]
        scrollEdgeAppearance.largeTitleTextAttributes = [
            .foregroundColor: primaryText,
            .font: tokens.appFont.uiFont(textStyle: .largeTitle, weight: .bold, monospaced: tokens.isGeek),
        ]

        UINavigationBar.appearance().standardAppearance = standardAppearance
        UINavigationBar.appearance().scrollEdgeAppearance = scrollEdgeAppearance
        UINavigationBar.appearance().compactAppearance = standardAppearance
        UINavigationBar.appearance().prefersLargeTitles = true
        UINavigationBar.appearance().tintColor = primaryText

        let tabAppearance = UITabBarAppearance()
        tabAppearance.configureWithOpaqueBackground()
        tabAppearance.backgroundColor = bgColor
        UITabBar.appearance().standardAppearance = tabAppearance
        UITabBar.appearance().scrollEdgeAppearance = tabAppearance
    }
}
