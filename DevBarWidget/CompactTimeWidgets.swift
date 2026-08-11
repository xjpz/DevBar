import AppIntents
import SwiftUI
import WidgetKit

struct CompactTimeEntry: TimelineEntry {
    let date: Date
}

enum CompactTimeWidgetVariant {
    case timeA
    case timeB
    case timeC
}

enum CompactTimeTextColorSelection: String, AppEnum {
    case automatic
    case white
    case black
    case silver
    case warmWhite

    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "时间文字颜色")
    }

    static var caseDisplayRepresentations: [CompactTimeTextColorSelection: DisplayRepresentation] {
        [
            .automatic: DisplayRepresentation(title: "自动"),
            .white: DisplayRepresentation(title: "白色"),
            .black: DisplayRepresentation(title: "黑色"),
            .silver: DisplayRepresentation(title: "银色"),
            .warmWhite: DisplayRepresentation(title: "暖白")
        ]
    }
}

enum CompactTimeAccentColorSelection: String, AppEnum {
    case automatic
    case blue
    case cyan
    case orange
    case champagne
    case matchText

    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "时间强调色")
    }

    static var caseDisplayRepresentations: [CompactTimeAccentColorSelection: DisplayRepresentation] {
        [
            .automatic: DisplayRepresentation(title: "自动"),
            .blue: DisplayRepresentation(title: "蓝色"),
            .cyan: DisplayRepresentation(title: "青色"),
            .orange: DisplayRepresentation(title: "橙色"),
            .champagne: DisplayRepresentation(title: "香槟金"),
            .matchText: DisplayRepresentation(title: "跟随文字")
        ]
    }
}

struct CompactTimeAppearance {
    let textColorSelection: CompactTimeTextColorSelection
    let accentColorSelection: CompactTimeAccentColorSelection

    static let automatic = CompactTimeAppearance(
        textColorSelection: .automatic,
        accentColorSelection: .automatic
    )

    func textColor(for visualStyle: WidgetVisualStyle) -> Color {
        switch textColorSelection {
        case .automatic:
            switch visualStyle {
            case .transparent, .liquidGlass, .dark:
                return .white
            }
        case .white:
            return .white
        case .black:
            return Color(red: 0.04, green: 0.045, blue: 0.055)
        case .silver:
            return Color(red: 0.82, green: 0.86, blue: 0.91)
        case .warmWhite:
            return Color(red: 1, green: 0.96, blue: 0.88)
        }
    }

    func accentColor(
        for variant: CompactTimeWidgetVariant,
        textColor: Color
    ) -> Color {
        switch accentColorSelection {
        case .automatic:
            switch variant {
            case .timeA:
                return Color(red: 0.16, green: 0.52, blue: 1)
            case .timeB:
                return Color(red: 0.70, green: 0.88, blue: 1)
            case .timeC:
                return Color(red: 1, green: 0.78, blue: 0.48)
            }
        case .blue:
            return Color(red: 0.16, green: 0.52, blue: 1)
        case .cyan:
            return Color(red: 0.22, green: 0.86, blue: 0.95)
        case .orange:
            return Color(red: 0.98, green: 0.55, blue: 0.12)
        case .champagne:
            return Color(red: 1, green: 0.78, blue: 0.48)
        case .matchText:
            return textColor
        }
    }
}

struct CompactTimeWidgetView: View {
    let entry: CompactTimeEntry
    let variant: CompactTimeWidgetVariant
    let visualStyle: WidgetVisualStyle
    let appearance: CompactTimeAppearance

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)

            Group {
                switch variant {
                case .timeA:
                    timeA(side: side)
                case .timeB:
                    timeB(side: side)
                case .timeC:
                    timeC(side: side)
                }
            }
            .frame(width: side, height: side)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .shadow(color: shadowColor, radius: 1, y: 1)
        }
    }

    private var primaryColor: Color {
        appearance.textColor(for: visualStyle)
    }

    private var accentColor: Color {
        appearance.accentColor(for: variant, textColor: primaryColor)
    }

    private var shadowColor: Color {
        switch appearance.textColorSelection {
        case .black:
            return .white.opacity(0.12)
        default:
            return .black.opacity(visualStyle == .dark ? 0.2 : 0.3)
        }
    }

    private func timeA(side: CGFloat) -> some View {
        let timeSize = min(48, max(36, side * 0.35))
        let dateSize = min(21, max(16, side * 0.145))
        let weekdaySize = min(20, max(16, side * 0.14))

        return VStack(spacing: 0) {
            Text(Self.timeFormatter.string(from: entry.date))
                .font(.system(size: timeSize, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(primaryColor)
                .lineLimit(1)
                .minimumScaleFactor(0.82)

            Rectangle()
                .fill(primaryColor.opacity(0.22))
                .frame(width: side * 0.84, height: 1)
                .padding(.top, side * 0.065)
                .padding(.bottom, side * 0.052)

            Text(Self.dateFormatter.string(from: entry.date))
                .font(.system(size: dateSize, weight: .regular, design: .rounded))
                .foregroundStyle(primaryColor.opacity(0.86))
                .lineLimit(1)

            Text(Self.weekdayFormatter.string(from: entry.date))
                .font(.system(size: weekdaySize, weight: .semibold, design: .rounded))
                .foregroundStyle(accentColor)
                .lineLimit(1)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func timeB(side: CGFloat) -> some View {
        let timeSize = min(49, max(36, side * 0.32))
        let dateSize = min(15, max(11, side * 0.088))
        let centerGap = side * 0.10

        return VStack(spacing: 0) {
            ZStack {
                HStack(spacing: 0) {
                    timePart(Self.hourFormatter.string(from: entry.date), size: timeSize)
                    Color.clear.frame(width: centerGap)
                    timePart(Self.minuteFormatter.string(from: entry.date), size: timeSize)
                }

                Rectangle()
                    .fill(primaryColor.opacity(0.20))
                    .frame(width: 1, height: side * 0.52)

                Text(":")
                    .font(.system(size: side * 0.18, weight: .semibold, design: .rounded))
                    .foregroundStyle(accentColor)
            }
            .frame(height: side * 0.61)

            Spacer(minLength: side * 0.02)

            HStack(spacing: side * 0.055) {
                Text(Self.dateFormatter.string(from: entry.date))
                Rectangle()
                    .fill(primaryColor.opacity(0.42))
                    .frame(width: side * 0.12, height: 1)
                Text(Self.weekdayFormatter.string(from: entry.date))
            }
            .font(.system(size: dateSize, weight: .semibold, design: .rounded))
            .foregroundStyle(accentColor)
            .lineLimit(1)
            .minimumScaleFactor(0.82)
        }
        .padding(.vertical, side * 0.06)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func timeC(side: CGFloat) -> some View {
        let timeSize = min(55, max(42, side * 0.36))
        let dateSize = min(18, max(14, side * 0.122))
        let weekdaySize = min(13, max(10, side * 0.086))
        let railWidth = side * 0.31

        return HStack(spacing: side * 0.055) {
            ZStack {
                VStack(spacing: -side * 0.035) {
                    Text(Self.hourFormatter.string(from: entry.date))
                    Text(Self.minuteFormatter.string(from: entry.date))
                }
                .font(.system(size: timeSize, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(primaryColor)
                .lineLimit(1)
                .minimumScaleFactor(0.82)

                Text(":")
                    .font(.system(size: side * 0.145, weight: .semibold, design: .rounded))
                    .foregroundStyle(accentColor)
                    .offset(x: side * 0.20)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Rectangle()
                .fill(accentColor.opacity(0.92))
                .frame(width: 1, height: side * 0.80)

            VStack(alignment: .leading, spacing: side * 0.045) {
                Text(Self.monthFormatter.string(from: entry.date))
                Text(Self.dayFormatter.string(from: entry.date))

                Rectangle()
                    .fill(primaryColor.opacity(0.32))
                    .frame(width: railWidth * 0.64, height: 1)

                Text(Self.weekdayFormatter.string(from: entry.date))
                    .font(.system(size: weekdaySize, weight: .semibold, design: .rounded))
                    .fixedSize()
            }
            .font(.system(size: dateSize, weight: .semibold, design: .rounded))
            .foregroundStyle(accentColor)
            .frame(width: railWidth, alignment: .leading)
        }
        .padding(.horizontal, side * 0.015)
        .padding(.vertical, side * 0.055)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func timePart(_ value: String, size: CGFloat) -> some View {
        Text(value)
            .font(.system(size: size, weight: .medium, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(primaryColor)
            .lineLimit(1)
            .minimumScaleFactor(0.78)
            .frame(maxWidth: .infinity)
    }

    private static func formatter(_ format: String, locale: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: locale)
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = format
        return formatter
    }

    private static let timeFormatter = formatter("HH:mm", locale: "en_US_POSIX")
    private static let hourFormatter = formatter("HH", locale: "en_US_POSIX")
    private static let minuteFormatter = formatter("mm", locale: "en_US_POSIX")
    private static let dateFormatter = formatter("M月d日", locale: "zh_CN")
    private static let monthFormatter = formatter("M月", locale: "zh_CN")
    private static let dayFormatter = formatter("d日", locale: "zh_CN")
    private static let weekdayFormatter = formatter("EEEE", locale: "zh_CN")
}
