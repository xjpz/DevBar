//
//  LoginView.swift
//  DevBar
//

import SwiftUI
import WebKit

// MARK: - SwiftUI View

struct LoginView: View {
    var isExpired = false
    let onLoginSuccess: (AuthCredentials) -> Void

    @State private var isValidating = false
    @State private var loginError: String?
    @State private var apiKey = ""

    var body: some View {
        VStack(spacing: 16) {

            header

            VStack(spacing: 12) {
                browserLoginSection
                separatorView
                apiKeySection
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(.ultraThinMaterial)
                    .shadow(color: .black.opacity(0.08), radius: 10, y: 4)
            )

            footer
        }
        .padding(20)
        .frame(width: 320)
    }
}

struct DevBarButtonStyle: ButtonStyle {
    var isPrimary: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isPrimary ? Color.accentColor : Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(isPrimary ? Color.clear : Color.gray.opacity(0.3))
                    )
                    .opacity(configuration.isPressed ? 0.85 : 1)
            )
            .foregroundStyle(isPrimary ? .white : .primary)
            .animation(.easeInOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - Header

private extension LoginView {
    var header: some View {
        VStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 52, height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 12))

            Text("DevBar")
                .font(.system(size: 18, weight: .semibold))

            Text("tagline")
                .font(.caption)
                .foregroundStyle(.secondary)

            if isExpired {
                Label("login_expired", systemImage: "clock.badge.exclamationmark")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
        }
    }
}

// MARK: - Sections

private extension LoginView {

    var browserLoginSection: some View {
        VStack(spacing: 10) {

            Text("scan_or_account_login")
                .font(.caption2)
                .foregroundStyle(.secondary)

            Button(action: openLoginWindow) {
                HStack {
                    Image(systemName: "safari")
                    Text("browser_login")
                }
            }
            .buttonStyle(DevBarButtonStyle(isPrimary: apiKey.trimmingCharacters(in: .whitespaces).isEmpty))
        }
    }

    var separatorView: some View {
        HStack {
            Rectangle().frame(height: 0.5).opacity(0.2)

            Text("or")
                .font(.caption2)
                .foregroundStyle(.secondary)

            Rectangle().frame(height: 0.5).opacity(0.2)
        }
    }

    var apiKeySection: some View {
        VStack(spacing: 10) {

//            Text("使用 API Key")
//                .font(.caption2)
//                .foregroundStyle(.secondary)

            SecureField("enter_api_key", text: $apiKey)
                .textFieldStyle(.plain)
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color(NSColor.textBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.gray.opacity(0.2))

                )
                .font(.system(size: 12, design: .monospaced))
                .onSubmit { loginWithApiKey() }

            Button(action: loginWithApiKey) {
                HStack {
                    if isValidating {
                        ProgressView().controlSize(.small)
                    }
                    Text("api_key_login")
                }
            }
            .buttonStyle(DevBarButtonStyle(isPrimary: !apiKey.trimmingCharacters(in: .whitespaces).isEmpty))

            if let error = loginError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .padding(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.red.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
    }

    var footer: some View {
        Text("credentials_local_only")
            .font(.caption2)
            .foregroundStyle(.tertiary)
    }
}

// MARK: - Actions

private extension LoginView {

    func loginWithApiKey() {
        let key = apiKey.trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty else { return }

        loginError = nil
        isValidating = true

        Task { @MainActor in
            let isValid = await validateApiKey(key)
            isValidating = false

            if isValid {
                withAnimation(.spring()) {
                    onLoginSuccess(AuthCredentials(token: key, cookieString: ""))
                }
            } else {
                loginError = String(localized: "api_key_invalid")
            }
        }
    }

    func openLoginWindow() {
        loginError = nil

        let controller = LoginWindowController(
            loginURL: Constants.API.loginURL,
            onCookiesExtracted: { credentials in
                isValidating = true

                Task { @MainActor in
                    let isValid = await validateToken(cookieString: credentials.cookieString)
                    isValidating = false

                    if isValid {
                        withAnimation(.spring()) {
                            onLoginSuccess(credentials)
                        }
                    } else {
                        loginError = String(localized: "token_invalid")
                    }
                }
            }
        )

        controller.show()
    }

    /// Validate API Key
    func validateApiKey(_ key: String) async -> Bool {
        var request = URLRequest(url: URL(string: Constants.API.quotaLimitURL)!)
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 10

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let http = response as? HTTPURLResponse,
                  http.statusCode == 200 else {
                return false
            }

            // 👇 解析 JSON
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let success = json["success"] as? Bool ?? false
                let code = json["code"] as? Int ?? -1

                if success == true || code == 0 {
                    return true
                } else {
                    print("[DevBar] API Key invalid: \(json)")
                    return false
                }
            }

            return false

        } catch {
            print("[DevBar] API Key validation failed: \(error.localizedDescription)")
            return false
        }
    }

    /// Validate Cookie Token
    func validateToken(cookieString: String) async -> Bool {
        var request = URLRequest(url: URL(string: Constants.API.subscriptionListURL)!)
        request.setValue(cookieString, forHTTPHeaderField: "Cookie")
        request.timeoutInterval = 10

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                return true
            }
            return false
        } catch {
            print("[DevBar] Token validation failed: \(error.localizedDescription)")
            return false
        }
    }
}

// MARK: - Web Login

private let loginScriptMessageHandler = "loginDetector"

final class LoginWindowController: NSObject, WKNavigationDelegate, WKScriptMessageHandler {

    private var window: NSWindow?
    private var webView: WKWebView?
    private var pollTimer: Timer?

    private let loginURL: String
    private let onCookiesExtracted: (AuthCredentials) -> Void

    init(loginURL: String, onCookiesExtracted: @escaping (AuthCredentials) -> Void) {
        self.loginURL = loginURL
        self.onCookiesExtracted = onCookiesExtracted
        super.init()
    }

    func show() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()

        let contentController = WKUserContentController()

        let script = WKUserScript(
            source: """
            (function() {
                function checkCookie() {
                    var cookies = document.cookie;
                    if (cookies.indexOf('bigmodel_token_production=') !== -1) {
                        window.webkit.messageHandlers.loginDetector.postMessage('found');
                    }
                }
                setInterval(checkCookie, 1000);
                checkCookie();
            })();
            """,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        )

        contentController.addUserScript(script)
        contentController.add(self, name: loginScriptMessageHandler)
        config.userContentController = contentController

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = self
        self.webView = webView

        let hostingView = NSHostingView(rootView: LoginWebViewWrapper(webView: webView))

        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 700),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )

        win.contentView = hostingView
        win.title = String(localized: "login_bigmodel")
        win.center()
        win.level = .floating
        win.isReleasedWhenClosed = false
        win.makeKeyAndOrderFront(nil)

        NSApp.activate(ignoringOtherApps: true)

        self.window = win

        if let url = URL(string: loginURL) {
            webView.load(URLRequest(url: url))
        }

        pollTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let webView = self.webView else { return }

                let cookies = await webView.configuration.websiteDataStore.httpCookieStore.allCookies()

                if let token = cookies.first(where: { $0.name == "bigmodel_token_production" }),
                   !token.value.isEmpty {
                    self.handleLoginSuccess(token: token.value, cookies: cookies)
                }
            }
        }
    }

    func close() {
        pollTimer?.invalidate()
        pollTimer = nil

        webView?.configuration.userContentController.removeAllUserScripts()
        webView?.stopLoading()

        window?.orderOut(nil)
        window = nil
        webView = nil
    }

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {

        guard message.name == loginScriptMessageHandler else { return }

        Task { @MainActor [weak self] in
            guard let self, let webView = self.webView else { return }

            let cookies = await webView.configuration.websiteDataStore.httpCookieStore.allCookies()

            if let token = cookies.first(where: { $0.name == "bigmodel_token_production" }),
               !token.value.isEmpty {
                self.handleLoginSuccess(token: token.value, cookies: cookies)
            }
        }
    }

    private func handleLoginSuccess(token: String, cookies: [HTTPCookie]) {
        pollTimer?.invalidate()
        pollTimer = nil

        let cookieString = cookies
            .filter { ["bigmodel.cn", ".bigmodel.cn"].contains($0.domain) }
            .map { "\($0.name)=\($0.value)" }
            .joined(separator: "; ")

        let credentials = AuthCredentials(token: token, cookieString: cookieString)

        close()
        onCookiesExtracted(credentials)
    }
}

// MARK: - WebView Wrapper

private struct LoginWebViewWrapper: NSViewRepresentable {
    let webView: WKWebView

    func makeNSView(context: Context) -> WKWebView { webView }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}
