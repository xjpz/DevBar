// AppViewModel.swift
// DevBar

import SwiftUI
import Combine
import ServiceManagement
import AppKit

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
    let updateViewModel = UpdateViewModel()
    let notificationService = NotificationService()
    private var statusTextUpdateTask: Task<Void, Never>?
    /// Prevents duplicate handleLoginSuccess calls
    private var isHandlingLogin = false
    private var settingsWindow: NSWindow?
    private var previousQuotaData: QuotaData?
    private var hasLaunched = false

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
            authState = .loggedIn
            quotaViewModel.isLoading = true
        } else {
            authState = .notLoggedIn
        }
        if authState == .loggedIn {
            Task { @MainActor [weak self] in
                await Task.yield()
                guard let self else { return }
                await self.quotaViewModel.loadInitialData(credentials: self.credentials)
                self.updateStatusText(after: .milliseconds(200))
                self.checkAndNotify()
                self.startRefreshIfNeeded()
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
        self.authState = .loggedIn
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

    func logout() {
        statusTextUpdateTask?.cancel()
        quotaViewModel.resetForLogout()
        credentials = nil
        authService.logout()
        authState = .notLoggedIn
        updateStatusText()
    }

    /// Refresh data when the popover opens, unless refreshed within 30s.
    func refreshOnPopoverOpenIfNeeded() {
        guard authState == .loggedIn, credentials != nil else { return }
        let minimumInterval: TimeInterval = 30
        if let last = quotaViewModel.lastUpdated,
           Date().timeIntervalSince(last) < minimumInterval {
            return
        }
        Task { await refreshQuota(silent: true) }
    }

    func refreshQuota(silent: Bool = false) async {
        await quotaViewModel.fetchQuota(credentials: credentials, silent: silent)
        updateStatusText(after: .milliseconds(200))
        if quotaViewModel.errorMessage == "登录已过期，请重新登录" {
            authState = .expired
            updateStatusText()
        }
    }

    /// Start refresh if not already running (prevents duplicate timers)
    func startRefreshIfNeeded() {
        guard refreshInterval > 0 else { return } // Don't start if "Never"
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
        guard let currentData = quotaViewModel.quotaData else { return }
        notificationService.checkAndNotify(
            quotaData: currentData,
            settings: notificationSettings,
            previousData: previousQuotaData
        )
        previousQuotaData = currentData
    }

    func stopAutoRefresh() {
        quotaViewModel.stopAutoRefresh()
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

    func showSettings() {
        // If window exists and is visible, just bring to front
        if let window = settingsWindow, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        // Clean up previous window
        settingsWindow = nil

        let settingsView = SettingsView()
            .environmentObject(self)
            .environmentObject(quotaViewModel)
            .environmentObject(updateViewModel)
            .environmentObject(notificationService)

        let hostingView = NSHostingView(rootView: settingsView)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 420),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        window.titleVisibility = .hidden
        window.center()

        let titleToolbar = CenterTitleToolbar(title: "设置")
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
        item.minSize = label.frame.size
        item.maxSize = label.frame.size
        return item
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [Self.titleId]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [Self.titleId]
    }
}
