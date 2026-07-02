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
    #expect(settings.hermesModel == "")
    #expect(settings.hermesProvider == "")
    #expect(settings.isStreamingEnabled)
    #expect(settings.normalizedChatTabProvider == .hermes)
    #expect(settings.enabledChatProviders == [.hermes])
    #expect(settings.toolsChatProviders.isEmpty)
}

@Test
func hermesSettingsStoreRoundTripsValues() throws {
    let suiteName = "DevBarCoreTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defaults.removePersistentDomain(forName: suiteName)
    let store = UserDefaultsHermesSettingsStore(defaults: defaults)
    let settings = HermesSettings(
        apiBaseURL: "https://hermes.example.com/v1",
        hermesModel: "mimo-v2.5-pro-ultraspeed",
        hermesProvider: "xiaomi",
        isStreamingEnabled: false,
        chatTabProvider: .hermes,
        hermesChatRemark: "小奕",
        hermesChatTag: "Hermes"
    )

    store.save(settings)

    #expect(store.load() == settings)
}

@Test
func hermesSettingsStoreNormalizesDisabledTabProvider() throws {
    let suiteName = "DevBarCoreTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defaults.removePersistentDomain(forName: suiteName)
    let store = UserDefaultsHermesSettingsStore(defaults: defaults)
    defaults.set("customProvider", forKey: DevBarCoreConstants.Defaults.hermesChatTabProviderKey)

    let loaded = store.load()
    #expect(loaded.normalizedChatTabProvider == .hermes)
    #expect(loaded.chatTabProvider == .hermes)
    #expect(loaded.toolsChatProviders.isEmpty)
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

@Test
func hermesQuickStartItemsDefaultToProvidedItemsWhenMissing() throws {
    let suiteName = "DevBarCoreTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defaults.removePersistentDomain(forName: suiteName)
    let store = UserDefaultsHermesSettingsStore(defaults: defaults)
    let defaultItems = [
        HermesQuickStartItem(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            title: "Fix error",
            subtitle: "Paste logs",
            systemImage: "exclamationmark.magnifyingglass",
            prompt: "Fix this error"
        )
    ]

    #expect(store.loadQuickStartItems(defaults: defaultItems) == defaultItems)
}

@Test
func hermesQuickStartItemsRoundTripNormalizedValues() throws {
    let suiteName = "DevBarCoreTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defaults.removePersistentDomain(forName: suiteName)
    let store = UserDefaultsHermesSettingsStore(defaults: defaults)
    let validID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
    let items = [
        HermesQuickStartItem(
            id: validID,
            title: "  Plan task  ",
            subtitle: "  Step by step  ",
            systemImage: "  ",
            prompt: "  Make a plan  "
        ),
        HermesQuickStartItem(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
            title: "No prompt",
            subtitle: "",
            systemImage: "checklist",
            prompt: "   "
        )
    ]

    store.saveQuickStartItems(items)

    #expect(
        store.loadQuickStartItems(defaults: []) == [
            HermesQuickStartItem(
                id: validID,
                title: "Plan task",
                subtitle: "Step by step",
                systemImage: "sparkles",
                prompt: "Make a plan"
            )
        ]
    )
}

@Test
func hermesQuickStartItemsResetRestoresProvidedDefaults() throws {
    let suiteName = "DevBarCoreTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defaults.removePersistentDomain(forName: suiteName)
    let store = UserDefaultsHermesSettingsStore(defaults: defaults)
    let defaultItems = [
        HermesQuickStartItem(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000004")!,
            title: "Default",
            subtitle: "",
            systemImage: "sparkles",
            prompt: "Default prompt"
        )
    ]

    store.saveQuickStartItems([])
    #expect(store.loadQuickStartItems(defaults: defaultItems).isEmpty)

    store.resetQuickStartItems()

    #expect(store.loadQuickStartItems(defaults: defaultItems) == defaultItems)
}
