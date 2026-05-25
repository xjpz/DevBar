import Foundation
import Security

public struct DeviceRelayStore: @unchecked Sendable {
    private let defaults: UserDefaults
    private let keychain: KeychainService

    public init(
        defaults: UserDefaults = .standard,
        keychain: KeychainService = .shared
    ) {
        self.defaults = defaults
        self.keychain = keychain
    }

    public func loadDeviceID(for type: DeviceRelayDeviceType) -> String? {
        defaults.string(forKey: deviceIDKey(for: type))
    }

    public func loadOrCreateDeviceID(for type: DeviceRelayDeviceType) -> String {
        if let existing = loadDeviceID(for: type), !existing.isEmpty {
            return existing
        }
        let id = "\(type.rawValue)-\(UUID().uuidString.lowercased())"
        defaults.set(id, forKey: deviceIDKey(for: type))
        return id
    }

    public func loadOrCreateDeviceSecret(for type: DeviceRelayDeviceType) -> String {
        let key = deviceSecretKey(for: type)
        if let existing = keychain.load(key: key), !existing.isEmpty {
            return existing
        }
        let secret = "drs_\(randomToken())"
        keychain.save(key: key, value: secret)
        return secret
    }

    public func saveDeviceToken(_ token: String) {
        keychain.save(key: DevBarCoreConstants.Keychain.relayDeviceTokenKey, value: token)
        defaults.set(token, forKey: DevBarCoreConstants.Defaults.relayDeviceTokenKey)
    }

    public func loadDeviceToken() -> String? {
        keychain.load(key: DevBarCoreConstants.Keychain.relayDeviceTokenKey) ??
            defaults.string(forKey: DevBarCoreConstants.Defaults.relayDeviceTokenKey)
    }

    public func clearDeviceToken() {
        keychain.delete(key: DevBarCoreConstants.Keychain.relayDeviceTokenKey)
        defaults.removeObject(forKey: DevBarCoreConstants.Defaults.relayDeviceTokenKey)
    }

    public func saveLocalPairSecret(_ secret: String, peerDeviceID: String) {
        guard !secret.isEmpty else { return }
        keychain.save(key: localPairSecretKey(peerDeviceID: peerDeviceID), value: secret)
    }

    public func loadLocalPairSecret(peerDeviceID: String) -> String? {
        keychain.load(key: localPairSecretKey(peerDeviceID: peerDeviceID))
    }

    public func clearLocalPairSecret(peerDeviceID: String) {
        keychain.delete(key: localPairSecretKey(peerDeviceID: peerDeviceID))
    }

    public func savePendingLocalPairSecret(_ secret: String, pairCode: String) {
        guard !secret.isEmpty else { return }
        keychain.save(key: pendingLocalPairSecretKey(pairCode: pairCode), value: secret)
    }

    public func loadPendingLocalPairSecret(pairCode: String) -> String? {
        keychain.load(key: pendingLocalPairSecretKey(pairCode: pairCode))
    }

    public func clearPendingLocalPairSecret(pairCode: String) {
        keychain.delete(key: pendingLocalPairSecretKey(pairCode: pairCode))
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
