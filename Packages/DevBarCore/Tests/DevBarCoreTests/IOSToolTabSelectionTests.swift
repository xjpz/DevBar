import Foundation
import Testing
@testable import DevBarCore

@Test
func iosToolTabSelectionKeepsSavedOrderUpToLimit() {
    let selection = IOSToolTabSelection.resolvedPinnedTabs(
        savedIDs: ["memo", "chatbot-hermes", "qr-code"],
        availableIDs: ["chatbot-hermes", "memo", "qr-code", "webkit"],
        limit: 3
    )

    #expect(selection == ["memo", "chatbot-hermes", "qr-code"])
}

@Test
func iosToolTabSelectionDropsStaleDuplicatesAndOverflow() {
    let selection = IOSToolTabSelection.resolvedPinnedTabs(
        savedIDs: ["legacy", "memo", "memo", "webkit", "chatbot-hermes", "qr-code"],
        availableIDs: ["memo", "webkit", "chatbot-hermes", "qr-code"],
        limit: 3
    )

    #expect(selection == ["memo", "webkit", "chatbot-hermes"])
}

@Test
func iosToolTabSelectionAddsOnlyWhenCapacityRemains() {
    let availableIDs = ["memo", "webkit", "chatbot-hermes", "qr-code"]
    let firstAdd = IOSToolTabSelection.adding(
        "webkit",
        to: ["memo"],
        availableIDs: availableIDs,
        limit: 3
    )
    let fullAdd = IOSToolTabSelection.adding(
        "qr-code",
        to: ["memo", "webkit", "chatbot-hermes"],
        availableIDs: availableIDs,
        limit: 3
    )

    #expect(firstAdd == ["memo", "webkit"])
    #expect(fullAdd == ["memo", "webkit", "chatbot-hermes"])
}

@Test
func iosToolTabSelectionRemovesPinnedID() {
    let selection = IOSToolTabSelection.removing(
        "webkit",
        from: ["memo", "webkit", "chatbot-hermes"]
    )

    #expect(selection == ["memo", "chatbot-hermes"])
}

@Test
func iosToolTabStoreRoundTripsPinnedIDs() {
    let suiteName = "DevBarCoreTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)

    let store = IOSToolTabStore(defaults: defaults)

    store.save(["memo", "webkit", "chatbot-hermes"])

    #expect(store.load() == ["memo", "webkit", "chatbot-hermes"])
}
