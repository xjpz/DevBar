import SwiftUI
import UIKit

enum IOSThemeMode: String, CaseIterable, Identifiable {
    case system
    case light
    case dark
    case geek

    var id: String { rawValue }
}

enum IOSAppFont: String, CaseIterable, Identifiable {
    case system
    case geist
    case geistMono
    case jetBrainsMono

    var id: String { rawValue }

    var titleKey: LocalizedStringKey {
        switch self {
        case .system: return "ios_settings_font_system"
        case .geist: return "ios_settings_font_geist"
        case .geistMono: return "ios_settings_font_geist_mono"
        case .jetBrainsMono: return "ios_settings_font_jetbrains_mono"
        }
    }

    func font(_ style: Font.TextStyle, weight: Font.Weight? = nil, monospaced: Bool = false) -> Font {
        let base: Font
        if let family = fontFamily(monospaced: monospaced) {
            let fontName = uiFontName(family: family, weight: uiWeight(for: weight))
            base = .custom(fontName, size: pointSize(for: style), relativeTo: style)
        } else {
            base = monospaced ? .system(style, design: .monospaced) : .system(style)
        }
        return weight.map { base.weight($0) } ?? base
    }

    func uiFont(textStyle: UIFont.TextStyle, weight: UIFont.Weight = .regular, monospaced: Bool = false) -> UIFont {
        let preferredSize = UIFont.preferredFont(forTextStyle: textStyle).pointSize
        if let family = fontFamily(monospaced: monospaced),
           let font = UIFont(name: uiFontName(family: family, weight: weight), size: preferredSize) ?? UIFont(name: family, size: preferredSize) {
            return UIFontMetrics(forTextStyle: textStyle).scaledFont(for: font)
        }
        if monospaced {
            return UIFontMetrics(forTextStyle: textStyle).scaledFont(
                for: .monospacedSystemFont(ofSize: preferredSize, weight: weight)
            )
        }
        return UIFontMetrics(forTextStyle: textStyle).scaledFont(
            for: .systemFont(ofSize: preferredSize, weight: weight)
        )
    }

    private func fontFamily(monospaced: Bool) -> String? {
        switch self {
        case .system:
            return nil
        case .geist:
            return monospaced ? "Geist Mono" : "Geist"
        case .geistMono:
            return "Geist Mono"
        case .jetBrainsMono:
            return "JetBrains Mono"
        }
    }

    private func uiFontName(family: String, weight: UIFont.Weight) -> String {
        switch family {
        case "Geist":
            if weight.rawValue >= UIFont.Weight.bold.rawValue { return "Geist-Bold" }
            if weight.rawValue >= UIFont.Weight.semibold.rawValue { return "Geist-SemiBold" }
            if weight.rawValue >= UIFont.Weight.medium.rawValue { return "Geist-Medium" }
            return "Geist-Regular"
        case "Geist Mono":
            if weight.rawValue >= UIFont.Weight.bold.rawValue { return "GeistMono-Bold" }
            if weight.rawValue >= UIFont.Weight.medium.rawValue { return "GeistMono-Medium" }
            return "GeistMono-Regular"
        case "JetBrains Mono":
            if weight.rawValue >= UIFont.Weight.bold.rawValue { return "JetBrainsMono-Bold" }
            if weight.rawValue >= UIFont.Weight.medium.rawValue { return "JetBrainsMono-Medium" }
            return "JetBrainsMono-Regular"
        default:
            return family
        }
    }

    private func uiWeight(for weight: Font.Weight?) -> UIFont.Weight {
        switch weight {
        case .bold, .heavy, .black:
            return .bold
        case .semibold:
            return .semibold
        case .medium:
            return .medium
        default:
            return .regular
        }
    }

    private func pointSize(for style: Font.TextStyle) -> CGFloat {
        UIFont.preferredFont(forTextStyle: uiTextStyle(for: style)).pointSize
    }

    private func uiTextStyle(for style: Font.TextStyle) -> UIFont.TextStyle {
        switch style {
        case .largeTitle: return .largeTitle
        case .title: return .title1
        case .title2: return .title2
        case .title3: return .title3
        case .headline: return .headline
        case .subheadline: return .subheadline
        case .callout: return .callout
        case .caption: return .caption1
        case .caption2: return .caption2
        case .footnote: return .footnote
        case .body: return .body
        @unknown default: return .body
        }
    }
}

struct IOSThemeTokens: Equatable {
    let backgroundPrimary: Color
    let backgroundSecondary: Color
    let surfacePrimary: Color
    let surfaceSecondary: Color
    let textPrimary: Color
    let textSecondary: Color
    let textTertiary: Color
    let borderSubtle: Color
    let borderStrong: Color
    let brandPrimary: Color
    let brandSecondary: Color
    let success: Color
    let warning: Color
    let danger: Color
    let info: Color
    let heroGradientStart: Color
    let heroGradientEnd: Color
    let providerPlateOpacity: Double
    let isGeek: Bool
    let appFont: IOSAppFont

    var heroGradient: LinearGradient {
        LinearGradient(
            colors: [heroGradientStart, heroGradientEnd],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    var progressSuccess: Color { success }
    var progressWarning: Color { warning }
    var progressDanger: Color { danger }

    // MARK: - Geek font helpers

    /// Body font: SF Mono in geek mode, system default otherwise
    var bodyFont: Font {
        appFont.font(.body, monospaced: isGeek && appFont == .system)
    }

    var bodyMonoFont: Font {
        appFont.font(.body, monospaced: true)
    }

    var subheadlineFont: Font {
        appFont.font(.subheadline, monospaced: isGeek && appFont == .system)
    }

    var subheadlineWeightFont: Font {
        appFont.font(.subheadline, weight: .medium, monospaced: isGeek && appFont == .system)
    }

    var captionFont: Font {
        appFont.font(.caption, monospaced: isGeek && appFont == .system)
    }

    var captionWeightFont: Font {
        appFont.font(.caption, weight: .medium, monospaced: isGeek && appFont == .system)
    }

    var caption2Font: Font {
        appFont.font(.caption2, monospaced: isGeek && appFont == .system)
    }

    var footnoteFont: Font {
        appFont.font(.footnote, monospaced: isGeek && appFont == .system)
    }

    func applying(font: IOSAppFont) -> IOSThemeTokens {
        IOSThemeTokens(
            backgroundPrimary: backgroundPrimary,
            backgroundSecondary: backgroundSecondary,
            surfacePrimary: surfacePrimary,
            surfaceSecondary: surfaceSecondary,
            textPrimary: textPrimary,
            textSecondary: textSecondary,
            textTertiary: textTertiary,
            borderSubtle: borderSubtle,
            borderStrong: borderStrong,
            brandPrimary: brandPrimary,
            brandSecondary: brandSecondary,
            success: success,
            warning: warning,
            danger: danger,
            info: info,
            heroGradientStart: heroGradientStart,
            heroGradientEnd: heroGradientEnd,
            providerPlateOpacity: providerPlateOpacity,
            isGeek: isGeek,
            appFont: font
        )
    }
}

extension IOSThemeTokens {
    static let light = IOSThemeTokens(
        backgroundPrimary: Color(hex: "F6F7F9"),
        backgroundSecondary: Color(hex: "EEF1F4"),
        surfacePrimary: Color(hex: "FFFFFF"),
        surfaceSecondary: Color(hex: "F2F7F3"),
        textPrimary: Color(hex: "111111"),
        textSecondary: Color(hex: "6B7280"),
        textTertiary: Color(hex: "9CA3AF"),
        borderSubtle: Color(hex: "DCE3E8"),
        borderStrong: Color(hex: "C0C8D0"),
        brandPrimary: Color(hex: "53A567"),
        brandSecondary: Color(hex: "7BC88C"),
        success: Color(hex: "34C759"),
        warning: Color(hex: "FF9F0A"),
        danger: Color(hex: "FF453A"),
        info: Color(hex: "007AFF"),
        heroGradientStart: Color(hex: "FFFFFF"),
        heroGradientEnd: Color(hex: "F2F7F3"),
        providerPlateOpacity: 0.14,
        isGeek: false,
        appFont: .system
    )

    static let dark = IOSThemeTokens(
        backgroundPrimary: Color(hex: "0F1115"),
        backgroundSecondary: Color(hex: "161A20"),
        surfacePrimary: Color(hex: "1B2129"),
        surfaceSecondary: Color(hex: "202833"),
        textPrimary: Color(hex: "F5F7FA"),
        textSecondary: Color(hex: "A9B2BE"),
        textTertiary: Color(hex: "7B8794"),
        borderSubtle: Color(hex: "2B3440"),
        borderStrong: Color(hex: "3A4555"),
        brandPrimary: Color(hex: "62C27A"),
        brandSecondary: Color(hex: "8FE0A3"),
        success: Color(hex: "30D158"),
        warning: Color(hex: "FFD60A"),
        danger: Color(hex: "FF6961"),
        info: Color(hex: "64D2FF"),
        heroGradientStart: Color(hex: "12161C"),
        heroGradientEnd: Color(hex: "0F1115"),
        providerPlateOpacity: 0.16,
        isGeek: false,
        appFont: .system
    )

    static let geek = IOSThemeTokens(
        backgroundPrimary: Color(hex: "0B0F14"),
        backgroundSecondary: Color(hex: "121821"),
        surfacePrimary: Color(hex: "1A2230"),
        surfaceSecondary: Color(hex: "222C3C"),
        textPrimary: Color(hex: "E6EDF3"),
        textSecondary: Color(hex: "9FB3C8"),
        textTertiary: Color(hex: "6B7C93"),
        borderSubtle: Color(hex: "2A3545"),
        borderStrong: Color(hex: "3A4B5E"),
        brandPrimary: Color(hex: "00FF9D"),
        brandSecondary: Color(hex: "00E5FF"),
        success: Color(hex: "00FF9D"),
        warning: Color(hex: "FFD166"),
        danger: Color(hex: "FF5E7E"),
        info: Color(hex: "3DDCFF"),
        heroGradientStart: Color(hex: "121821"),
        heroGradientEnd: Color(hex: "0B0F14"),
        providerPlateOpacity: 0.18,
        isGeek: true,
        appFont: .system
    )
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r, g, b: Double
        (r, g, b) = (
            Double((int >> 16) & 0xFF) / 255,
            Double((int >> 8) & 0xFF) / 255,
            Double(int & 0xFF) / 255
        )
        self.init(.sRGB, red: r, green: g, blue: b, opacity: 1)
    }
}

extension UIColor {
    convenience init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        self.init(
            red: CGFloat((int >> 16) & 0xFF) / 255,
            green: CGFloat((int >> 8) & 0xFF) / 255,
            blue: CGFloat(int & 0xFF) / 255,
            alpha: 1
        )
    }
}

extension IOSThemeTokens {
    var uiBackgroundPrimary: UIColor { .init(hex: backgroundPrimaryHex) }
    var uiBackgroundSecondary: UIColor { .init(hex: backgroundSecondaryHex) }

    private var backgroundPrimaryHex: String {
        switch self {
        case .light: return "F6F7F9"
        case .dark: return "0F1115"
        case .geek: return "0B0F14"
        default: return "F6F7F9"
        }
    }

    private var backgroundSecondaryHex: String {
        switch self {
        case .light: return "EEF1F4"
        case .dark: return "161A20"
        case .geek: return "121821"
        default: return "EEF1F4"
        }
    }
}
