import Foundation

public protocol TerminalSecretBackend: Sendable {
    @discardableResult
    func save(key: String, value: String) -> Bool
    func load(key: String) -> String?
    func delete(key: String)
}

public struct KeychainTerminalSecretBackend: TerminalSecretBackend {
    private let keychain: KeychainService

    public init(keychain: KeychainService = .shared) {
        self.keychain = keychain
    }

    @discardableResult
    public func save(key: String, value: String) -> Bool {
        keychain.save(key: key, value: value) == errSecSuccess
    }

    public func load(key: String) -> String? {
        keychain.load(key: key)
    }

    public func delete(key: String) {
        keychain.delete(key: key)
    }
}

public final class InMemoryTerminalSecretBackend: TerminalSecretBackend, @unchecked Sendable {
    private var values: [String: String] = [:]

    public init() {}

    @discardableResult
    public func save(key: String, value: String) -> Bool {
        values[key] = value
        return true
    }

    public func load(key: String) -> String? {
        values[key]
    }

    public func delete(key: String) {
        values.removeValue(forKey: key)
    }
}

public struct TerminalCredentialStore: Sendable {
    private let backend: TerminalSecretBackend

    public init(backend: TerminalSecretBackend = KeychainTerminalSecretBackend()) {
        self.backend = backend
    }

    public func savePassword(_ password: String, serverID: UUID) -> String {
        let key = Self.passwordKey(serverID: serverID)
        backend.save(key: key, value: password)
        return key
    }

    public func savePrivateKey(_ privateKey: String, serverID: UUID) -> String {
        let key = Self.privateKeyKey(serverID: serverID)
        backend.save(key: key, value: privateKey)
        return key
    }

    public func savePrivateKeyPassphrase(_ passphrase: String, serverID: UUID) -> String {
        let key = Self.privateKeyPassphraseKey(serverID: serverID)
        backend.save(key: key, value: passphrase)
        return key
    }

    public func loadSecret(forKey key: String) -> String? {
        backend.load(key: key)
    }

    public func deleteSecrets(serverID: UUID) {
        backend.delete(key: Self.passwordKey(serverID: serverID))
        backend.delete(key: Self.privateKeyKey(serverID: serverID))
        backend.delete(key: Self.privateKeyPassphraseKey(serverID: serverID))
    }

    public static func passwordKey(serverID: UUID) -> String {
        "ios.terminal.server.\(serverID.uuidString.lowercased()).password"
    }

    public static func privateKeyKey(serverID: UUID) -> String {
        "ios.terminal.server.\(serverID.uuidString.lowercased()).privateKey"
    }

    public static func privateKeyPassphraseKey(serverID: UUID) -> String {
        "ios.terminal.server.\(serverID.uuidString.lowercased()).privateKeyPassphrase"
    }
}
