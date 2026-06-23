import Foundation

public struct ProviderPingScheduleCalculator: Sendable {
    public init() {}

    public func todayKey(now: Date, calendar: Calendar = .current) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: now)
        let year = components.year ?? 0
        let month = components.month ?? 0
        let day = components.day ?? 0
        return String(format: "%04d-%02d-%02d", year, month, day)
    }

    public func scheduledDateToday(
        for config: ProviderPingConfig,
        now: Date,
        calendar: Calendar = .current
    ) -> Date? {
        var components = calendar.dateComponents([.year, .month, .day], from: now)
        components.hour = config.hour
        components.minute = config.minute
        components.second = 0
        return calendar.date(from: components)
    }

    public func shouldRunAutomaticPing(
        for config: ProviderPingConfig,
        now: Date,
        calendar: Calendar = .current
    ) -> Bool {
        guard config.isEnabled,
              config.lastAutomaticRunDay != todayKey(now: now, calendar: calendar),
              let scheduled = scheduledDateToday(for: config, now: now, calendar: calendar) else {
            return false
        }
        return now >= scheduled
    }

    public func nextFireDate(
        for config: ProviderPingConfig,
        now: Date,
        calendar: Calendar = .current
    ) -> Date? {
        guard config.isEnabled,
              let scheduledToday = scheduledDateToday(for: config, now: now, calendar: calendar) else {
            return nil
        }

        if now < scheduledToday && config.lastAutomaticRunDay != todayKey(now: now, calendar: calendar) {
            return scheduledToday
        }

        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) else {
            return nil
        }
        return scheduledDateToday(for: config, now: tomorrow, calendar: calendar)
    }
}
