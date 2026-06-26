import Foundation
import Testing
@testable import DevBarCore

@Test
func iosToolOrderAppliesSavedOrderAndAppendsNewTools() {
    let defaultOrder = ["chat", "api", "formatter", "qr"]
    let savedOrder = ["formatter", "chat"]

    let resolvedOrder = IOSToolOrder.resolvedOrder(savedOrder: savedOrder, defaultOrder: defaultOrder)

    #expect(resolvedOrder == ["formatter", "chat", "api", "qr"])
}

@Test
func iosToolOrderIgnoresStaleAndDuplicateSavedIDs() {
    let defaultOrder = ["chat", "api", "formatter", "qr"]
    let savedOrder = ["legacy", "qr", "api", "qr"]

    let resolvedOrder = IOSToolOrder.resolvedOrder(savedOrder: savedOrder, defaultOrder: defaultOrder)

    #expect(resolvedOrder == ["qr", "api", "chat", "formatter"])
}

@Test
func iosToolOrderMovesItemBeforeDestination() {
    let order = ["chat", "api", "formatter", "qr"]

    let resolvedOrder = IOSToolOrder.moving("qr", before: "api", in: order)

    #expect(resolvedOrder == ["chat", "qr", "api", "formatter"])
}

@Test
func iosToolOrderStoreRoundTrips() {
    let suiteName = "DevBarCoreTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)

    let store = IOSToolOrderStore(defaults: defaults)

    store.save(["qr", "chat", "api"])

    #expect(store.load() == ["qr", "chat", "api"])
}
