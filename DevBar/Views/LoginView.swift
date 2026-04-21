//
//  LoginView.swift
//  DevBar
//

import SwiftUI
import WebKit

struct LoginView: View {
    @EnvironmentObject private var appViewModel: AppViewModel

    var isExpired = false

    @State private var selectedProvider: QuotaProvider = .glm
    @State private var isValidating = false
    @State private var loginError: String?
    @State private var glmAPIKey = ""
    @State private var openAIToken = ""

    var body: some View {
        VStack(spacing: 16) {
            header

            providerPicker

            Group {
                switch selectedProvider {
                case .glm:
                    glmLoginCard
                case .openai:
                    openAILoginCard
                }
            }

            footer
        }
        .padding(20)
        .frame(width: 320)
        .task {
            if let token = KeychainService.shared.load(key: Constants.Keychain.openAIAccessTokenKey),
               !token.isEmpty {
                openAIToken = token
            }
        }
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

private extension LoginView {
    var header: some View {
        VStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 52, height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 12))

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

    var providerPicker: some View {
        HStack(spacing: 8) {
            ForEach(providerOrder, id: \.self) { provider in
                Button {
                    loginError = nil
                    selectedProvider = provider
                } label: {
                    HStack(spacing: 6) {
                        providerLogo(for: provider, size: 14)
                        Text(provider.localizedName)
                            .font(.caption.weight(selectedProvider == provider ? .semibold : .regular))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(selectedProvider == provider ? Color.accentColor.opacity(0.14) : Color.primary.opacity(0.04))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(selectedProvider == provider ? selectedAccentColor.opacity(0.35) : Color.primary.opacity(0.06), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    var glmLoginCard: some View {
        VStack(spacing: 12) {
            browserLoginSection
            separatorView
            glmAPIKeySection
        }
        .padding(16)
        .background(cardBackground)
    }

    var openAILoginCard: some View {
        VStack(spacing: 12) {
            Button(action: loadOpenAITokenFromCodexConfig) {
                Text("accounts_read_from_config")
            }
            .buttonStyle(DevBarButtonStyle(isPrimary: openAIToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
            .disabled(isValidating)

            separatorView

            openAITokenSection
        }
        .padding(16)
        .background(cardBackground)
    }

    var browserLoginSection: some View {
        VStack(spacing: 10) {
            Button(action: openLoginWindow) {
                Text("browser_login")
            }
            .buttonStyle(DevBarButtonStyle(isPrimary: glmAPIKey.trimmingCharacters(in: .whitespaces).isEmpty))
            .disabled(isValidating)
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

    var glmAPIKeySection: some View {
        VStack(spacing: 10) {
            SecureField("enter_api_key", text: $glmAPIKey)
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
                .onSubmit { loginWithGLMApiKey() }

            Text("accounts_glm_api_key_hint")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: loginWithGLMApiKey) {
                HStack {
                    if isValidating {
                        ProgressView().controlSize(.small)
                    }
                    Text("api_key_login")
                }
            }
            .buttonStyle(DevBarButtonStyle(isPrimary: !glmAPIKey.trimmingCharacters(in: .whitespaces).isEmpty))
            .disabled(isValidating)

            errorMessageView
        }
    }

    var openAITokenSection: some View {
        VStack(spacing: 10) {
            SecureField(String(localized: "openai_token_placeholder"), text: $openAIToken)
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
                .onSubmit { loginWithOpenAIToken() }

            Text("accounts_openai_token_hint")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: loginWithOpenAIToken) {
                HStack {
                    if isValidating {
                        ProgressView().controlSize(.small)
                    }
                    Text("openai_token_login")
                }
            }
            .buttonStyle(DevBarButtonStyle(isPrimary: !openAIToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
            .disabled(isValidating)

            errorMessageView
        }
    }

    @ViewBuilder
    var errorMessageView: some View {
        if let loginError {
            Label(loginError, systemImage: "exclamationmark.triangle.fill")
                .font(.caption2)
                .foregroundStyle(.red)
                .padding(6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.red.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }

    var footer: some View {
        Text("credentials_local_only")
            .font(.caption2)
            .foregroundStyle(.tertiary)
    }

    var providerOrder: [QuotaProvider] {
        let ordered = appViewModel.accountConfigs
            .sorted { $0.order < $1.order }
            .map(\.provider)
        return ordered.isEmpty ? QuotaProvider.allCases : ordered
    }

    var selectedAccentColor: Color {
        selectedProvider.accentColor
    }

    var cardBackground: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(selectedAccentColor.opacity(0.12), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.08), radius: 10, y: 4)
    }

    func providerLogo(for provider: QuotaProvider, size: CGFloat) -> some View {
        Image(provider.assetName)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
    }
}

private extension LoginView {
    func loginWithGLMApiKey() {
        let key = glmAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }

        loginError = nil
        isValidating = true

        Task { @MainActor in
            let isValid = await validateGLMAPIKey(key)
            isValidating = false

            if isValid {
                appViewModel.updateAccountConfig(provider: .glm, isEnabled: true)
                withAnimation(.spring()) {
                    appViewModel.handleLoginSuccess(AuthCredentials(token: key, cookieString: ""))
                }
            } else {
                loginError = String(localized: "api_key_invalid")
            }
        }
    }

    func loginWithOpenAIToken() {
        let token = openAIToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { return }

        loginError = nil
        isValidating = true
        let accountId = UserDefaults.standard.string(forKey: Constants.OpenAI.accountIdKey)

        Task { @MainActor in
            defer { isValidating = false }

            do {
                _ = try await appViewModel.openAIQuotaViewModel.fetchUsage(
                    accessToken: token,
                    accountId: accountId,
                    silent: true
                )
                KeychainService.shared.save(key: Constants.Keychain.openAIAccessTokenKey, value: token)
                appViewModel.updateAccountConfig(provider: .openai, isEnabled: true)
                appViewModel.refreshAuthenticationState()
            } catch let error as APIError {
                loginError = error.errorDescription
            } catch {
                loginError = error.localizedDescription
            }
        }
    }

    func loadOpenAITokenFromCodexConfig() {
        loginError = nil

        do {
            let token = try CodexAuthFileLoader.loadOpenAIAccessToken()
            guard !token.isEmpty else {
                loginError = String(localized: "accounts_openai_config_missing_token")
                return
            }
            openAIToken = token
        } catch {
            loginError = String(localized: "accounts_openai_config_read_failed")
        }
    }

    func openLoginWindow() {
        loginError = nil

        let controller = LoginWindowController(
            loginURL: Constants.API.loginURL,
            onCookiesExtracted: { credentials in
                isValidating = true

                Task { @MainActor in
                    let isValid = await validateGLMCookie(credentials.cookieString)
                    isValidating = false

                    if isValid {
                        appViewModel.updateAccountConfig(provider: .glm, isEnabled: true)
                        withAnimation(.spring()) {
                            appViewModel.handleLoginSuccess(credentials)
                        }
                    } else {
                        loginError = String(localized: "token_invalid")
                    }
                }
            }
        )

        controller.show()
    }

    func validateGLMAPIKey(_ key: String) async -> Bool {
        var request = URLRequest(url: URL(string: Constants.API.quotaLimitURL)!)
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 10

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  http.statusCode == 200 else {
                return false
            }

            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let success = json["success"] as? Bool ?? false
                let code = json["code"] as? Int ?? -1
                return success || code == 0
            }

            return false
        } catch {
            print("[DevBar] API Key validation failed: \(error.localizedDescription)")
            return false
        }
    }

    func validateGLMCookie(_ cookieString: String) async -> Bool {
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

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
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

private struct LoginWebViewWrapper: NSViewRepresentable {
    let webView: WKWebView

    func makeNSView(context: Context) -> WKWebView { webView }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}
