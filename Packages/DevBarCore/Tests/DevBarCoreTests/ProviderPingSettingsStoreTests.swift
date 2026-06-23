import Foundation
import Testing
@testable import DevBarCore

@Test
func providerPingSettingsStoreLoadsDefaultGLMConfig() throws {
    let suiteName = "DevBarCoreTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defaults.removePersistentDomain(forName: suiteName)

    let store = UserDefaultsProviderPingSettingsStore(defaults: defaults)
    let configs = store.loadProviderPingConfigs()

    #expect(configs == [.defaultGLM])
}

@Test
func providerPingSettingsStoreNormalizesInvalidTimeAndKeepsFutureConfigs() throws {
    let suiteName = "DevBarCoreTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defaults.removePersistentDomain(forName: suiteName)

    let store = UserDefaultsProviderPingSettingsStore(defaults: defaults)
    let configs = [
        ProviderPingConfig(provider: .mimo, isEnabled: true, hour: 8, minute: 30),
        ProviderPingConfig(provider: .glm, isEnabled: true, hour: 99, minute: -1),
    ]

    store.saveProviderPingConfigs(configs)
    let loaded = store.loadProviderPingConfigs()

    let glm = try #require(loaded.first { $0.provider == .glm })
    let mimo = try #require(loaded.first { $0.provider == .mimo })

    #expect(glm.hour == 10)
    #expect(glm.minute == 0)
    #expect(mimo.hour == 8)
    #expect(mimo.minute == 30)
}
