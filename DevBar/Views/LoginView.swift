//
//  LoginView.swift
//  DevBar
//

import SwiftUI
import WebKit
import Combine
import DevBarCore

struct LoginView: View {
    @EnvironmentObject private var appViewModel: AppViewModel

    var isExpired = false

    @State private var selectedProvider: QuotaProvider = .glm
    @State private var isValidating = false
    @State private var loginError: String?
    @State private var glmAPIKey = ""
    @State private var openAIToken = ""
    @State private var mimoCookie = ""
    @State private var deepseekToken = ""
    @State private var deepseekCookie = ""

    // DeepSeek webview login state
    @State private var deepSeekLoginWebView: WKWebView?
    @State private var deepSeekLoginWindow: NSWindow?
    @StateObject private var deepSeekTokenStore = DeepSeekTokenStore()
    @State private var deepSeekPollTimer: Timer?

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
                case .mimo:
                    mimoLoginCard
                case .deepseek:
                    deepSeekLoginCard
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
            if let token = KeychainService.shared.load(key: DevBarCoreConstants.Keychain.mimoServiceTokenKey),
               !token.isEmpty {
                mimoCookie = token
            }
            if let account = appViewModel.providerAccounts.first(where: { $0.provider == .deepseek }),
               let credential = KeychainService.shared.loadProviderCredential(for: account) {
                deepseekToken = credential.token ?? ""
                deepseekCookie = credential.cookieString ?? ""
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

    var mimoLoginCard: some View {
        VStack(spacing: 12) {
            Button(action: openMiMoLoginWindow) {
                Text("browser_login")
            }
            .buttonStyle(DevBarButtonStyle(isPrimary: mimoCookie.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
            .disabled(isValidating)

            separatorView

            mimoCookieSection
        }
        .padding(16)
        .background(cardBackground)
    }

    var deepSeekLoginCard: some View {
        VStack(spacing: 12) {
            Button(action: openDeepSeekLoginWindow) {
                Text("browser_login")
            }
            .buttonStyle(DevBarButtonStyle(isPrimary: true))
            .disabled(isValidating)

            separatorView

            VStack(spacing: 10) {
                SecureField("Bearer xxx", text: $deepseekToken)
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

                SecureField("Cookie", text: $deepseekCookie)
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

                Text("deepseek_authorization_hint")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Button(action: loginWithDeepSeekToken) {
                    HStack {
                        if isValidating {
                            ProgressView()
                                .controlSize(.mini)
                        }
                        Text("accounts_done_editing")
                    }
                }
                .buttonStyle(DevBarButtonStyle(isPrimary: true))
                .disabled(deepseekToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || deepseekCookie.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isValidating)
            }
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

    var mimoCookieSection: some View {
        VStack(spacing: 10) {
            SecureField(String(localized: "mimo_cookie_placeholder"), text: $mimoCookie)
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
                .onSubmit { loginWithMimoCookie() }

            Text("mimo_cookie_hint")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: loginWithMimoCookie) {
                HStack {
                    if isValidating {
                        ProgressView().controlSize(.small)
                    }
                    Text("mimo_cookie_login")
                }
            }
            .buttonStyle(DevBarButtonStyle(isPrimary: !mimoCookie.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
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

    func loginWithMimoCookie() {
        let credential = mimoCookie.trimmingCharacters(in: .whitespacesAndNewlines)
        let serviceToken = MimoAPIClient.normalizedServiceToken(from: credential)
        guard !serviceToken.isEmpty else { return }

        loginError = nil
        isValidating = true

        Task { @MainActor in
            defer { isValidating = false }

            do {
                _ = try await appViewModel.mimoQuotaViewModel.fetchUsage(
                    serviceToken: credential,
                    silent: true
                )
                await appViewModel.mimoQuotaViewModel.fetchPlanDetailIfNeeded(
                    serviceToken: credential,
                    force: true
                )
                KeychainService.shared.save(
                    key: DevBarCoreConstants.Keychain.mimoServiceTokenKey,
                    value: credential
                )
                appViewModel.updateAccountConfig(provider: .mimo, isEnabled: true)
                appViewModel.refreshAuthenticationState()
            } catch let error as APIError {
                loginError = error.errorDescription
            } catch {
                loginError = error.localizedDescription
            }
        }
    }

    func openMiMoLoginWindow() {
        loginError = nil

        let controller = LoginWindowController(
            loginURL: DevBarCoreConstants.MiMO.dashboardURL,
            windowTitle: String(localized: "login_mimo_platform"),
            targetCookieName: "api-platform_serviceToken",
            onTokenExtracted: { token, cookies in
                let cookieString = MimoAPIClient.platformCookieString(from: cookies)
                let storedValue = cookieString.isEmpty ? token : cookieString
                let savedValue = mimoCookie.trimmingCharacters(in: .whitespacesAndNewlines)

                if MimoAPIClient.isSameRequiredCookie(storedValue, savedValue) {
                    loginError = String(localized: "mimo_cookie_unchanged_from_browser")
                    return false
                }

                isValidating = true

                Task { @MainActor in
                    defer { isValidating = false }

                    do {
                        print("[MiMo:WebViewLogin] cookie string prefix: \(storedValue.prefix(60))...")
                        _ = try await appViewModel.mimoQuotaViewModel.fetchUsage(
                            serviceToken: storedValue,
                            silent: true
                        )
                        print("[MiMo:WebViewLogin] fetchUsage succeeded")
                        await appViewModel.mimoQuotaViewModel.fetchPlanDetailIfNeeded(
                            serviceToken: storedValue,
                            force: true
                        )
                        print("[MiMo:WebViewLogin] fetchPlanDetail succeeded")
                        KeychainService.shared.save(
                            key: DevBarCoreConstants.Keychain.mimoServiceTokenKey,
                            value: storedValue
                        )
                        mimoCookie = storedValue
                        appViewModel.updateAccountConfig(provider: .mimo, isEnabled: true)
                        appViewModel.refreshAuthenticationState()
                        print("[MiMo:WebViewLogin] auth state refreshed")
                    } catch let error as APIError {
                        print("[MiMo:WebViewLogin] APIError: \(error)")
                        loginError = error.errorDescription
                    } catch {
                        print("[MiMo:WebViewLogin] error: \(error)")
                        loginError = error.localizedDescription
                    }
                }
                return true
            }
        )

        controller.show()
    }

    func openDeepSeekLoginWindow() {
        loginError = nil

        // Create WKWebView with network interception to capture the Bearer token
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()

        let contentController = WKUserContentController()
        let captureScript = WKUserScript(
            source: """
            (function() {
                var origFetch = window.fetch;
                window.fetch = function() {
                    var req = arguments[0];
                    var opts = arguments[1] || {};
                    var auth = (typeof req === 'object' && req.headers) ? req.headers.get('Authorization') : (opts.headers && (opts.headers['Authorization'] || opts.headers['authorization']));
                    if (auth && auth.indexOf('Bearer ') === 0) {
                        window.webkit.messageHandlers.deepSeekTokenCapture.postMessage(auth.substring(7));
                    }
                    return origFetch.apply(this, arguments);
                };
                var origOpen = XMLHttpRequest.prototype.open;
                var origSetHeader = XMLHttpRequest.prototype.setRequestHeader;
                XMLHttpRequest.prototype.open = function() {
                    this._authHeader = null;
                    return origOpen.apply(this, arguments);
                };
                XMLHttpRequest.prototype.setRequestHeader = function(name, value) {
                    if (name.toLowerCase() === 'authorization' && value.indexOf('Bearer ') === 0) {
                        this._authHeader = value.substring(7);
                    }
                    return origSetHeader.apply(this, arguments);
                };
                var origSend = XMLHttpRequest.prototype.send;
                XMLHttpRequest.prototype.send = function() {
                    if (this._authHeader) {
                        window.webkit.messageHandlers.deepSeekTokenCapture.postMessage(this._authHeader);
                    }
                    return origSend.apply(this, arguments);
                };
            })();
            """,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        )
        contentController.addUserScript(captureScript)
        contentController.add(DeepSeekTokenMessageHandler(store: deepSeekTokenStore), name: "deepSeekTokenCapture")
        config.userContentController = contentController

        let webView = WKWebView(frame: .zero, configuration: config)
        let hostingView = NSHostingView(rootView: LoginWebViewWrapper(webView: webView))

        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 700),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        win.contentView = hostingView
        win.title = "DeepSeek Platform"
        win.center()
        win.level = .floating
        win.isReleasedWhenClosed = false
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        deepSeekLoginWebView = webView
        deepSeekLoginWindow = win
        deepSeekTokenStore.capturedToken = nil

        if let url = URL(string: DevBarCoreConstants.DeepSeek.dashboardURL) {
            webView.load(URLRequest(url: url))
        }

        deepSeekPollTimer?.invalidate()
        deepSeekPollTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
            Task { @MainActor in
                await tryDeepSeekLoginExtract(webView: webView)
            }
        }
    }

    @MainActor
    private func tryDeepSeekLoginExtract(webView: WKWebView) async {
        guard let bearerToken = deepSeekTokenStore.capturedToken, !bearerToken.isEmpty else { return }

        let cookies = await webView.configuration.websiteDataStore.httpCookieStore.allCookies()
        let cookieString = cookies
            .filter { $0.domain.contains("deepseek.com") }
            .map { "\($0.name)=\($0.value)" }
            .joined(separator: "; ")

        guard !cookieString.isEmpty else { return }

        deepSeekPollTimer?.invalidate()
        deepSeekPollTimer = nil
        deepSeekLoginWindow?.close()
        deepSeekLoginWindow = nil
        deepSeekLoginWebView = nil

        isValidating = true
        defer { isValidating = false }

        do {
            let apiClient = DeepSeekAPIClient()
            _ = try await apiClient.fetchUsage(token: bearerToken, cookieString: cookieString)

            appViewModel.upsertCredentialForPrimaryAccount(
                provider: .deepseek,
                token: bearerToken,
                cookieString: cookieString,
                accountIdentifier: nil
            )
            deepseekToken = bearerToken
            deepseekCookie = cookieString
            appViewModel.updateAccountConfig(provider: .deepseek, isEnabled: true)
            appViewModel.refreshAuthenticationState()

            await appViewModel.deepSeekQuotaViewModel.fetchUsage(
                token: bearerToken,
                cookieString: cookieString,
                silent: true
            )
        } catch let error as APIError {
            loginError = error.errorDescription
        } catch {
            loginError = error.localizedDescription
        }
    }

    func loginWithDeepSeekToken() {
        let trimmedToken = deepseekToken.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCookie = deepseekCookie.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedToken.isEmpty, !trimmedCookie.isEmpty else { return }

        loginError = nil
        isValidating = true

        Task { @MainActor in
            defer { isValidating = false }

            do {
                let apiClient = DeepSeekAPIClient()
                _ = try await apiClient.fetchUsage(
                    token: trimmedToken,
                    cookieString: trimmedCookie
                )

                appViewModel.upsertCredentialForPrimaryAccount(
                    provider: .deepseek,
                    token: trimmedToken,
                    cookieString: trimmedCookie,
                    accountIdentifier: nil
                )
                appViewModel.updateAccountConfig(provider: .deepseek, isEnabled: true)
                appViewModel.refreshAuthenticationState()

                await appViewModel.deepSeekQuotaViewModel.fetchUsage(
                    token: trimmedToken,
                    cookieString: trimmedCookie,
                    silent: true
                )
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
            windowTitle: String(localized: "login_bigmodel"),
            targetCookieName: "bigmodel_token_production",
            onTokenExtracted: { token, cookies in
                isValidating = true

                Task { @MainActor in
                    let cookieString = cookies
                        .filter { ["bigmodel.cn", ".bigmodel.cn"].contains($0.domain) }
                        .map { "\($0.name)=\($0.value)" }
                        .joined(separator: "; ")
                    let credentials = AuthCredentials(token: token, cookieString: cookieString)

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
                return true
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
    private var didExtract = false

    private let loginURL: String
    private let windowTitle: String
    private let candidateCookieNames: [String]
    private let cookieDomain: String
    private let onTokenExtracted: (_ token: String, _ cookies: [HTTPCookie]) -> Bool

    /// Single cookie name convenience init (backward compatible).
    init(
        loginURL: String,
        windowTitle: String,
        targetCookieName: String,
        onTokenExtracted: @escaping (_ token: String, _ cookies: [HTTPCookie]) -> Bool
    ) {
        self.loginURL = loginURL
        self.windowTitle = windowTitle
        self.candidateCookieNames = [targetCookieName]
        self.cookieDomain = ""
        self.onTokenExtracted = onTokenExtracted
        super.init()
    }

    /// Multi-candidate init: tries each cookie name in order.
    init(
        loginURL: String,
        windowTitle: String,
        candidateCookieNames: [String],
        cookieDomain: String,
        onTokenExtracted: @escaping (_ token: String, _ cookies: [HTTPCookie]) -> Bool
    ) {
        self.loginURL = loginURL
        self.windowTitle = windowTitle
        self.candidateCookieNames = candidateCookieNames
        self.cookieDomain = cookieDomain
        self.onTokenExtracted = onTokenExtracted
        super.init()
    }

    func show() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()

        let contentController = WKUserContentController()
        let names = candidateCookieNames
        let namesJSArray = names.map { "'\($0)'" }.joined(separator: ",")
        let script = WKUserScript(
            source: """
            (function() {
                var targets = [\(namesJSArray)];
                function checkCookie() {
                    var cookies = document.cookie;
                    for (var i = 0; i < targets.length; i++) {
                        if (cookies.indexOf(targets[i] + '=') !== -1) {
                            window.webkit.messageHandlers.loginDetector.postMessage('found');
                            return;
                        }
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
        win.title = windowTitle
        win.center()
        win.level = .floating
        win.isReleasedWhenClosed = false
        win.delegate = self
        win.makeKeyAndOrderFront(nil)

        NSApp.activate(ignoringOtherApps: true)

        self.window = win

        if let url = URL(string: loginURL) {
            webView.load(URLRequest(url: url))
        }

        startPolling()
    }

    private func startPolling() {
        pollTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, !self.didExtract, let webView = self.webView else { return }
                await self.tryExtractToken(from: webView)
            }
        }
    }

    @MainActor
    private func tryExtractToken(from webView: WKWebView) async {
        let cookies = await webView.configuration.websiteDataStore.httpCookieStore.allCookies()

        // Try each candidate cookie name
        for name in candidateCookieNames {
            if let token = cookies.first(where: { $0.name == name }),
               !token.value.isEmpty {
                self.handleLoginSuccess(token: token.value, cookies: cookies)
                return
            }
        }

        // Try JS extraction for each candidate
        for name in candidateCookieNames {
            if let jsToken = await self.extractCookieViaJS(webView: webView, name: name) {
                var enriched = cookies
                if enriched.allSatisfy({ $0.name != name }) {
                    let domain = cookieDomain.isEmpty ? URL(string: loginURL)?.host ?? "" : cookieDomain
                    if let synth = HTTPCookie(properties: [
                        .name: name,
                        .value: jsToken,
                        .domain: domain,
                        .path: "/",
                    ]) {
                        enriched.append(synth)
                    }
                }
                self.handleLoginSuccess(token: jsToken, cookies: enriched)
                return
            }
        }
    }

    func close() {
        guard !didExtract else { return }
        didExtract = true

        pollTimer?.invalidate()
        pollTimer = nil

        webView?.configuration.userContentController.removeScriptMessageHandler(forName: loginScriptMessageHandler)
        webView?.configuration.userContentController.removeAllUserScripts()
        webView?.stopLoading()

        window?.close()
        window = nil
        webView = nil
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == loginScriptMessageHandler else { return }

        Task { @MainActor [weak self] in
            guard let self, !self.didExtract, let webView = self.webView else { return }
            await self.tryExtractToken(from: webView)
        }
    }

    private func handleLoginSuccess(token: String, cookies: [HTTPCookie]) {
        guard !didExtract else { return }
        if onTokenExtracted(token, cookies) {
            close()
        }
    }

    @MainActor
    private func extractCookieViaJS(webView: WKWebView, name: String) async -> String? {
        let js = """
        (function() {
            var pairs = document.cookie.split(';');
            for (var i = 0; i < pairs.length; i++) {
                var p = pairs[i].split('=');
                if (p[0].trim() === '\(name)') {
                    return p.slice(1).join('=').trim();
                }
            }
            return '';
        })();
        """
        guard let value = try? await webView.evaluateJavaScript(js) as? String,
              !value.isEmpty else {
            return nil
        }
        #if DEBUG
        print("[LoginWindow] JS extract \(name) = \(value.prefix(40))...")
        #endif
        return value
    }
}

extension LoginWindowController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        pollTimer?.invalidate()
        pollTimer = nil
    }
}

extension LoginWindowController {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard !didExtract else { return }

        Task { @MainActor in
            let cookies = await webView.configuration.websiteDataStore.httpCookieStore.allCookies()

            #if DEBUG
            let names = cookies.map { "\($0.name)=\($0.value.prefix(16))..." }
            print("[LoginWindowController] cookies after navigation: \(names)")
            #endif

            for name in candidateCookieNames {
                if let token = cookies.first(where: { $0.name == name }),
                   !token.value.isEmpty {
                    self.handleLoginSuccess(token: token.value, cookies: cookies)
                    return
                }
            }
        }
    }
}

/// Shared storage for DeepSeek login webview token capture.
final class DeepSeekTokenStore: ObservableObject {
    @Published var capturedToken: String?
}

/// Lightweight message handler for capturing DeepSeek Bearer token from webview JS.
private final class DeepSeekTokenMessageHandler: NSObject, WKScriptMessageHandler {
    let store: DeepSeekTokenStore
    init(store: DeepSeekTokenStore) { self.store = store }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "deepSeekTokenCapture",
              let token = message.body as? String, !token.isEmpty else { return }
        Task { @MainActor in
            store.capturedToken = token
        }
    }
}

struct LoginWebViewWrapper: NSViewRepresentable {
    let webView: WKWebView

    func makeNSView(context: Context) -> WKWebView { webView }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}
