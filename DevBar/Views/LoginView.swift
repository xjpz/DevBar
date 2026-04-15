// LoginView.swift
// DevBar

import SwiftUI
import SafariServices

// MARK: - SwiftUI View

struct LoginView: View {
    var isExpired = false
    let onLoginSuccess: (AuthCredentials) -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.crop.circle.badge.questionmark")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)

            Text(isExpired ? "登录已过期" : "未登录")
                .font(.headline)

            Text("点击下方按钮在浏览器中登录 BigModel，登录完成后点击\"已完成登录\"")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button("在浏览器中登录") {
                openLoginInBrowser()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Button("已完成登录") {
                attemptCookieExtraction()
            }
            .buttonStyle(.borderless)
            .font(.caption)
        }
        .padding(32)
        .frame(width: 280)
        .fixedSize()
    }

    private func openLoginInBrowser() {
        NSWorkspace.shared.open(URL(string: Constants.API.loginURL)!)
    }

    /// Attempt to read BigModel cookies from the shared HTTPCookieStorage.
    /// The user must have already logged in via the browser for this to succeed.
    private func attemptCookieExtraction() {
        let cookies = HTTPCookieStorage.shared.cookies(for: URL(string: "https://bigmodel.cn")!) ?? []
        var token = ""
        var cookieParts: [String] = []
        for cookie in cookies {
            cookieParts.append("\(cookie.name)=\(cookie.value)")
            if cookie.name == "bigmodel_token_production" {
                token = cookie.value
            }
        }
        guard !token.isEmpty else {
            print("[DevBar] No bigmodel_token_production cookie found")
            return
        }
        let credentials = AuthCredentials(
            token: token,
            cookieString: cookieParts.joined(separator: "; ")
        )
        onLoginSuccess(credentials)
    }
}
