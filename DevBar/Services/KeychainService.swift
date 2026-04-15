// KeychainService.swift
// DevBar

import Foundation
import Security

final class KeychainService: Sendable {
    static let shared = KeychainService()

    private init() {}

    // MARK: - Public API

    func save(credentials: AuthCredentials) {
        save(key: Constants.Keychain.tokenKey, value: credentials.token)
        save(key: Constants.Keychain.cookieKey, value: credentials.cookieString)
    }

    func loadCredentials() -> AuthCredentials? {
        guard let token = load(key: Constants.Keychain.tokenKey),
              let cookieString = load(key: Constants.Keychain.cookieKey)
        else {
            return nil
        }
        return AuthCredentials(
            token: token,
            cookieString: cookieString
        )
    }

    func clear() {
        delete(key: Constants.Keychain.tokenKey)
        delete(key: Constants.Keychain.cookieKey)
    }

    // MARK: - Private Helpers

    private func save(key: String, value: String) {
        guard let data = value.data(using: .utf8) else { return }

        // Delete existing item first
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Constants.Keychain.service,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        // Add new item
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Constants.Keychain.service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        SecItemAdd(addQuery as CFDictionary, nil)
    }

    private func load(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Constants.Keychain.service,
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

    private func delete(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Constants.Keychain.service,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
