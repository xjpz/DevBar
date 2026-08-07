import Foundation
import Security

public protocol DevBarSessionStoring: Sendable {
    func loadToken() -> String?
    @discardableResult func saveToken(_ token: String) -> Bool
    func clearToken()
}

public struct KeychainDevBarSessionStore: DevBarSessionStoring {
    public init() {}
    public func loadToken() -> String? {
        KeychainService.shared.load(key: DevBarCoreConstants.Keychain.devBarAppSessionTokenKey)
    }
    @discardableResult public func saveToken(_ token: String) -> Bool {
        KeychainService.shared.save(key: DevBarCoreConstants.Keychain.devBarAppSessionTokenKey, value: token) == errSecSuccess
    }
    public func clearToken() {
        KeychainService.shared.delete(key: DevBarCoreConstants.Keychain.devBarAppSessionTokenKey)
    }
}

public struct DevBarProfileCacheStore {
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func save(_ profile: DevBarUserProfile) {
        guard let data = try? JSONEncoder().encode(profile) else { return }
        defaults.set(data, forKey: cacheKey(profile.userId))
        defaults.set(profile.userId, forKey: DevBarCoreConstants.Defaults.devBarActiveUserIDKey)
    }

    public func loadActive() -> DevBarUserProfile? {
        let userId = (defaults.object(forKey: DevBarCoreConstants.Defaults.devBarActiveUserIDKey) as? NSNumber)?.int64Value ?? 0
        guard userId > 0,
              let data = defaults.data(forKey: cacheKey(userId)) else { return nil }
        return try? JSONDecoder().decode(DevBarUserProfile.self, from: data)
    }

    public func clearActiveUser() {
        defaults.removeObject(forKey: DevBarCoreConstants.Defaults.devBarActiveUserIDKey)
    }

    private func cacheKey(_ userId: Int64) -> String {
        DevBarCoreConstants.Defaults.devBarProfileCachePrefix + String(userId)
    }
}
