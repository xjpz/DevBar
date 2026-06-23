import Foundation
import Testing
@testable import DevBarCore

@Test
func hermesSettingsDefaultToEmptyBaseURLAndStreamingEnabled() throws {
    let suiteName = "DevBarCoreTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defaults.removePersistentDomain(forName: suiteName)

    let store = UserDefaultsHermesSettingsStore(defaults: defaults)
    let settings = store.load()

    #expect(settings.apiBaseURL == "")
    #expect(settings.isStreamingEnabled)
}

@Test
func hermesSettingsStoreRoundTripsValues() throws {
    let suiteName = "DevBarCoreTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defaults.removePersistentDomain(forName: suiteName)
    let store = UserDefaultsHermesSettingsStore(defaults: defaults)
    let settings = HermesSettings(
        apiBaseURL: "https://hermes.example.com/v1",
        isStreamingEnabled: false
    )

    store.save(settings)

    #expect(store.load() == settings)
}

@Test
func iosWebKitTabVisibilityDefaultsToEnabledAndRoundTrips() throws {
    let suiteName = "DevBarCoreTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defaults.removePersistentDomain(forName: suiteName)
    let store = UserDefaultsHermesSettingsStore(defaults: defaults)

    #expect(store.loadWebKitTabEnabled())

    store.saveWebKitTabEnabled(false)

    #expect(!store.loadWebKitTabEnabled())
}
