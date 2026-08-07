import Foundation
import Testing
@testable import DevBarCore

@Test
func quotaResetCountdownUsesDaysAndHoursAtOrAboveOneDay() {
    let now = Date(timeIntervalSince1970: 1_000_000)

    #expect(
        QuotaResetTimePresentation.countdownText(
            until: now.addingTimeInterval((5 * 24 + 8) * 60 * 60),
            now: now
        ) == "5d 8h"
    )
    #expect(
        QuotaResetTimePresentation.countdownText(
            until: now.addingTimeInterval(24 * 60 * 60),
            now: now
        ) == "1d 0h"
    )
}

@Test
func quotaResetCountdownUsesHoursAndMinutesBelowOneDay() {
    let now = Date(timeIntervalSince1970: 1_000_000)

    #expect(
        QuotaResetTimePresentation.countdownText(
            until: now.addingTimeInterval((2 * 60 + 23) * 60),
            now: now
        ) == "2h 23m"
    )
    #expect(
        QuotaResetTimePresentation.countdownText(
            until: now.addingTimeInterval((23 * 60 + 59) * 60),
            now: now
        ) == "23h 59m"
    )
    #expect(QuotaResetTimePresentation.countdownText(until: now.addingTimeInterval(-60), now: now) == "0h 0m")
}

@Test
func quotaResetDateParserResolvesYearlessDatesNearReferenceDate() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .current
    let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 12, day: 31, hour: 23)))

    let parsed = try #require(
        QuotaResetTimePresentation.resetDate(from: "01/01 08:30", relativeTo: now)
    )
    let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: parsed)

    #expect(components.year == 2027)
    #expect(components.month == 1)
    #expect(components.day == 1)
    #expect(components.hour == 8)
    #expect(components.minute == 30)
}

@Test
func quotaResetDisplayTextRespectsSelectedMode() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .current
    let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 7, day: 22, hour: 8)))

    #expect(
        QuotaResetTimePresentation.displayText(
            exactText: "07/22 10:23",
            mode: .exact,
            now: now
        ) == "07/22 10:23"
    )
    #expect(
        QuotaResetTimePresentation.displayText(
            exactText: "07/22 10:23",
            mode: .countdown,
            now: now
        ) == "2h 23m"
    )
}

@Test
func quotaResetDisplayModeMigratesLegacyDefaultsOnlyOnce() throws {
    let legacySuite = "QuotaResetTimePresentationTests.legacy.\(UUID().uuidString)"
    let sharedSuite = "QuotaResetTimePresentationTests.shared.\(UUID().uuidString)"
    let legacyDefaults = try #require(UserDefaults(suiteName: legacySuite))
    let sharedDefaults = try #require(UserDefaults(suiteName: sharedSuite))
    defer {
        legacyDefaults.removePersistentDomain(forName: legacySuite)
        sharedDefaults.removePersistentDomain(forName: sharedSuite)
    }

    legacyDefaults.set(QuotaResetTimeDisplayMode.countdown.rawValue, forKey: QuotaResetTimeDisplayMode.defaultsKey)
    #expect(
        QuotaResetTimeDisplayMode.migrateLegacyValueIfNeeded(
            to: sharedDefaults,
            from: legacyDefaults
        )
    )
    #expect(QuotaResetTimeDisplayMode.stored(in: sharedDefaults) == .countdown)

    sharedDefaults.set(QuotaResetTimeDisplayMode.exact.rawValue, forKey: QuotaResetTimeDisplayMode.defaultsKey)
    #expect(
        !QuotaResetTimeDisplayMode.migrateLegacyValueIfNeeded(
            to: sharedDefaults,
            from: legacyDefaults
        )
    )
    #expect(QuotaResetTimeDisplayMode.stored(in: sharedDefaults) == .exact)
}
