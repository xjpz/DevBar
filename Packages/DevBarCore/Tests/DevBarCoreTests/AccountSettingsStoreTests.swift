import Foundation
import Testing
@testable import DevBarCore

@Test
func accountSettingsStoreRestoresProvidersFromCredentialsWhenDefaultsAreMissing() {
    let suiteName = "DevBarCoreTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)

    let store = UserDefaultsAccountSettingsStore(defaults: defaults)
    let configs = store.loadAccountConfigs(
        restoringEnabledProviders: [.openai, .mimo]
    )

    #expect(configs.first(where: { $0.provider == .glm })?.isEnabled == true)
    #expect(configs.first(where: { $0.provider == .openai })?.isEnabled == true)
    #expect(configs.first(where: { $0.provider == .mimo })?.isEnabled == true)
}

@Test
func accountSettingsStoreRespectsSavedDisabledProviders() {
    let suiteName = "DevBarCoreTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)

    let store = UserDefaultsAccountSettingsStore(defaults: defaults)
    store.saveAccountConfigs([
        AccountConfig(provider: .glm, isEnabled: true, order: 0),
        AccountConfig(provider: .openai, isEnabled: false, order: 1),
        AccountConfig(provider: .mimo, isEnabled: false, order: 2),
    ])

    let configs = store.loadAccountConfigs(
        restoringEnabledProviders: [.openai, .mimo]
    )

    #expect(configs.first(where: { $0.provider == .openai })?.isEnabled == false)
    #expect(configs.first(where: { $0.provider == .mimo })?.isEnabled == false)
}
