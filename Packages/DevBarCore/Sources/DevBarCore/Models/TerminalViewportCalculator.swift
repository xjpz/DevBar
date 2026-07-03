import Foundation

public enum TerminalViewportCalculator {
    public static func columns(
        forWidth width: Double,
        fontSize: Double = 13,
        horizontalPadding: Double = 24
    ) -> Int {
        let characterWidth = fontSize * 0.66
        let usableWidth = max(0, width - horizontalPadding)
        let columns = Int((usableWidth / characterWidth).rounded(.down))
        return min(120, max(24, columns))
    }

    public static func rows(
        forHeight height: Double,
        fontSize: Double = 13,
        verticalPadding: Double = 24
    ) -> Int {
        let lineHeight = fontSize + 3
        let usableHeight = max(0, height - verticalPadding)
        let rows = Int((usableHeight / lineHeight).rounded(.down))
        return min(80, max(12, rows))
    }
}
