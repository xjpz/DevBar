import Foundation
import Testing
@testable import DevBarCore

@Test
func iosToolVisibilityResolvesCurrentHiddenIDsWithoutDuplicates() {
    let hiddenIDs = IOSToolVisibility.resolvedHiddenIDs(
        savedHiddenIDs: ["webkit", "legacy", "memo", "webkit"],
        availableIDs: ["memo", "webkit", "terminal"]
    )

    #expect(hiddenIDs == ["webkit", "memo"])
}

@Test
func iosToolVisibilityHideAndShowAreIdempotent() {
    let hiddenOnce = IOSToolVisibility.hiding("memo", in: ["webkit"])
    let hiddenTwice = IOSToolVisibility.hiding("memo", in: hiddenOnce)
    let shownOnce = IOSToolVisibility.showing("memo", in: hiddenTwice)
    let shownTwice = IOSToolVisibility.showing("memo", in: shownOnce)

    #expect(hiddenOnce == ["webkit", "memo"])
    #expect(hiddenTwice == hiddenOnce)
    #expect(shownOnce == ["webkit"])
    #expect(shownTwice == shownOnce)
}

@Test
func iosToolVisibilityKeepsNewToolsVisibleByDefault() {
    let visibleIDs = IOSToolVisibility.visibleIDs(
        orderedIDs: ["memo", "new-tool", "webkit"],
        hiddenIDs: ["memo"]
    )

    #expect(visibleIDs == ["new-tool", "webkit"])
}

@Test
func iosToolVisibilityMergesVisibleOrderWithoutMovingHiddenSlots() {
    let fullOrder = IOSToolVisibility.mergingVisibleOrder(
        ["c", "a", "b"],
        into: ["a", "hidden", "b", "c"],
        hiddenIDs: ["hidden"]
    )

    #expect(fullOrder == ["c", "hidden", "a", "b"])
}

@Test
func iosToolVisibilityMergeIgnoresUnknownAndAppendsOmittedVisibleIDs() {
    let fullOrder = IOSToolVisibility.mergingVisibleOrder(
        ["c", "legacy"],
        into: ["a", "hidden", "b", "c"],
        hiddenIDs: ["hidden"]
    )

    #expect(fullOrder == ["c", "hidden", "a", "b"])
}

@Test
func iosToolVisibilityStoreRoundTripsRawIDs() {
    let suiteName = "DevBarCoreTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let store = IOSToolVisibilityStore(defaults: defaults)
    store.save(["webkit", "currently-unavailable"])

    #expect(store.load() == ["webkit", "currently-unavailable"])
}
