import Foundation

public struct LiveActivitySettings: Codable, Equatable, Sendable {
    public var isEnabled: Bool
    public var startHour: Int
    public var startMinute: Int
    public var endHour: Int
    public var endMinute: Int

    public static let defaults = LiveActivitySettings(
        isEnabled: false,
        startHour: 9,
        startMinute: 0,
        endHour: 18,
        endMinute: 0
    )

    public init(
        isEnabled: Bool,
        startHour: Int,
        startMinute: Int,
        endHour: Int,
        endMinute: Int
    ) {
        self.isEnabled = isEnabled
        self.startHour = startHour
        self.startMinute = startMinute
        self.endHour = endHour
        self.endMinute = endMinute
    }

    public var isValidTimeRange: Bool {
        minutesOfDay(hour: startHour, minute: startMinute) < minutesOfDay(hour: endHour, minute: endMinute)
    }

    public func isWithinDisplayWindow(now: Date = Date(), calendar: Calendar = .current) -> Bool {
        guard isEnabled, let window = displayWindow(containing: now, calendar: calendar) else {
            return false
        }
        return now >= window.start && now < window.end
    }

    public func displayWindow(containing date: Date = Date(), calendar: Calendar = .current) -> (start: Date, end: Date)? {
        guard isValidTimeRange else { return nil }

        var startComponents = calendar.dateComponents([.year, .month, .day], from: date)
        startComponents.hour = clampedHour(startHour)
        startComponents.minute = clampedMinute(startMinute)
        startComponents.second = 0

        var endComponents = calendar.dateComponents([.year, .month, .day], from: date)
        endComponents.hour = clampedHour(endHour)
        endComponents.minute = clampedMinute(endMinute)
        endComponents.second = 0

        guard let start = calendar.date(from: startComponents),
              let end = calendar.date(from: endComponents),
              start < end else {
            return nil
        }

        return (start, end)
    }

    private func minutesOfDay(hour: Int, minute: Int) -> Int {
        clampedHour(hour) * 60 + clampedMinute(minute)
    }

    private func clampedHour(_ value: Int) -> Int {
        min(max(value, 0), 23)
    }

    private func clampedMinute(_ value: Int) -> Int {
        min(max(value, 0), 59)
    }
}
