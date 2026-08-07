import Foundation
import Testing
@testable import DevBarCore

@Test
func relayDeviceIDMigratesFromUserDefaultsToKeychain() {
    let context = makeStoreContext()
    defer { context.cleanup() }
    let expectedID = "iphone-11111111-1111-1111-1111-111111111111"
    context.defaults.set(expectedID, forKey: DevBarCoreConstants.Defaults.relayIPhoneDeviceIDKey)

    let resolution = context.store.resolveOrCreateDeviceID(for: .iPhone)

    #expect(resolution == DeviceRelayIdentityResolution(
        deviceID: expectedID,
        source: .userDefaultsMigration
    ))
    #expect(context.secureStore.string(forKey: DevBarCoreConstants.Keychain.iPhoneRelayDeviceIDKey) == expectedID)
}

@Test
func relayDeviceIDSurvivesUserDefaultsRemovalThroughKeychain() {
    let context = makeStoreContext()
    defer { context.cleanup() }
    let expectedID = "iphone-22222222-2222-2222-2222-222222222222"
    context.secureStore.setString(expectedID, forKey: DevBarCoreConstants.Keychain.iPhoneRelayDeviceIDKey)

    let resolution = context.store.resolveOrCreateDeviceID(for: .iPhone)

    #expect(resolution == DeviceRelayIdentityResolution(deviceID: expectedID, source: .keychain))
    #expect(context.defaults.string(forKey: DevBarCoreConstants.Defaults.relayIPhoneDeviceIDKey) == expectedID)
}

@Test
func relayDeviceIDRecoversFromLegacyTokenWhenDefaultsWereRemoved() {
    let context = makeStoreContext()
    defer { context.cleanup() }
    let expectedID = "iphone-33333333-3333-3333-3333-333333333333"
    let token = makeRelayToken(deviceID: expectedID, type: .iPhone)
    context.secureStore.setString("drs_legacy-secret", forKey: DevBarCoreConstants.Keychain.iPhoneRelayDeviceSecretKey)
    context.secureStore.setString(token, forKey: DevBarCoreConstants.Keychain.relayDeviceTokenKey)

    let resolution = context.store.resolveOrCreateDeviceID(for: .iPhone)

    #expect(resolution == DeviceRelayIdentityResolution(deviceID: expectedID, source: .relayTokenRecovery))
    #expect(context.secureStore.string(forKey: DevBarCoreConstants.Keychain.iPhoneRelayDeviceIDKey) == expectedID)
    #expect(context.defaults.string(forKey: DevBarCoreConstants.Defaults.relayIPhoneDeviceIDKey) == expectedID)
    #expect(context.store.loadDeviceToken(for: .iPhone) == token)
}

@Test
func relayDeviceTokenIsRejectedWhenItBelongsToPreviousDeviceID() {
    let context = makeStoreContext()
    defer { context.cleanup() }
    let currentID = "iphone-44444444-4444-4444-4444-444444444444"
    let oldID = "iphone-55555555-5555-5555-5555-555555555555"
    context.defaults.set(currentID, forKey: DevBarCoreConstants.Defaults.relayIPhoneDeviceIDKey)
    context.secureStore.setString(
        makeRelayToken(deviceID: oldID, type: .iPhone),
        forKey: DevBarCoreConstants.Keychain.relayDeviceTokenKey
    )

    #expect(context.store.loadDeviceID(for: .iPhone) == currentID)
    #expect(context.store.loadDeviceToken(for: .iPhone) == nil)
}

@Test
func malformedOrWrongTypeTokenDoesNotRecoverRelayDeviceID() {
    let malformedContext = makeStoreContext()
    defer { malformedContext.cleanup() }
    malformedContext.secureStore.setString(
        "drs_legacy-secret",
        forKey: DevBarCoreConstants.Keychain.iPhoneRelayDeviceSecretKey
    )
    malformedContext.secureStore.setString(
        "drt_v1.not-base64.signature",
        forKey: DevBarCoreConstants.Keychain.relayDeviceTokenKey
    )

    let malformedResolution = malformedContext.store.resolveOrCreateDeviceID(for: .iPhone)

    #expect(malformedResolution.source == .generated)
    #expect(malformedResolution.deviceID.hasPrefix("iphone-"))

    let wrongTypeContext = makeStoreContext()
    defer { wrongTypeContext.cleanup() }
    wrongTypeContext.secureStore.setString(
        "drs_legacy-secret",
        forKey: DevBarCoreConstants.Keychain.iPhoneRelayDeviceSecretKey
    )
    wrongTypeContext.secureStore.setString(
        makeRelayToken(
            deviceID: "mac-66666666-6666-6666-6666-666666666666",
            type: .mac
        ),
        forKey: DevBarCoreConstants.Keychain.relayDeviceTokenKey
    )

    let wrongTypeResolution = wrongTypeContext.store.resolveOrCreateDeviceID(for: .iPhone)

    #expect(wrongTypeResolution.source == .generated)
    #expect(wrongTypeResolution.deviceID.hasPrefix("iphone-"))
}

@Test
func freshRelayDeviceIDIsGeneratedOnceAndMirrored() {
    let context = makeStoreContext()
    defer { context.cleanup() }

    let first = context.store.resolveOrCreateDeviceID(for: .iPhone)
    let second = context.store.resolveOrCreateDeviceID(for: .iPhone)

    #expect(first.source == .generated)
    #expect(second.source == .keychain)
    #expect(second.deviceID == first.deviceID)
    #expect(context.secureStore.string(forKey: DevBarCoreConstants.Keychain.iPhoneRelayDeviceIDKey) == first.deviceID)
    #expect(context.defaults.string(forKey: DevBarCoreConstants.Defaults.relayIPhoneDeviceIDKey) == first.deviceID)
}

@Test
func relayDeviceTokenSaveRequiresMatchingIdentity() {
    let context = makeStoreContext()
    defer { context.cleanup() }
    let currentID = "iphone-77777777-7777-7777-7777-777777777777"
    let otherID = "iphone-88888888-8888-8888-8888-888888888888"

    let saved = context.store.saveDeviceToken(
        makeRelayToken(deviceID: otherID, type: .iPhone),
        for: .iPhone,
        deviceID: currentID
    )

    #expect(!saved)
    #expect(context.secureStore.string(forKey: DevBarCoreConstants.Keychain.relayDeviceTokenKey) == nil)
}

@MainActor
@Test
func relayManagerDoesNotPublishCachedTokenBeforeIdentitySetup() {
    let context = makeStoreContext()
    defer { context.cleanup() }
    let deviceID = "iphone-99999999-9999-9999-9999-999999999999"
    context.secureStore.setString(deviceID, forKey: DevBarCoreConstants.Keychain.iPhoneRelayDeviceIDKey)
    context.secureStore.setString(
        makeRelayToken(deviceID: deviceID, type: .iPhone),
        forKey: DevBarCoreConstants.Keychain.relayDeviceTokenKey
    )

    let manager = DeviceRelayManager(store: context.store)

    #expect(manager.localDeviceID == nil)
    #expect(manager.deviceToken == nil)
}

private struct RelayStoreTestContext {
    let suiteName: String
    let defaults: UserDefaults
    let secureStore: InMemoryDeviceRelaySecureStore
    let store: DeviceRelayStore

    func cleanup() {
        defaults.removePersistentDomain(forName: suiteName)
    }
}

private func makeStoreContext() -> RelayStoreTestContext {
    let suiteName = "cc.xjpz.DevBar.DeviceRelayStoreTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    let secureStore = InMemoryDeviceRelaySecureStore()
    let store = DeviceRelayStore(
        defaults: defaults,
        sharedDefaults: nil,
        secureStore: secureStore,
        diagnostics: NoOpDeviceRelayDiagnosticReporter()
    )
    return RelayStoreTestContext(
        suiteName: suiteName,
        defaults: defaults,
        secureStore: secureStore,
        store: store
    )
}

private final class InMemoryDeviceRelaySecureStore: DeviceRelaySecureStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: String] = [:]

    func string(forKey key: String) -> String? {
        lock.withLock { values[key] }
    }

    @discardableResult
    func setString(_ value: String, forKey key: String) -> Bool {
        lock.withLock { values[key] = value }
        return true
    }

    func removeValue(forKey key: String) {
        _ = lock.withLock { values.removeValue(forKey: key) }
    }
}

private struct NoOpDeviceRelayDiagnosticReporter: DiagnosticReporting {
    func record(_ event: DiagnosticLogEvent) {}
}

private struct TestRelayTokenClaims: Encodable {
    let deviceId: String
    let deviceType: String
    let iat: Int64
}

private func makeRelayToken(deviceID: String, type: DeviceRelayDeviceType) -> String {
    let claims = TestRelayTokenClaims(deviceId: deviceID, deviceType: type.rawValue, iat: 1_785_800_000)
    let data = try! JSONEncoder().encode(claims)
    let payload = data.base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
    return "drt_v1.\(payload).unit-signature"
}
