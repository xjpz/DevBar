#if os(iOS)
import DevBarCore
import SwiftUI
import WidgetKit

struct QuotaContributionGrid: View {
    let percentage: Int
    let palette: QuotaInstrumentPalette

    var body: some View {
        GeometryReader { geometry in
            let gap: CGFloat = 3
            let side = min((geometry.size.width - gap * 6) / 7, (geometry.size.height - gap * 3) / 4)
            let filled = WidgetQuotaPresentation.filledSegments(percentage: percentage, count: 28)
            HStack(spacing: gap) {
                ForEach(0..<7) { column in
                    VStack(spacing: gap) {
                        ForEach(0..<4) { row in
                            let index = column * 4 + row
                            RoundedRectangle(cornerRadius: max(2, side * 0.13))
                                .fill(index < filled ? palette.accent.opacity(palette.isFullColor ? 0.60 + Double(row) * 0.13 : 1) : palette.track)
                                .overlay {
                                    if index >= filled {
                                        RoundedRectangle(cornerRadius: max(2, side * 0.13))
                                            .strokeBorder(palette.border, lineWidth: 0.6)
                                    }
                                }
                                .frame(width: max(0, side), height: max(0, side))
                                .widgetAccentable(index < filled)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .aspectRatio(7.0 / 4.0, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

struct QuotaDotMatrix: Shape {
    let text: String
    var lit = true

    private static let glyphs: [Character: [String]] = [
        "0": ["01110", "11011", "11011", "11011", "11011", "11011", "01110"],
        "1": ["01100", "11100", "01100", "01100", "01100", "01100", "11110"],
        "2": ["01110", "11011", "00011", "00110", "01100", "11000", "11111"],
        "3": ["11110", "00011", "00011", "01110", "00011", "00011", "11110"],
        "4": ["00110", "01110", "11010", "11010", "11111", "00011", "00011"],
        "5": ["11111", "11000", "11000", "11110", "00011", "11011", "01110"],
        "6": ["01110", "11000", "11000", "11110", "11011", "11011", "01110"],
        "7": ["11111", "00011", "00110", "00110", "01100", "01100", "01100"],
        "8": ["01110", "11011", "11011", "01110", "11011", "11011", "01110"],
        "9": ["01110", "11011", "11011", "01111", "00011", "00110", "11100"],
        "%": ["11001", "11010", "00010", "00100", "01000", "01011", "10011"]
    ]

    var aspectRatio: CGFloat { CGFloat(max(1, text.count * 6 - 1)) / 7 }

    func path(in rect: CGRect) -> Path {
        let columns = max(1, text.count * 6 - 1)
        let pitch = min(rect.width / CGFloat(columns), rect.height / 7)
        let origin = CGPoint(x: rect.midX - CGFloat(columns) * pitch / 2, y: rect.midY - pitch * 7 / 2)
        var path = Path()
        for (digit, character) in text.enumerated() {
            guard let rows = Self.glyphs[character] else { continue }
            for (row, cells) in rows.enumerated() {
                for (column, value) in cells.enumerated() where (value == "1") == lit {
                    path.addEllipse(in: CGRect(
                        x: origin.x + CGFloat(digit * 6 + column) * pitch + pitch * 0.11,
                        y: origin.y + CGFloat(row) * pitch + pitch * 0.11,
                        width: pitch * 0.78, height: pitch * 0.78
                    ))
                }
            }
        }
        return path
    }
}

struct QuotaSevenSegment: Shape {
    let text: String
    var lit = true

    // A, B, C, D, E, F, G: top, upper-right, lower-right, bottom, lower-left, upper-left, middle.
    private static let digits: [Character: Set<Int>] = [
        "0": [0, 1, 2, 3, 4, 5], "1": [1, 2], "2": [0, 1, 6, 4, 3],
        "3": [0, 1, 2, 3, 6], "4": [5, 6, 1, 2], "5": [0, 5, 6, 2, 3],
        "6": [0, 5, 4, 3, 2, 6], "7": [0, 1, 2],
        "8": [0, 1, 2, 3, 4, 5, 6], "9": [0, 1, 2, 3, 5, 6]
    ]

    var aspectRatio: CGFloat { (CGFloat(max(1, text.count)) * 68 - 10) / 100 }

    func path(in rect: CGRect) -> Path {
        let digitWidth: CGFloat = 58
        let advance: CGFloat = 68
        let width = CGFloat(max(1, text.count)) * advance - 10
        let scale = min(rect.width / width, rect.height / 100)
        let origin = CGPoint(x: rect.midX - width * scale / 2, y: rect.midY - 100 * scale / 2)
        let segments: [CGRect] = [
            CGRect(x: 14, y: 0, width: 30, height: 12),
            CGRect(x: 46, y: 13, width: 12, height: 31),
            CGRect(x: 46, y: 56, width: 12, height: 31),
            CGRect(x: 14, y: 88, width: 30, height: 12),
            CGRect(x: 0, y: 56, width: 12, height: 31),
            CGRect(x: 0, y: 13, width: 12, height: 31),
            CGRect(x: 14, y: 44, width: 30, height: 12)
        ]
        var path = Path()
        for (digit, character) in text.enumerated() {
            guard let active = Self.digits[character] else { continue }
            for (index, segment) in segments.enumerated() where active.contains(index) == lit {
                let transformed = CGRect(
                    x: origin.x + (CGFloat(digit) * advance + segment.minX) * scale,
                    y: origin.y + segment.minY * scale,
                    width: min(digitWidth, segment.width) * scale, height: segment.height * scale
                )
                path.addRoundedRect(in: transformed, cornerSize: CGSize(width: scale * 5.5, height: scale * 5.5))
            }
        }
        return path
    }
}

struct QuotaSegmentProgress: View {
    let percentage: Int
    let round: Bool
    let palette: QuotaInstrumentPalette
    var height: CGFloat = 7

    var body: some View {
        let filled = WidgetQuotaPresentation.filledSegments(percentage: percentage, count: 14)
        GeometryReader { geometry in
            let width = max(0, (geometry.size.width - 13 * 3) / 14)
            let side = min(width, height)
            let spacing = max(0, (geometry.size.width - (round ? side : width) * 14) / 13)
            HStack(spacing: spacing) {
                ForEach(0..<14) { index in
                    RoundedRectangle(cornerRadius: round ? side / 2 : 2)
                        .fill(segmentColor(index: index, filled: filled))
                        .widgetAccentable(index < filled)
                        .frame(width: round ? side : width, height: round ? side : height)
                        .overlay {
                            if index >= filled && (!palette.isFullColor || palette.increasedContrast) {
                                RoundedRectangle(cornerRadius: round ? side / 2 : 2)
                                    .strokeBorder(palette.border, lineWidth: 0.6)
                            }
                        }
                }
            }
            .frame(maxHeight: .infinity)
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }

    private func segmentColor(index: Int, filled: Int) -> Color {
        if index >= filled {
            return round ? palette.accent.opacity(0.15) : palette.track
        }
        return !round && index < filled - 1 ? palette.primary : palette.accent
    }
}
#endif
