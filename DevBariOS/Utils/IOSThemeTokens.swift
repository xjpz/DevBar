import SwiftUI

enum IOSThemeMode: String, CaseIterable, Identifiable {
    case system
    case light
    case dark
    case geek

    var id: String { rawValue }
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
        isGeek ? .system(.body, design: .monospaced) : .body
    }

    var bodyMonoFont: Font {
        isGeek ? .system(.body, design: .monospaced) : .system(.body, design: .monospaced)
    }

    var subheadlineFont: Font {
        isGeek ? .system(.subheadline, design: .monospaced) : .subheadline
    }

    var subheadlineWeightFont: Font {
        isGeek ? .system(.subheadline, design: .monospaced).weight(.medium) : .subheadline.weight(.medium)
    }

    var captionFont: Font {
        isGeek ? .system(.caption, design: .monospaced) : .caption
    }

    var captionWeightFont: Font {
        isGeek ? .system(.caption, design: .monospaced).weight(.medium) : .caption.weight(.medium)
    }

    var caption2Font: Font {
        isGeek ? .system(.caption2, design: .monospaced) : .caption2
    }

    var footnoteFont: Font {
        isGeek ? .system(.footnote, design: .monospaced) : .footnote
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
        isGeek: false
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
        isGeek: false
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
        isGeek: true
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
