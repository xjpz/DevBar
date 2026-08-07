import DevBarCore
import Foundation

enum QuotaWidgetResetPresentation {
    private static var sharedDefaults: UserDefaults? {
        UserDefaults(suiteName: DevBarCoreConstants.AppGroup.groupID)
    }

    static var displayMode: QuotaResetTimeDisplayMode {
        QuotaResetTimeDisplayMode.stored(in: sharedDefaults)
    }

    static func text(for exactText: String?, at date: Date) -> String? {
        guard let exactText, !exactText.isEmpty else { return nil }
        return QuotaResetTimePresentation.displayText(
            exactText: exactText,
            mode: displayMode,
            now: date
        )
    }

    static func timelineDates(
        from now: Date,
        through nextUpdate: Date,
        limits: [WidgetQuotaLimit]
    ) -> [Date] {
        var dates = [now]

        if displayMode == .countdown,
           limits.contains(where: { QuotaResetTimePresentation.resetDate(from: $0.formattedResetTime ?? "", relativeTo: now) != nil }) {
            var minuteDate = now.addingTimeInterval(60)
            while minuteDate < nextUpdate {
                dates.append(minuteDate)
                minuteDate = minuteDate.addingTimeInterval(60)
            }
        }

        if let earliestReset = limits
            .compactMap({ $0.formattedResetTime })
            .compactMap({ QuotaResetTimePresentation.resetDate(from: $0, relativeTo: now) })
            .filter({ $0 > now && $0 < nextUpdate })
            .min() {
            dates.append(earliestReset)
        }

        return dates
            .reduce(into: [Date]()) { uniqueDates, date in
                if !uniqueDates.contains(where: { abs($0.timeIntervalSince(date)) < 0.5 }) {
                    uniqueDates.append(date)
                }
            }
            .sorted()
    }
}
