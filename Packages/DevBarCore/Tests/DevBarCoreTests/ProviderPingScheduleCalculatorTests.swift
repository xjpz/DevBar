import Foundation
import Testing
@testable import DevBarCore

@Test
func providerPingScheduleWaitsUntilTodaysTime() throws {
    let calculator = ProviderPingScheduleCalculator()
    let calendar = testCalendar()
    let now = try testDate("2026-06-19 09:30:00")
    let expectedFireDate = try testDate("2026-06-19 10:00:00")
    let config = ProviderPingConfig(provider: .glm, isEnabled: true, hour: 10, minute: 0)

    #expect(!calculator.shouldRunAutomaticPing(for: config, now: now, calendar: calendar))
    #expect(calculator.nextFireDate(for: config, now: now, calendar: calendar) == expectedFireDate)
}

@Test
func providerPingScheduleRunsMissedPingOnceToday() throws {
    let calculator = ProviderPingScheduleCalculator()
    let calendar = testCalendar()
    let now = try testDate("2026-06-19 10:05:00")
    let config = ProviderPingConfig(provider: .glm, isEnabled: true, hour: 10, minute: 0)

    #expect(calculator.shouldRunAutomaticPing(for: config, now: now, calendar: calendar))
    #expect(calculator.todayKey(now: now, calendar: calendar) == "2026-06-19")
}

@Test
func providerPingScheduleSkipsAfterAutomaticRunForToday() throws {
    let calculator = ProviderPingScheduleCalculator()
    let calendar = testCalendar()
    let now = try testDate("2026-06-19 15:00:00")
    let expectedFireDate = try testDate("2026-06-20 10:00:00")
    let config = ProviderPingConfig(
        provider: .glm,
        isEnabled: true,
        hour: 10,
        minute: 0,
        lastAutomaticRunDay: "2026-06-19"
    )

    #expect(!calculator.shouldRunAutomaticPing(for: config, now: now, calendar: calendar))
    #expect(calculator.nextFireDate(for: config, now: now, calendar: calendar) == expectedFireDate)
}

@Test
func providerPingScheduleAllowsNextDayRun() throws {
    let calculator = ProviderPingScheduleCalculator()
    let calendar = testCalendar()
    let now = try testDate("2026-06-20 10:01:00")
    let config = ProviderPingConfig(
        provider: .glm,
        isEnabled: true,
        hour: 10,
        minute: 0,
        lastAutomaticRunDay: "2026-06-19"
    )

    #expect(calculator.shouldRunAutomaticPing(for: config, now: now, calendar: calendar))
}

private func testCalendar() -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    return calendar
}

private func testDate(_ value: String) throws -> Date {
    let formatter = DateFormatter()
    formatter.calendar = testCalendar()
    formatter.timeZone = TimeZone(secondsFromGMT: 0)!
    formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
    return try #require(formatter.date(from: value))
}
