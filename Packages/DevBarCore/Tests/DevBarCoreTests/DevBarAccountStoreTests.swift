import Foundation
import Testing
@testable import DevBarCore

@Test
func devBarProfileCacheIsScopedByActiveUser() throws {
    let suite = "DevBarAccountStoreTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let store = DevBarProfileCacheStore(defaults: defaults)
    let first = DevBarUserProfile(
        userId: 101,
        displayName: "Alice",
        displayNameSource: "user",
        profileVersion: 2,
        updatedAt: 1_000
    )
    let second = DevBarUserProfile(
        userId: 202,
        displayName: "Bob",
        displayNameSource: "user",
        profileVersion: 3,
        updatedAt: 2_000
    )

    store.save(first)
    #expect(store.loadActive() == first)
    store.save(second)
    #expect(store.loadActive() == second)
    store.clearActiveUser()
    #expect(store.loadActive() == nil)
}

@Test
func deletingActiveProfileRemovesTheCachedAccountData() throws {
    let suite = "DevBarAccountStoreTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let store = DevBarProfileCacheStore(defaults: defaults)
    let profile = DevBarUserProfile(
        userId: 303,
        displayName: "待注销用户",
        displayNameSource: "user",
        profileVersion: 1,
        updatedAt: 3_000
    )

    store.save(profile)
    store.deleteActiveProfile()

    #expect(store.loadActive() == nil)
    #expect(defaults.data(forKey: DevBarCoreConstants.Defaults.devBarProfileCachePrefix + "303") == nil)
}
