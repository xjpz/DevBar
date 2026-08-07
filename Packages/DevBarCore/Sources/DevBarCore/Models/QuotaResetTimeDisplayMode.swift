import Foundation

public enum QuotaResetTimeDisplayMode: String, CaseIterable, Codable, Identifiable, Sendable {
    case exact
    case countdown

    public static let defaultsKey = "quota_reset_time_display_mode"

    public static var sharedDefaults: UserDefaults? {
        UserDefaults(suiteName: DevBarCoreConstants.AppGroup.groupID)
    }

    public var id: String { rawValue }

    public static func stored(in defaults: UserDefaults?) -> Self {
        guard let rawValue = defaults?.string(forKey: defaultsKey) else { return .exact }
        return Self(rawValue: rawValue) ?? .exact
    }

    @discardableResult
    public static func migrateLegacyValueIfNeeded(
        to sharedDefaults: UserDefaults?,
        from legacyDefaults: UserDefaults = .standard
    ) -> Bool {
        guard let sharedDefaults,
              sharedDefaults.object(forKey: defaultsKey) == nil,
              let legacyRawValue = legacyDefaults.string(forKey: defaultsKey),
              Self(rawValue: legacyRawValue) != nil else {
            return false
        }
        sharedDefaults.set(legacyRawValue, forKey: defaultsKey)
        return true
    }
}

public enum QuotaResetTimePresentation {
    public static func displayText(
        exactText: String,
        mode: QuotaResetTimeDisplayMode,
        now: Date = Date()
    ) -> String {
        guard mode == .countdown,
              let resetDate = resetDate(from: exactText, relativeTo: now) else {
            return exactText
        }
        return countdownText(until: resetDate, now: now)
    }

    public static func countdownText(until resetDate: Date, now: Date = Date()) -> String {
        let totalMinutes = max(0, Int(resetDate.timeIntervalSince(now) / 60))

        if totalMinutes >= 24 * 60 {
            let days = totalMinutes / (24 * 60)
            let hours = totalMinutes % (24 * 60) / 60
            return "\(days)d \(hours)h"
        }

        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        return "\(hours)h \(minutes)m"
    }

    public static func resetDate(from text: String, relativeTo now: Date = Date()) -> Date? {
        let formatsWithYear = [
            "yyyy/M/d HH:mm",
            "yyyy/MM/dd HH:mm",
            "yyyy-MM-dd HH:mm",
        ]
        for format in formatsWithYear {
            if let date = dateFormatter(format: format).date(from: text) {
                return date
            }
        }

        let formatsWithoutYear = [
            "M/d HH:mm",
            "MM/dd HH:mm",
            "M-d HH:mm",
            "MM-dd HH:mm",
        ]
        for format in formatsWithoutYear {
            guard let parsed = dateFormatter(format: format).date(from: text) else { continue }
            return dateNearest(to: now, matching: parsed)
        }
        return nil
    }

    private static func dateFormatter(format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .current
        formatter.dateFormat = format
        formatter.isLenient = false
        return formatter
    }

    private static func dateNearest(to now: Date, matching dateWithoutYear: Date) -> Date? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let components = calendar.dateComponents([.month, .day, .hour, .minute], from: dateWithoutYear)
        let currentYear = calendar.component(.year, from: now)

        return [currentYear - 1, currentYear, currentYear + 1]
            .compactMap { year -> Date? in
                var datedComponents = components
                datedComponents.year = year
                return calendar.date(from: datedComponents)
            }
            .min { abs($0.timeIntervalSince(now)) < abs($1.timeIntervalSince(now)) }
    }
}
