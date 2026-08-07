import Foundation
import Security

protocol DeviceRelaySecureStoring: Sendable {
    func string(forKey key: String) -> String?

    @discardableResult
    func setString(_ value: String, forKey key: String) -> Bool

    func removeValue(forKey key: String)
}

public final class KeychainService: Sendable {
    public static let shared = KeychainService()

    public init() {}

    @discardableResult
    public func save(credentials: AuthCredentials) -> Bool {
        let tokenStatus = save(key: DevBarCoreConstants.Keychain.tokenKey, value: credentials.token)
        let cookieStatus = save(key: DevBarCoreConstants.Keychain.cookieKey, value: credentials.cookieString)
        let didSave = tokenStatus == errSecSuccess && cookieStatus == errSecSuccess
        if !didSave {
            delete(key: DevBarCoreConstants.Keychain.tokenKey)
            delete(key: DevBarCoreConstants.Keychain.cookieKey)
        }
        return didSave
    }

    public func loadCredentials() -> AuthCredentials? {
        guard let token = load(key: DevBarCoreConstants.Keychain.tokenKey),
              let cookieString = load(key: DevBarCoreConstants.Keychain.cookieKey) else {
            return nil
        }
        return AuthCredentials(token: token, cookieString: cookieString)
    }

    public func clear() {
        delete(key: DevBarCoreConstants.Keychain.tokenKey)
        delete(key: DevBarCoreConstants.Keychain.cookieKey)
        delete(key: DevBarCoreConstants.Keychain.glmAPIKeyKey)
        delete(key: DevBarCoreConstants.Keychain.openAIAccessTokenKey)
        delete(key: DevBarCoreConstants.Keychain.mimoServiceTokenKey)
    }

    @discardableResult
    public func saveProviderCredential(_ credential: ProviderCredentialEnvelope, for account: ProviderAccount) -> Bool {
        guard let data = try? JSONEncoder().encode(credential),
              let value = String(data: data, encoding: .utf8) else {
            return false
        }
        return save(key: account.credentialRef.keychainAccount, value: value) == errSecSuccess
    }

    public func loadProviderCredential(for account: ProviderAccount) -> ProviderCredentialEnvelope? {
        guard let value = load(key: account.credentialRef.keychainAccount),
              let data = value.data(using: .utf8) else {
            return nil
        }
        return try? JSONDecoder().decode(ProviderCredentialEnvelope.self, from: data)
    }

    public func deleteProviderCredential(for account: ProviderAccount) {
        delete(key: account.credentialRef.keychainAccount)
    }

    public func migrateLegacyCredentialIfNeeded(for account: ProviderAccount) {
        guard loadProviderCredential(for: account) == nil else { return }

        let credential: ProviderCredentialEnvelope?
        switch account.provider {
        case .glm:
            credential = loadCredentials().map {
                ProviderCredentialEnvelope(
                    accountID: account.id,
                    provider: .glm,
                    token: $0.token,
                    cookieString: $0.cookieString
                )
            }
        case .openai:
            credential = load(key: DevBarCoreConstants.Keychain.openAIAccessTokenKey).map {
                ProviderCredentialEnvelope(
                    accountID: account.id,
                    provider: .openai,
                    token: $0,
                    accountIdentifier: UserDefaults.standard.string(forKey: DevBarCoreConstants.OpenAI.accountIdKey)
                )
            }
        case .mimo:
            credential = load(key: DevBarCoreConstants.Keychain.mimoServiceTokenKey).map {
                ProviderCredentialEnvelope(
                    accountID: account.id,
                    provider: .mimo,
                    cookieString: $0
                )
            }
        case .deepseek:
            credential = nil
        }

        if let credential, credential.hasCredential {
            _ = saveProviderCredential(credential, for: account)
        }
    }

    @discardableResult
    public func save(key: String, value: String) -> OSStatus {
        guard let data = value.data(using: .utf8) else {
            print("[KeychainService] Failed to encode value for account \(key)")
            return errSecParam
        }

        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: DevBarCoreConstants.Keychain.service,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: DevBarCoreConstants.Keychain.service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        if status != errSecSuccess {
            print("[KeychainService] Failed to save account \(key): \(status)")
        }
        return status
    }

    public func load(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: DevBarCoreConstants.Keychain.service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        guard status == errSecSuccess, let data = item as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    public func delete(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: DevBarCoreConstants.Keychain.service,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

extension KeychainService: DeviceRelaySecureStoring {
    func string(forKey key: String) -> String? {
        load(key: key)
    }

    @discardableResult
    func setString(_ value: String, forKey key: String) -> Bool {
        save(key: key, value: value) == errSecSuccess
    }

    func removeValue(forKey key: String) {
        delete(key: key)
    }
}
