// AppViewModel.swift
// DevBar

import SwiftUI
import Combine
import ServiceManagement
import AppKit
import DevBarCore

@MainActor
final class AppViewModel: ObservableObject {
    enum AuthState {
        case loading
        case notLoggedIn
        case loggedIn
        case expired
    }

    @Published var authState: AuthState = .loading
    @Published var credentials: AuthCredentials?

    private let authService = AuthService()
    let quotaViewModel = QuotaViewModel()
    let openAIQuotaViewModel = OpenAIQuotaViewModel()
    let updateViewModel = UpdateViewModel()
    let notificationService = NotificationService()
    private var statusTextUpdateTask: Task<Void, Never>?
    /// Prevents duplicate handleLoginSuccess calls
    private var isHandlingLogin = false
    private var settingsWindow: NSWindow?
    private var previousGLMNotificationItems: [NotificationQuotaItem]?
    private var previousOpenAINotificationItems: [NotificationQuotaItem]?
    private var hasLaunched = false
    weak var languageManager: LanguageManager?

    // MARK: - Account Configs

    @Published var accountConfigs: [AccountConfig] {
        didSet {
            saveAccountConfigs()
        }
    }

    private func saveAccountConfigs() {
        if let data = try? JSONEncoder().encode(accountConfigs) {
            UserDefaults.standard.set(data, forKey: Constants.Defaults.accountConfigsKey)
        }
    }

    var enabledProviders: [QuotaProvider] {
        accountConfigs
            .filter(\.isEnabled)
            .sorted { $0.order < $1.order }
            .map(\.provider)
    }

    func hasAuthenticatedSession(for provider: QuotaProvider) -> Bool {
        switch provider {
        case .glm:
            return credentials?.token.isEmpty == false
        case .openai:
            let token = KeychainService.shared.load(key: Constants.Keychain.openAIAccessTokenKey)
            return token?.isEmpty == false
        }
    }

    private var hasAnyAuthenticatedProvider: Bool {
        enabledProviders.contains { hasAuthenticatedSession(for: $0) }
    }

    private func syncAuthState() {
        authState = hasAnyAuthenticatedProvider ? .loggedIn : .notLoggedIn
    }

    func refreshAuthenticationState() {
        syncAuthState()
        updateStatusText()
    }

    func isProviderEnabled(_ provider: QuotaProvider) -> Bool {
        accountConfigs.first(where: { $0.provider == provider })?.isEnabled ?? false
    }

    func updateAccountConfig(provider: QuotaProvider, isEnabled: Bool) {
        if let idx = accountConfigs.firstIndex(where: { $0.provider == provider }) {
            accountConfigs[idx].isEnabled = isEnabled
        }
        syncAuthState()
        updateStatusText()
    }

    weak var statusBarButton: NSStatusBarButton?

    @Published var menuBarIcon: String {
        didSet {
            UserDefaults.standard.set(menuBarIcon, forKey: Constants.Defaults.menuBarIconKey)
        }
    }

    // NOTE: statusText is a stored property, NOT computed.
    // A computed property would create an observation dependency from the
    // MenuBarExtra label to quotaViewModel.quotaData. When quotaData changes,
    // both the label and the popover content try to update simultaneously,
    // causing "entangle context after pre-commit" → EXC_BREAKPOINT.
    @Published var statusText: String = "DevBar"

    func updateStatusText(after delay: Duration = .zero) {
        statusTextUpdateTask?.cancel()
        statusTextUpdateTask = Task { @MainActor [weak self] in
            guard let self else { return }
            if delay > .zero {
                try? await Task.sleep(for: delay)
            } else {
                await Task.yield()
            }
            guard !Task.isCancelled else { return }
            guard authState == .loggedIn else {
                statusText = "DevBar"
                return
            }
            statusText = quotaViewModel.statusText
            print("[DevBar] ⑪ statusText updated -> \(statusText)")
        }
    }

    var refreshInterval: TimeInterval {
        get {
            UserDefaults.standard.double(forKey: Constants.Defaults.refreshIntervalKey)
                .nonZero ?? Constants.Defaults.defaultRefreshInterval
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Constants.Defaults.refreshIntervalKey)
        }
    }

    init() {
        // Load account configs
        if let data = UserDefaults.standard.data(forKey: Constants.Defaults.accountConfigsKey),
           let configs = try? JSONDecoder().decode([AccountConfig].self, from: data) {
            accountConfigs = configs
        } else {
            accountConfigs = [
                AccountConfig(provider: .glm, isEnabled: true, order: 0),
                AccountConfig(provider: .openai, isEnabled: false, order: 1)
            ]
        }

        menuBarIcon = UserDefaults.standard.string(forKey: Constants.Defaults.menuBarIconKey)
            ?? Constants.Defaults.defaultMenuBarIcon
        launchAtLogin = UserDefaults.standard.bool(forKey: Constants.Defaults.launchAtLoginKey)
        isHiddenFromDock = UserDefaults.standard.bool(forKey: Constants.Defaults.hideFromDockKey)
        notificationLowQuotaEnabled = UserDefaults.standard.bool(forKey: Constants.Defaults.notificationLowQuotaEnabledKey)
        notificationLowQuotaThreshold = UserDefaults.standard.double(forKey: Constants.Defaults.notificationLowQuotaThresholdKey)
            .nonZero ?? Constants.Defaults.defaultLowQuotaThreshold
        notificationExhaustedEnabled = UserDefaults.standard.bool(forKey: Constants.Defaults.notificationExhaustedEnabledKey)
        notificationResetEnabled = UserDefaults.standard.bool(forKey: Constants.Defaults.notificationResetEnabledKey)
        if let saved = authService.credentials {
            credentials = saved
            quotaViewModel.isLoading = true
        }
        syncAuthState()

        if hasAuthenticatedSession(for: .glm) {
            Task { @MainActor [weak self] in
                await Task.yield()
                guard let self else { return }
                await self.quotaViewModel.loadInitialData(credentials: self.credentials)
                self.updateStatusText(after: .milliseconds(200))
                self.checkAndNotify()
                self.startRefreshIfNeeded()
            }
        }

        // Load OpenAI data if enabled
        if isProviderEnabled(.openai) {
            let token = KeychainService.shared.load(key: Constants.Keychain.openAIAccessTokenKey)
            if let token, !token.isEmpty {
                Task { @MainActor [weak self] in
                    await openAIQuotaViewModel.fetchUsage(silent: true)
                    self?.checkAndNotify()
                }
            }
        }
    }

    /// Check for updates after a short delay, called once from onAppear.
    func checkForUpdatesOnFirstAppear() {
        guard !hasLaunched else { return }
        hasLaunched = true
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(Constants.Update.launchCheckDelay))
            self?.updateViewModel.checkForUpdates(silent: true)
        }
    }

    func handleLoginSuccess(_ credentials: AuthCredentials) {
        print("[DevBar] ⑥ handleLoginSuccess START, isHandlingLogin=\(isHandlingLogin)")
        guard !isHandlingLogin else {
            print("[DevBar] ⑥⑧ Already handling login, skipping")
            return
        }
        isHandlingLogin = true

        self.credentials = credentials
        authService.saveCredentials(credentials)
        syncAuthState()
        print("[DevBar] ⑥① authState set to loggedIn")

        Task { @MainActor [weak self] in
            await Task.yield()
            guard let self, self.authState == .loggedIn else {
                self?.isHandlingLogin = false
                return
            }
            print("[DevBar] ⑥② startRefreshIfNeeded")
            self.startRefreshIfNeeded()
            self.isHandlingLogin = false
        }
    }

    deinit {
        statusTextUpdateTask?.cancel()
        print("[DevBar] AppViewModel DEINIT")
    }

    func logout(provider: QuotaProvider) {
        statusTextUpdateTask?.cancel()
        switch provider {
        case .glm:
            quotaViewModel.resetForLogout()
            credentials = nil
            authService.logout()
        case .openai:
            openAIQuotaViewModel.resetForLogout()
            KeychainService.shared.delete(key: Constants.Keychain.openAIAccessTokenKey)
        }
        refreshAuthenticationState()
    }

    func makeTransferPayload(expirationInterval: TimeInterval = 300) -> TransferPayload {
        let exportedAt = Date()
        let glmCredentials = credentials.map {
            ProviderTransferCredentials(token: $0.token, cookieString: $0.cookieString)
        }
        let openAIToken = KeychainService.shared.load(key: Constants.Keychain.openAIAccessTokenKey)
        let openAICredentials = openAIToken.map {
            ProviderTransferCredentials(token: $0, cookieString: nil)
        }
        let openAIAccountId = UserDefaults.standard.string(forKey: Constants.OpenAI.accountIdKey)

        return TransferPayload(
            exportedAt: exportedAt,
            expiresAt: exportedAt.addingTimeInterval(expirationInterval),
            deviceName: Host.current().localizedName,
            accountConfigs: accountConfigs.sorted { $0.order < $1.order },
            providers: [
                ProviderTransferPayload(provider: .glm, credentials: glmCredentials),
                ProviderTransferPayload(
                    provider: .openai,
                    credentials: openAICredentials,
                    accountId: openAIAccountId
                ),
            ]
        )
    }

    func makeTransferURL(expirationInterval: TimeInterval = 300) throws -> URL {
        try TransferPayloadCodec.makeURL(for: makeTransferPayload(expirationInterval: expirationInterval))
    }

    /// Refresh data when the popover opens, unless refreshed within 30s.
    func refreshOnPopoverOpenIfNeeded() {
        guard authState == .loggedIn else { return }
        let minimumInterval: TimeInterval = 30
        if selectedRefreshProvider == .glm,
           let last = quotaViewModel.lastUpdated,
           Date().timeIntervalSince(last) < minimumInterval {
            return
        }
        Task { await refreshQuota(silent: true) }
    }

    func refreshQuota(silent: Bool = false) async {
        if isProviderEnabled(.glm), hasAuthenticatedSession(for: .glm) {
            await quotaViewModel.fetchQuota(credentials: credentials, silent: silent)
            updateStatusText(after: .milliseconds(200))
            if quotaViewModel.errorMessage == String(localized: "login_expired") {
                authState = hasAuthenticatedSession(for: .openai) ? .loggedIn : .expired
                updateStatusText()
            }
        }

        if isProviderEnabled(.openai), hasAuthenticatedSession(for: .openai) {
            await openAIQuotaViewModel.fetchUsage(silent: true)
        }

        checkAndNotify()
    }

    /// Start refresh if not already running (prevents duplicate timers)
    func startRefreshIfNeeded() {
        guard refreshInterval > 0 else { return } // Don't start if "Never"
        guard hasAuthenticatedSession(for: .glm) else { return }
        print("[DevBar] ⑦ startRefreshIfNeeded, hasCredentials=\(credentials != nil)")
        quotaViewModel.startAutoRefresh(
            credentials: credentials,
            interval: refreshInterval,
            onFetchComplete: { [weak self] in
                self?.updateStatusText(after: .milliseconds(200))
                self?.checkAndNotify()
            }
        )
    }

    private func checkAndNotify() {
        if let limits = quotaViewModel.quotaData?.limits {
            let glmItems = limits.map {
                NotificationQuotaItem(
                    key: "\($0.type)_\($0.unit ?? -1)_\($0.number ?? -1)",
                    name: $0.displayName,
                    percentage: $0.percentage
                )
            }
            notificationService.checkAndNotify(
                provider: .glm,
                items: glmItems,
                settings: notificationSettings,
                previousItems: previousGLMNotificationItems
            )
            previousGLMNotificationItems = glmItems
        }

        if !openAIQuotaViewModel.quotaRows.isEmpty {
            let openAIItems = openAIQuotaViewModel.quotaRows.map {
                NotificationQuotaItem(
                    key: $0.name,
                    name: $0.name,
                    percentage: $0.percentage
                )
            }
            notificationService.checkAndNotify(
                provider: .openai,
                items: openAIItems,
                settings: notificationSettings,
                previousItems: previousOpenAINotificationItems
            )
            previousOpenAINotificationItems = openAIItems
        }
    }

    func stopAutoRefresh() {
        quotaViewModel.stopAutoRefresh()
    }

    private var selectedRefreshProvider: QuotaProvider {
        enabledProviders.first(where: { hasAuthenticatedSession(for: $0) }) ?? enabledProviders.first ?? .glm
    }

    @Published var isHiddenFromDock: Bool {
        didSet {
            UserDefaults.standard.set(isHiddenFromDock, forKey: Constants.Defaults.hideFromDockKey)
            NSApplication.shared.setActivationPolicy(isHiddenFromDock ? .accessory : .regular)
        }
    }

    // MARK: - Launch at Login

    @Published var launchAtLogin: Bool {
        didSet {
            UserDefaults.standard.set(launchAtLogin, forKey: Constants.Defaults.launchAtLoginKey)
            do {
                if launchAtLogin {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                print("[DevBar] Launch at login error: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Notification Settings

    @Published var notificationLowQuotaEnabled: Bool {
        didSet {
            UserDefaults.standard.set(notificationLowQuotaEnabled, forKey: Constants.Defaults.notificationLowQuotaEnabledKey)
        }
    }

    @Published var notificationLowQuotaThreshold: Double {
        didSet {
            UserDefaults.standard.set(notificationLowQuotaThreshold, forKey: Constants.Defaults.notificationLowQuotaThresholdKey)
        }
    }

    @Published var notificationExhaustedEnabled: Bool {
        didSet {
            UserDefaults.standard.set(notificationExhaustedEnabled, forKey: Constants.Defaults.notificationExhaustedEnabledKey)
        }
    }

    @Published var notificationResetEnabled: Bool {
        didSet {
            UserDefaults.standard.set(notificationResetEnabled, forKey: Constants.Defaults.notificationResetEnabledKey)
        }
    }

    var notificationSettings: NotificationSettings {
        NotificationSettings(
            lowQuotaEnabled: notificationLowQuotaEnabled,
            lowQuotaThreshold: notificationLowQuotaThreshold,
            exhaustedEnabled: notificationExhaustedEnabled,
            resetEnabled: notificationResetEnabled
        )
    }

    // MARK: - Settings Window

    func showSettings(select tab: SettingsTab? = nil) {
        if let tab {
            UserDefaults.standard.set(tab.rawValue, forKey: "selectedSettingsTab")
        }

        // If window exists and is visible, just bring to front
        if let window = settingsWindow, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        // Clean up previous window
        settingsWindow = nil

        let baseView = SettingsView()
            .environmentObject(self)
            .environmentObject(quotaViewModel)
            .environmentObject(openAIQuotaViewModel)
            .environmentObject(updateViewModel)
            .environmentObject(notificationService)

        let hostedView: AnyView
        if let lm = languageManager {
            hostedView = AnyView(baseView
                .environmentObject(lm)
                .environment(\.locale, lm.currentLocale))
        } else {
            hostedView = AnyView(baseView)
        }

        let hostingView = NSHostingView(rootView: hostedView)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 420),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        window.titleVisibility = .hidden
        window.center()

        let titleToolbar = CenterTitleToolbar(title: String(localized: "settings"))
        window.toolbar = titleToolbar.toolbar
        window.level = .floating
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow = window

        // Background update check (fire-and-forget, failures are ignored)
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            self?.updateViewModel.checkForUpdates(silent: true)
        }

        // Show update window if new version available
        if updateViewModel.hasUpdateAvailable {
            updateViewModel.showUpdateWindow()
        }
    }

    func hideSettings() {
        settingsWindow?.orderOut(nil)
        settingsWindow = nil
    }
}

private extension Double {
    var nonZero: Double? {
        self > 0 ? self : nil
    }
}

private final class CenterTitleToolbar: NSObject, NSToolbarDelegate {
    let toolbar: NSToolbar
    private let title: String
    private static let titleId = NSToolbarItem.Identifier("centerTitle")

    init(title: String) {
        self.title = title
        self.toolbar = NSToolbar(identifier: "CenterTitleToolbar")
        super.init()
        toolbar.delegate = self
        toolbar.displayMode = .default
        toolbar.showsBaselineSeparator = true
        toolbar.centeredItemIdentifier = Self.titleId
    }

    func toolbar(_ toolbar: NSToolbar,
                 itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        guard itemIdentifier == Self.titleId else { return nil }
        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        label.alignment = .center
        label.sizeToFit()
        item.view = label
        NSLayoutConstraint.activate([
            label.widthAnchor.constraint(equalToConstant: label.frame.width),
            label.heightAnchor.constraint(equalToConstant: label.frame.height)
        ])
        return item
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [Self.titleId]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [Self.titleId]
    }
}
