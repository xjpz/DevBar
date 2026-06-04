import Foundation

public final class AuthService {
    public private(set) var isLoggedIn = false
    public private(set) var credentials: AuthCredentials?

    private let keychain = KeychainService.shared

    public init() {
        credentials = keychain.loadCredentials()
        isLoggedIn = credentials.map { !$0.token.isEmpty } ?? false
        if !isLoggedIn {
            credentials = nil
            keychain.delete(key: DevBarCoreConstants.Keychain.tokenKey)
            keychain.delete(key: DevBarCoreConstants.Keychain.cookieKey)
        }
    }

    @discardableResult
    public func saveCredentials(_ credentials: AuthCredentials) -> Bool {
        guard keychain.save(credentials: credentials) else {
            return false
        }
        self.credentials = credentials
        self.isLoggedIn = true
        return true
    }

    public func logout() {
        credentials = nil
        isLoggedIn = false
        keychain.delete(key: DevBarCoreConstants.Keychain.tokenKey)
        keychain.delete(key: DevBarCoreConstants.Keychain.cookieKey)
        if let url = URL(string: "https://bigmodel.cn") {
            let cookies = HTTPCookieStorage.shared.cookies(for: url) ?? []
            for cookie in cookies {
                HTTPCookieStorage.shared.deleteCookie(cookie)
            }
        }
    }
}
