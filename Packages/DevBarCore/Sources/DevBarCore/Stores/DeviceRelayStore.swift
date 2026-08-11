import Crypto
import Foundation
import Security

enum DeviceRelayIdentityResolutionSource: String, Sendable {
    case keychain
    case userDefaultsMigration = "user_defaults_migration"
    case relayTokenRecovery = "relay_token_recovery"
    case generated
}

struct DeviceRelayIdentityResolution: Sendable, Equatable {
    let deviceID: String
    let source: DeviceRelayIdentityResolutionSource
}

private struct DeviceRelayTokenClaims: Decodable {
    let deviceId: String
    let deviceType: String
}

public struct DeviceRelayStore: @unchecked Sendable {
    private let defaults: UserDefaults
    private let sharedDefaults: UserDefaults?
    private let secureStore: any DeviceRelaySecureStoring
    private let diagnostics: any DiagnosticReporting

    public init(
        defaults: UserDefaults = .standard,
        sharedDefaults: UserDefaults? = UserDefaults(suiteName: DevBarCoreConstants.AppGroup.groupID),
        keychain: KeychainService = .shared,
        diagnostics: any DiagnosticReporting = DiagnosticLogger.shared
    ) {
        self.defaults = defaults
        self.sharedDefaults = sharedDefaults
        self.secureStore = keychain
        self.diagnostics = diagnostics
    }

    init(
        defaults: UserDefaults,
        sharedDefaults: UserDefaults?,
        secureStore: any DeviceRelaySecureStoring,
        diagnostics: any DiagnosticReporting
    ) {
        self.defaults = defaults
        self.sharedDefaults = sharedDefaults
        self.secureStore = secureStore
        self.diagnostics = diagnostics
    }

    public func loadDeviceID(for type: DeviceRelayDeviceType) -> String? {
        (try? resolveExistingDeviceID(for: type))?.deviceID
    }

    public func loadOrCreateDeviceID(for type: DeviceRelayDeviceType) throws -> String {
        try resolveOrCreateDeviceID(for: type).deviceID
    }

    func resolveOrCreateDeviceID(for type: DeviceRelayDeviceType) throws -> DeviceRelayIdentityResolution {
        if let existing = try resolveExistingDeviceID(for: type) {
            logIdentityResolution(existing, type: type)
            return existing
        }

        let id = "\(type.rawValue)-\(UUID().uuidString.lowercased())"
        try persistDeviceID(id, for: type)
        let resolution = DeviceRelayIdentityResolution(deviceID: id, source: .generated)
        logIdentityResolution(resolution, type: type)
        return resolution
    }

    public func loadOrCreateDeviceSecret(for type: DeviceRelayDeviceType) throws -> String {
        let key = deviceSecretKey(for: type)
        if let existing = secureStore.string(forKey: key), !existing.isEmpty {
            return existing
        }
        let secret = "drs_\(randomToken())"
        guard secureStore.setString(secret, forKey: key),
              secureStore.string(forKey: key) == secret else {
            secureStore.removeValue(forKey: key)
            throw DeviceRelayError.secureStorageUnavailable
        }
        return secret
    }

    @discardableResult
    public func saveDeviceToken(
        _ token: String,
        for type: DeviceRelayDeviceType,
        deviceID: String
    ) -> Bool {
        guard let claims = Self.decodeTokenClaims(token) else {
            logTokenRejection(type: type, deviceID: deviceID, reason: "invalid_format")
            return false
        }
        guard claims.deviceType == type.rawValue, claims.deviceId == deviceID else {
            logTokenRejection(type: type, deviceID: deviceID, reason: "identity_mismatch")
            return false
        }

        return persistDeviceToken(token)
    }

    public func loadDeviceToken(for type: DeviceRelayDeviceType) -> String? {
        guard let deviceID = loadDeviceID(for: type) else { return nil }
        let candidates = deviceTokenCandidates()

        for token in candidates {
            guard let claims = Self.decodeTokenClaims(token),
                  claims.deviceType == type.rawValue,
                  claims.deviceId == deviceID else {
                continue
            }
            guard persistDeviceToken(token) else { return nil }
            return token
        }

        if !candidates.isEmpty {
            logTokenRejection(type: type, deviceID: deviceID, reason: "cached_identity_mismatch")
        }
        return nil
    }

    public func clearDeviceToken() {
        secureStore.removeValue(forKey: DevBarCoreConstants.Keychain.relayDeviceTokenKey)
        defaults.removeObject(forKey: DevBarCoreConstants.Defaults.relayDeviceTokenKey)
        sharedDefaults?.removeObject(forKey: DevBarCoreConstants.Defaults.relayDeviceTokenKey)
    }

    @discardableResult
    public func saveLocalPairSecret(_ secret: String, peerDeviceID: String) -> Bool {
        guard !secret.isEmpty else { return false }
        let key = localPairSecretKey(peerDeviceID: peerDeviceID)
        guard secureStore.setString(secret, forKey: key),
              secureStore.string(forKey: key) == secret else {
            secureStore.removeValue(forKey: key)
            return false
        }
        return true
    }

    public func loadLocalPairSecret(peerDeviceID: String) -> String? {
        secureStore.string(forKey: localPairSecretKey(peerDeviceID: peerDeviceID))
    }

    public func clearLocalPairSecret(peerDeviceID: String) {
        secureStore.removeValue(forKey: localPairSecretKey(peerDeviceID: peerDeviceID))
    }

    @discardableResult
    public func savePendingLocalPairSecret(_ secret: String, pairCode: String) -> Bool {
        guard !secret.isEmpty else { return false }
        let key = pendingLocalPairSecretKey(pairCode: pairCode)
        guard secureStore.setString(secret, forKey: key),
              secureStore.string(forKey: key) == secret else {
            secureStore.removeValue(forKey: key)
            return false
        }
        return true
    }

    public func loadPendingLocalPairSecret(pairCode: String) -> String? {
        secureStore.string(forKey: pendingLocalPairSecretKey(pairCode: pairCode))
    }

    public func clearPendingLocalPairSecret(pairCode: String) {
        secureStore.removeValue(forKey: pendingLocalPairSecretKey(pairCode: pairCode))
    }

    public func resetIdentity(
        for type: DeviceRelayDeviceType,
        knownPeerIDs: Set<String>,
        pendingPairCode: String?
    ) throws {
        clearDeviceToken()
        secureStore.removeValue(forKey: keychainDeviceIDKey(for: type))
        secureStore.removeValue(forKey: deviceSecretKey(for: type))
        defaults.removeObject(forKey: deviceIDKey(for: type))

        for peerDeviceID in knownPeerIDs {
            clearLocalPairSecret(peerDeviceID: peerDeviceID)
        }
        if let pendingPairCode {
            clearPendingLocalPairSecret(pairCode: pendingPairCode)
        }

        guard secureStore.string(forKey: DevBarCoreConstants.Keychain.relayDeviceTokenKey) == nil,
              secureStore.string(forKey: keychainDeviceIDKey(for: type)) == nil,
              secureStore.string(forKey: deviceSecretKey(for: type)) == nil,
              knownPeerIDs.allSatisfy({
                  secureStore.string(forKey: localPairSecretKey(peerDeviceID: $0)) == nil
              }),
              pendingPairCode.map({
                  secureStore.string(forKey: pendingLocalPairSecretKey(pairCode: $0)) == nil
              }) ?? true else {
            throw DeviceRelayError.secureStorageUnavailable
        }
    }

    private func resolveExistingDeviceID(
        for type: DeviceRelayDeviceType
    ) throws -> DeviceRelayIdentityResolution? {
        if let keychainID = normalizedDeviceID(
            secureStore.string(forKey: keychainDeviceIDKey(for: type)),
            for: type
        ) {
            defaults.set(keychainID, forKey: deviceIDKey(for: type))
            return DeviceRelayIdentityResolution(deviceID: keychainID, source: .keychain)
        }

        if let defaultsID = normalizedDeviceID(defaults.string(forKey: deviceIDKey(for: type)), for: type) {
            try persistDeviceID(defaultsID, for: type)
            return DeviceRelayIdentityResolution(deviceID: defaultsID, source: .userDefaultsMigration)
        }

        guard secureStore.string(forKey: deviceSecretKey(for: type))?.isEmpty == false else {
            return nil
        }

        for token in deviceTokenCandidates() {
            guard let claims = Self.decodeTokenClaims(token),
                  claims.deviceType == type.rawValue,
                  let recoveredID = normalizedDeviceID(claims.deviceId, for: type) else {
                continue
            }
            try persistDeviceID(recoveredID, for: type)
            return DeviceRelayIdentityResolution(deviceID: recoveredID, source: .relayTokenRecovery)
        }
        return nil
    }

    private func persistDeviceID(_ deviceID: String, for type: DeviceRelayDeviceType) throws {
        let key = keychainDeviceIDKey(for: type)
        guard secureStore.setString(deviceID, forKey: key),
              secureStore.string(forKey: key) == deviceID else {
            secureStore.removeValue(forKey: key)
            throw DeviceRelayError.secureStorageUnavailable
        }
        defaults.set(deviceID, forKey: deviceIDKey(for: type))
    }

    private func persistDeviceToken(_ token: String) -> Bool {
        let key = DevBarCoreConstants.Keychain.relayDeviceTokenKey
        guard secureStore.setString(token, forKey: key),
              secureStore.string(forKey: key) == token else {
            secureStore.removeValue(forKey: key)
            return false
        }
        defaults.set(token, forKey: DevBarCoreConstants.Defaults.relayDeviceTokenKey)
        sharedDefaults?.set(token, forKey: DevBarCoreConstants.Defaults.relayDeviceTokenKey)
        return true
    }

    private func deviceTokenCandidates() -> [String] {
        let candidates = [
            secureStore.string(forKey: DevBarCoreConstants.Keychain.relayDeviceTokenKey),
            defaults.string(forKey: DevBarCoreConstants.Defaults.relayDeviceTokenKey),
            sharedDefaults?.string(forKey: DevBarCoreConstants.Defaults.relayDeviceTokenKey),
        ]
        var seen = Set<String>()
        return candidates.compactMap { candidate in
            guard let candidate, !candidate.isEmpty, seen.insert(candidate).inserted else { return nil }
            return candidate
        }
    }

    private func normalizedDeviceID(_ value: String?, for type: DeviceRelayDeviceType) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty,
              value.hasPrefix("\(type.rawValue)-") else {
            return nil
        }
        return value
    }

    private func logIdentityResolution(
        _ resolution: DeviceRelayIdentityResolution,
        type: DeviceRelayDeviceType
    ) {
        print(
            "[DevBar:DeviceRelayIdentity] Resolved type=\(type.rawValue) " +
                "source=\(resolution.source.rawValue) device=\(Self.fingerprint(resolution.deviceID))"
        )
    }

    private func logTokenRejection(
        type: DeviceRelayDeviceType,
        deviceID: String,
        reason: String
    ) {
        let deviceFingerprint = Self.fingerprint(deviceID)
        print(
            "[DevBar:DeviceRelayIdentity] Rejected relay token for type=\(type.rawValue) " +
                "device=\(deviceFingerprint) reason=\(reason)"
        )
        diagnostics.record(DiagnosticLogEvent(
            level: .warning,
            category: "device.relay.identity",
            name: "relay_token_rejected",
            message: "Cached Relay token rejected because it does not match the resolved identity",
            platform: type == .iPhone ? "ios" : "macos",
            details: [
                "deviceType": type.rawValue,
                "deviceFingerprint": deviceFingerprint,
                "reason": reason,
            ]
        ))
    }

    static func fingerprint(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).prefix(6).map { String(format: "%02x", $0) }.joined()
    }

    private static func decodeTokenClaims(_ token: String) -> DeviceRelayTokenClaims? {
        let components = token.split(separator: ".", omittingEmptySubsequences: false)
        guard components.count == 3, components[0] == "drt_v1" else { return nil }

        var payload = String(components[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let padding = (4 - payload.count % 4) % 4
        payload += String(repeating: "=", count: padding)
        guard let data = Data(base64Encoded: payload) else { return nil }
        return try? JSONDecoder().decode(DeviceRelayTokenClaims.self, from: data)
    }

    private func deviceIDKey(for type: DeviceRelayDeviceType) -> String {
        switch type {
        case .mac:
            return DevBarCoreConstants.Defaults.relayMacDeviceIDKey
        case .iPhone:
            return DevBarCoreConstants.Defaults.relayIPhoneDeviceIDKey
        }
    }

    private func deviceSecretKey(for type: DeviceRelayDeviceType) -> String {
        switch type {
        case .mac:
            return DevBarCoreConstants.Keychain.macRelayDeviceSecretKey
        case .iPhone:
            return DevBarCoreConstants.Keychain.iPhoneRelayDeviceSecretKey
        }
    }

    private func keychainDeviceIDKey(for type: DeviceRelayDeviceType) -> String {
        switch type {
        case .mac:
            return DevBarCoreConstants.Keychain.macRelayDeviceIDKey
        case .iPhone:
            return DevBarCoreConstants.Keychain.iPhoneRelayDeviceIDKey
        }
    }

    private func localPairSecretKey(peerDeviceID: String) -> String {
        DevBarCoreConstants.Keychain.relayLocalPairSecretPrefix + peerDeviceID
    }

    private func pendingLocalPairSecretKey(pairCode: String) -> String {
        DevBarCoreConstants.Keychain.relayPendingLocalPairSecretPrefix + pairCode
    }

    private func randomToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64URLEncodedString()
    }
}
