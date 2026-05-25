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
    let mimoQuotaViewModel = MimoQuotaViewModel()
    let updateViewModel = UpdateViewModel()
    let notificationService = NotificationService()
    let weChatViewModel = WeChatViewModel()
    let deviceRelayManager = DeviceRelayManager()
    let antiSleepService = AntiSleepService()
    private var statusTextUpdateTask: Task<Void, Never>?
    private var antiSleepStatusCancellable: AnyCancellable?
    /// Prevents duplicate handleLoginSuccess calls
    private var isHandlingLogin = false
    private var settingsWindow: NSWindow?
    private var previousGLMNotificationItems: [NotificationQuotaItem]?
    private var previousOpenAINotificationItems: [NotificationQuotaItem]?
    private var hasLaunched = false
    private var handledRelayRequestIDs: Set<String> = []
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
        case .mimo:
            let token = KeychainService.shared.load(key: DevBarCoreConstants.Keychain.mimoServiceTokenKey)
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
    @Published private(set) var antiSleepStatus: AntiSleepService.Status = .disabled

    var antiSleepStatusText: String {
        switch antiSleepStatus {
        case .disabled:
            String(localized: "prevent_sleep_status_disabled")
        case .desktopHolding:
            String(localized: "prevent_sleep_status_desktop_enabled")
        case .portableOpenHolding:
            String(localized: "prevent_sleep_status_portable_open")
        case .portableClosedReleased:
            String(localized: "prevent_sleep_status_portable_closed")
        }
    }

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
            accountConfigs = UserDefaultsAccountSettingsStore.normalizedConfigs(configs)
        } else {
            accountConfigs = UserDefaultsAccountSettingsStore.defaultConfigs
        }

        menuBarIcon = UserDefaults.standard.string(forKey: Constants.Defaults.menuBarIconKey)
            ?? Constants.Defaults.defaultMenuBarIcon
        launchAtLogin = UserDefaults.standard.bool(forKey: Constants.Defaults.launchAtLoginKey)
        isHiddenFromDock = UserDefaults.standard.bool(forKey: Constants.Defaults.hideFromDockKey)
        antiSleepEnabled = UserDefaults.standard.bool(forKey: Constants.Defaults.antiSleepEnabledKey)
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
        deviceRelayManager.messageHandler = { [weak self] message in
            Task { @MainActor [weak self] in
                await self?.handleRelayMessage(message)
            }
        }
        antiSleepStatus = antiSleepService.status
        antiSleepStatusCancellable = antiSleepService.$status
            .receive(on: RunLoop.main)
            .sink { [weak self] status in
                Task { @MainActor [weak self] in
                    self?.antiSleepStatus = status
                }
            }
        antiSleepService.setEnabled(antiSleepEnabled)

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

        if isProviderEnabled(.mimo) {
            let token = KeychainService.shared.load(key: DevBarCoreConstants.Keychain.mimoServiceTokenKey)
            if let token, !token.isEmpty {
                Task { @MainActor [weak self] in
                    await mimoQuotaViewModel.fetchUsage(storedServiceToken: token, silent: true)
                    self?.checkAndNotify()
                }
            }
        }

        // Setup WeChat service if enabled
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.weChatViewModel.setup()
        }

        Task { @MainActor [weak self] in
            guard let self else { return }
            let relayEnabled = UserDefaults.standard.object(forKey: DevBarCoreConstants.Defaults.relayMacEnabledKey) == nil ||
                UserDefaults.standard.bool(forKey: DevBarCoreConstants.Defaults.relayMacEnabledKey)
            if relayEnabled {
                await self.deviceRelayManager.setup(deviceType: .mac, deviceName: Self.currentDeviceName)
            }
        }
    }

    private static var currentDeviceName: String {
        Host.current().localizedName ?? ProcessInfo.processInfo.hostName
    }

    private func handleRelayMessage(_ message: DeviceRelayMessage) async {
        switch message.type {
        case .agentCommand:
            await handleRelayAgentCommand(message)
        case .systemLockScreen:
            await handleRelayLockScreenCommand(message)
        case .systemWakeDisplay:
            await handleRelaySystemCommand(message, commandType: "wakeDisplay") {
                try MacSystemCommandExecutor.wakeDisplay()
            }
        case .systemDisplaySleep:
            await handleRelaySystemCommand(message, commandType: "displaySleep") {
                try MacSystemCommandExecutor.displaySleep()
            }
        case .systemStatusRequest:
            await handleRelayStatusRequest(message)
        default:
            return
        }
    }

    private func handleRelayAgentCommand(_ message: DeviceRelayMessage) async {
        guard message.type == .agentCommand else { return }
        guard let requestId = message.requestId, !handledRelayRequestIDs.contains(requestId) else { return }
        guard let sourceDeviceId = message.fromDeviceId else { return }
        let prompt = message.payload["prompt"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !prompt.isEmpty else {
            await sendRelayAgentFailure(
                requestId: requestId,
                targetDeviceId: sourceDeviceId,
                errorCode: "EMPTY_PROMPT",
                message: "任务内容为空"
            )
            return
        }

        handledRelayRequestIDs.insert(requestId)
        await sendRelayAgentProgress(
            requestId: requestId,
            targetDeviceId: sourceDeviceId,
            message: "Mac 已收到任务"
        )

        do {
            let agentName = message.payload["agent"]?.trimmingCharacters(in: .whitespacesAndNewlines)
            let reply = try await weChatViewModel.agentRouter.route(
                agentName: agentName?.isEmpty == false ? agentName : nil,
                userID: "relay:\(sourceDeviceId)",
                message: prompt
            )
            try await deviceRelayManager.send(
                DeviceRelayMessage(
                    type: .agentDone,
                    requestId: requestId,
                    fromDeviceId: deviceRelayManager.localDeviceID,
                    targetDeviceId: sourceDeviceId,
                    payload: [
                        "status": "done",
                        "summary": reply,
                    ]
                )
            )
        } catch {
            await sendRelayAgentFailure(
                requestId: requestId,
                targetDeviceId: sourceDeviceId,
                errorCode: "AGENT_FAILED",
                message: error.localizedDescription
            )
        }
    }

    private func sendRelayAgentProgress(requestId: String, targetDeviceId: String, message: String) async {
        do {
            try await deviceRelayManager.send(
                DeviceRelayMessage(
                    type: .agentProgress,
                    requestId: requestId,
                    fromDeviceId: deviceRelayManager.localDeviceID,
                    targetDeviceId: targetDeviceId,
                    payload: [
                        "status": "running",
                        "message": message,
                    ]
                )
            )
        } catch {
            print("[DevBar:DeviceRelay] agent.progress send failed: \(error)")
        }
    }

    private func sendRelayAgentFailure(
        requestId: String,
        targetDeviceId: String,
        errorCode: String,
        message: String
    ) async {
        do {
            try await deviceRelayManager.send(
                DeviceRelayMessage(
                    type: .agentFailed,
                    requestId: requestId,
                    fromDeviceId: deviceRelayManager.localDeviceID,
                    targetDeviceId: targetDeviceId,
                    payload: [
                        "errorCode": errorCode,
                        "message": message,
                    ]
                )
            )
        } catch {
            print("[DevBar:DeviceRelay] agent.failed send failed: \(error)")
        }
    }

    private func handleRelayLockScreenCommand(_ message: DeviceRelayMessage) async {
        if let targetDeviceId = message.targetDeviceId,
           targetDeviceId != deviceRelayManager.localDeviceID {
            return
        }
        guard let requestId = message.requestId,
              !handledRelayRequestIDs.contains(requestId) else {
            return
        }

        handledRelayRequestIDs.insert(requestId)
        print("[DevBar:DeviceRelay] lock screen requested from=\(message.fromDeviceId ?? "-") requestId=\(requestId)")

        do {
            try MacSystemCommandExecutor.lockScreen()
            if let sourceDeviceId = message.fromDeviceId {
                await sendRelaySystemStatus(
                    requestId: requestId,
                    targetDeviceId: sourceDeviceId
                )
            }
        } catch {
            print("[DevBar:DeviceRelay] lock screen failed: \(error)")
            if let sourceDeviceId = message.fromDeviceId {
                await sendRelayAgentFailure(
                    requestId: requestId,
                    targetDeviceId: sourceDeviceId,
                    errorCode: "LOCK_SCREEN_FAILED",
                    message: error.localizedDescription
                )
            }
        }
    }

    private func handleRelaySystemCommand(
        _ message: DeviceRelayMessage,
        commandType: String,
        execute: () throws -> Void
    ) async {
        if let targetDeviceId = message.targetDeviceId,
           targetDeviceId != deviceRelayManager.localDeviceID {
            return
        }
        guard let requestId = message.requestId,
              !handledRelayRequestIDs.contains(requestId) else {
            return
        }

        handledRelayRequestIDs.insert(requestId)
        print("[DevBar:DeviceRelay] \(commandType) requested from=\(message.fromDeviceId ?? "-") requestId=\(requestId)")

        do {
            try execute()
            if let sourceDeviceId = message.fromDeviceId {
                await sendRelaySystemStatus(
                    requestId: requestId,
                    targetDeviceId: sourceDeviceId
                )
            }
        } catch {
            print("[DevBar:DeviceRelay] \(commandType) failed: \(error)")
            if let sourceDeviceId = message.fromDeviceId {
                await sendRelayAgentFailure(
                    requestId: requestId,
                    targetDeviceId: sourceDeviceId,
                    errorCode: "\(commandType.uppercased())_FAILED",
                    message: error.localizedDescription
                )
            }
        }
    }

    private func handleRelayStatusRequest(_ message: DeviceRelayMessage) async {
        if let targetDeviceId = message.targetDeviceId,
           targetDeviceId != deviceRelayManager.localDeviceID {
            return
        }
        guard let sourceDeviceId = message.fromDeviceId else { return }
        await sendRelaySystemStatus(
            requestId: message.requestId,
            targetDeviceId: sourceDeviceId
        )
    }

    private func sendRelaySystemStatus(requestId: String?, targetDeviceId: String) async {
        do {
            try await deviceRelayManager.sendSystemStatus(
                targetDeviceId: targetDeviceId,
                requestId: requestId,
                screenLocked: MacScreenLockStateProvider.isScreenLocked(),
                deviceName: Self.currentDeviceName
            )
        } catch {
            print("[DevBar:DeviceRelay] system.status send failed: \(error)")
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
        case .mimo:
            mimoQuotaViewModel.resetForLogout()
            KeychainService.shared.delete(key: DevBarCoreConstants.Keychain.mimoServiceTokenKey)
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
        let mimoServiceToken = KeychainService.shared.load(key: DevBarCoreConstants.Keychain.mimoServiceTokenKey)
        let mimoCredentials = mimoServiceToken.map {
            ProviderTransferCredentials(token: nil, cookieString: $0)
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
                ProviderTransferPayload(provider: .mimo, credentials: mimoCredentials),
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

        if isProviderEnabled(.mimo), hasAuthenticatedSession(for: .mimo) {
            await mimoQuotaViewModel.fetchUsage(silent: silent)
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

    @Published var antiSleepEnabled: Bool {
        didSet {
            UserDefaults.standard.set(antiSleepEnabled, forKey: Constants.Defaults.antiSleepEnabledKey)
            antiSleepService.setEnabled(antiSleepEnabled)
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
            .environmentObject(mimoQuotaViewModel)
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
