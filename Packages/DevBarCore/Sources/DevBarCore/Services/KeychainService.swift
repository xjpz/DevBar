import Foundation
import Security

public final class KeychainService: Sendable {
    public static let shared = KeychainService()

    public init() {}

    public func save(credentials: AuthCredentials) {
        save(key: DevBarCoreConstants.Keychain.tokenKey, value: credentials.token)
        save(key: DevBarCoreConstants.Keychain.cookieKey, value: credentials.cookieString)
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
        delete(key: DevBarCoreConstants.Keychain.openAIAccessTokenKey)
        delete(key: DevBarCoreConstants.Keychain.mimoServiceTokenKey)
    }

    public func save(key: String, value: String) {
        guard let data = value.data(using: .utf8) else { return }

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
        SecItemAdd(addQuery as CFDictionary, nil)
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
