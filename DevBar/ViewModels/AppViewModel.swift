// AppViewModel.swift
// DevBar

import SwiftUI
import Combine

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
    private var statusTextUpdateTask: Task<Void, Never>?
    /// Prevents duplicate handleLoginSuccess calls
    private var isHandlingLogin = false

    var menuBarIcon: String {
        UserDefaults.standard.string(forKey: Constants.Defaults.menuBarIconKey)
            ?? Constants.Defaults.defaultMenuBarIcon
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
        if let saved = authService.credentials {
            credentials = saved
            authState = .loggedIn
        } else {
            authState = .notLoggedIn
        }
    }

    /// Called after the view hierarchy is ready (prevents triggering
    /// network calls before SwiftUI has finished its initial layout).
    func appDidFinishLaunching() {
        guard authState == .loggedIn, credentials != nil else { return }
        Task { @MainActor [weak self] in
            await Task.yield()
            self?.startRefreshIfNeeded()
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
        stopAutoRefresh()
        quotaViewModel.quotaData = nil
        credentials = nil
        authService.logout()
        authState = .notLoggedIn
        updateStatusText()
    }

    func refreshQuota() async {
        await quotaViewModel.fetchQuota(credentials: credentials)
        updateStatusText(after: .milliseconds(200))
        if quotaViewModel.errorMessage == "登录已过期，请重新登录" {
            authState = .expired
            updateStatusText()
        }
    }

    /// Start refresh if not already running (prevents duplicate timers)
    func startRefreshIfNeeded() {
        print("[DevBar] ⑦ startRefreshIfNeeded, hasCredentials=\(credentials != nil)")
        quotaViewModel.startAutoRefresh(
            credentials: credentials,
            interval: refreshInterval,
            onFetchComplete: { [weak self] in
                self?.updateStatusText(after: .milliseconds(200))
            }
        )
    }

    func stopAutoRefresh() {
        quotaViewModel.stopAutoRefresh()
    }

    var isHiddenFromDock: Bool {
        UserDefaults.standard.bool(forKey: Constants.Defaults.hideFromDockKey)
    }

    func setHiddenFromDock(_ hide: Bool) {
        UserDefaults.standard.set(hide, forKey: Constants.Defaults.hideFromDockKey)
        NSApplication.shared.setActivationPolicy(hide ? .accessory : .regular)
    }
}

private extension Double {
    var nonZero: Double? {
        self > 0 ? self : nil
    }
}
