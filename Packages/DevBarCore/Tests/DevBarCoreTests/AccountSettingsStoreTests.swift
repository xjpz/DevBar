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

@Test
func providerAccountsMigrateLegacyConfigsToStableIDs() {
    let suiteName = "DevBarCoreTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)

    let store = UserDefaultsAccountSettingsStore(defaults: defaults)
    store.saveAccountConfigs([
        AccountConfig(provider: .glm, isEnabled: true, order: 0),
        AccountConfig(provider: .openai, isEnabled: true, order: 1),
    ])

    let accounts = store.loadProviderAccounts()

    #expect(accounts.first(where: { $0.provider == .glm })?.id == "legacy-glm")
    #expect(accounts.first(where: { $0.provider == .openai })?.id == "legacy-openai")
    #expect(accounts.first(where: { $0.provider == .deepseek })?.isEnabled == false)
}

@Test
func providerAccountsAllowMultipleAccountsForSameProvider() {
    let suiteName = "DevBarCoreTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)

    let store = UserDefaultsAccountSettingsStore(defaults: defaults)
    store.saveProviderAccounts([
        ProviderAccount(id: "openai-a", provider: .openai, displayName: "OpenAI A", isEnabled: true, order: 0),
        ProviderAccount(id: "openai-b", provider: .openai, displayName: "OpenAI B", isEnabled: true, order: 1),
    ])

    let accounts = store.loadProviderAccounts()
    let openAIAccounts = accounts.filter { $0.provider == .openai }

    #expect(openAIAccounts.map(\.id).contains("openai-a"))
    #expect(openAIAccounts.map(\.id).contains("openai-b"))
}

@Test
func providerAccountsPersistCredentialSyncPolicy() {
    let suiteName = "DevBarCoreTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)

    let store = UserDefaultsAccountSettingsStore(defaults: defaults)
    store.saveProviderAccounts([
        ProviderAccount(
            id: "openai-primary",
            provider: .openai,
            displayName: "OpenAI",
            isEnabled: true,
            order: 0,
            syncPolicy: ProviderAccountSyncPolicy(
                quotaSyncEnabled: true,
                credentialSyncEnabled: true
            )
        ),
    ])

    let account = store.loadProviderAccounts()
        .first { $0.id == "openai-primary" }

    #expect(account?.syncPolicy.quotaSyncEnabled == true)
    #expect(account?.syncPolicy.credentialSyncEnabled == true)
}
