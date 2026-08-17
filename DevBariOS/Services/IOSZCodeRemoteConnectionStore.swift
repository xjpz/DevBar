import Combine
import Foundation
import Security

/// 存储单条 zcode 远控连接地址（v1 不做多桌面管理）。
/// 连接地址自带远控授权，只进 Keychain；不落 UserDefaults / SwiftData / iCloud。
final class IOSZCodeRemoteConnectionStore: ObservableObject {
    @Published private(set) var connectionURLString: String?

    private enum KeychainKeys {
        static let service = "com.devbar.zcode.remote"
        static let account = "connection-url"
    }

    init() {
        connectionURLString = Self.load()
    }

    func save(_ urlString: String) {
        Self.delete()
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: KeychainKeys.service,
            kSecAttrAccount: KeychainKeys.account,
            kSecValueData: Data(urlString.utf8),
            kSecAttrAccessible: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { return }
        connectionURLString = urlString
    }

    func clear() {
        Self.delete()
        connectionURLString = nil
    }

    private static func load() -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: KeychainKeys.service,
            kSecAttrAccount: KeychainKeys.account,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        guard let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func delete() {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: KeychainKeys.service,
            kSecAttrAccount: KeychainKeys.account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
