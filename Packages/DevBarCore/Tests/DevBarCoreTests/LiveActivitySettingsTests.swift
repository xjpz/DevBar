import Foundation
import Testing
@testable import DevBarCore

@Test
func liveActivitySettingsDefaultToDisabledNineToSix() {
    let settings = LiveActivitySettings.defaults

    #expect(!settings.isEnabled)
    #expect(settings.startHour == 9)
    #expect(settings.startMinute == 0)
    #expect(settings.endHour == 18)
    #expect(settings.endMinute == 0)
    #expect(settings.isValidTimeRange)
}

@Test
func liveActivitySettingsDetectDisplayWindow() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!

    let settings = LiveActivitySettings(
        isEnabled: true,
        startHour: 9,
        startMinute: 0,
        endHour: 18,
        endMinute: 0
    )

    let inside = try #require(calendar.date(from: DateComponents(year: 2026, month: 5, day: 16, hour: 12)))
    let before = try #require(calendar.date(from: DateComponents(year: 2026, month: 5, day: 16, hour: 8, minute: 59)))
    let after = try #require(calendar.date(from: DateComponents(year: 2026, month: 5, day: 16, hour: 18)))

    #expect(settings.isWithinDisplayWindow(now: inside, calendar: calendar))
    #expect(!settings.isWithinDisplayWindow(now: before, calendar: calendar))
    #expect(!settings.isWithinDisplayWindow(now: after, calendar: calendar))
}

@Test
func liveActivitySettingsRejectCrossDayWindow() {
    let settings = LiveActivitySettings(
        isEnabled: true,
        startHour: 18,
        startMinute: 0,
        endHour: 9,
        endMinute: 0
    )

    #expect(!settings.isValidTimeRange)
    #expect(!settings.isWithinDisplayWindow())
}

@Test
func liveActivitySettingsStoreRoundTrips() {
    let suiteName = "DevBarCoreTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)

    let store = LiveActivitySettingsStore(defaults: defaults)
    let settings = LiveActivitySettings(
        isEnabled: true,
        startHour: 10,
        startMinute: 30,
        endHour: 17,
        endMinute: 45
    )

    store.save(settings)
    #expect(store.load() == settings)
}
