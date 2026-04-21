// AuthService.swift
// DevBar

import Foundation

final class AuthService {
    private(set) var isLoggedIn = false
    private(set) var credentials: AuthCredentials?

    private let keychain = KeychainService.shared

    init() {
        // Restore saved credentials on launch
        credentials = keychain.loadCredentials()
        isLoggedIn = credentials.map { !$0.token.isEmpty } ?? false
        if !isLoggedIn {
            credentials = nil
            keychain.clear()
        }
    }

    func saveCredentials(_ credentials: AuthCredentials) {
        self.credentials = credentials
        self.isLoggedIn = true
        keychain.save(credentials: credentials)
    }

    deinit {
        print("[DevBar] AuthService DEINIT")
    }

    func logout() {
        credentials = nil
        isLoggedIn = false
        keychain.delete(key: Constants.Keychain.tokenKey)
        keychain.delete(key: Constants.Keychain.cookieKey)
        // Clear browser cookies so re-login requires actual authentication
        if let url = URL(string: "https://bigmodel.cn") {
            let cookies = HTTPCookieStorage.shared.cookies(for: url) ?? []
            for cookie in cookies {
                HTTPCookieStorage.shared.deleteCookie(cookie)
            }
        }
    }
}
