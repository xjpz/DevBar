#if os(iOS)
import AppIntents
import DevBarCore
import SwiftUI
import WidgetKit

enum QuotaWidgetStyleSelection: String, AppEnum {
    case classic, github, led, sevenSegment

    var isInstrument: Bool { self == .led || self == .sevenSegment }

    var instrumentBackground: Color {
        self == .led ? .black : Color(white: 0.105)
    }

    static var typeDisplayRepresentation: TypeDisplayRepresentation { .init(name: "额度样式") }
    static var caseDisplayRepresentations: [Self: DisplayRepresentation] {
        [.classic: .init(title: "经典"), .github: .init(title: "GitHub 方格"),
         .led: .init(title: "LED 点阵"), .sevenSegment: .init(title: "数码管")]
    }
}

enum QuotaWidgetPeriodSelection: String, AppEnum {
    case automatic, fiveHour, weekly, monthly

    static var typeDisplayRepresentation: TypeDisplayRepresentation { .init(name: "额度周期") }
    static var caseDisplayRepresentations: [Self: DisplayRepresentation] {
        [.automatic: .init(title: "自动"), .fiveHour: .init(title: "5 小时"),
         .weekly: .init(title: "每周"), .monthly: .init(title: "每月")]
    }

    var period: WidgetQuotaPeriod { WidgetQuotaPeriod(rawValue: rawValue) ?? .automatic }
}

enum QuotaWidgetTextSelection: String, AppEnum {
    case automatic, light, dark

    static var typeDisplayRepresentation: TypeDisplayRepresentation { .init(name: "额度文字颜色") }
    static var caseDisplayRepresentations: [Self: DisplayRepresentation] {
        [.automatic: .init(title: "自动"), .light: .init(title: "浅色"), .dark: .init(title: "深色")]
    }
}

struct QuotaWidgetAppearance {
    var style: QuotaWidgetStyleSelection = .classic
    var period: QuotaWidgetPeriodSelection = .automatic
    var text: QuotaWidgetTextSelection = .automatic

    static let classic = QuotaWidgetAppearance()
}

/// WidgetKit owns the final glass/tinted composition; don't layer app glass effects here.
struct QuotaInstrumentPalette {
    let visualStyle: WidgetVisualStyle
    let textSelection: QuotaWidgetTextSelection
    let renderingMode: WidgetRenderingMode
    let colorScheme: ColorScheme
    let increasedContrast: Bool
    let reduceTransparency: Bool
    let showsContainerBackground: Bool
    var instrumentStyle: QuotaWidgetStyleSelection = .classic

    var isFullColor: Bool { renderingMode == .fullColor }
    var usesLightText: Bool {
        if visualStyle == .dark && showsContainerBackground { return true }
        switch textSelection {
        case .light: return true
        case .dark: return false
        case .automatic: return colorScheme == .dark
        }
    }
    var primary: Color { isFullColor ? (usesLightText ? .white : Color(white: 0.08)) : .primary }
    var secondary: Color {
        if instrumentStyle == .led, isFullColor {
            return accent.opacity(increasedContrast || !usesLightText ? 1 : 0.82)
        }
        return primary.opacity(increasedContrast ? 1 : (instrumentStyle.isInstrument ? 0.72 : 0.82))
    }
    var accent: Color {
        guard isFullColor else { return .primary }
        return usesLightText
            ? Color(red: 0.57, green: 0.91, blue: 0.28)
            : Color(red: 0.06, green: 0.37, blue: 0.17)
    }
    var track: Color { primary.opacity(increasedContrast ? 0.30 : 0.13) }
    var border: Color { primary.opacity(increasedContrast ? 0.65 : 0.32) }
    // Lit segments remain readable without an '888' ghost on busy wallpaper or tinted glass.
    var unlit: Color {
        guard isFullColor, visualStyle == .dark, showsContainerBackground, !increasedContrast else { return .clear }
        return instrumentStyle == .led ? accent.opacity(0.14) : primary.opacity(0.09)
    }
    var shadow: Color {
        guard isFullColor, visualStyle != .dark else { return .clear }
        return (usesLightText ? Color.black : .white).opacity(instrumentStyle.isInstrument ? 0.25 : 0.65)
    }
    var backing: Color {
        guard isFullColor, visualStyle != .dark else { return .clear }
        let opacity = reduceTransparency ? 0.96 : (increasedContrast ? 0.90 : (instrumentStyle.isInstrument ? 0 : 0.16))
        return (usesLightText ? Color.black : .white).opacity(opacity)
    }
}
#endif
