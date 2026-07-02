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

    enum MimoCookieRenewalState: Equatable {
        case idle
        case renewing
        case renewed(Date)
        case needsLogin(String)
        case failed(String)

        var message: String? {
            switch self {
            case .idle:
                return nil
            case .renewing:
                return String(localized: "mimo_cookie_renewal_running")
            case .renewed(let date):
                return String(
                    format: String(localized: "mimo_cookie_renewal_success"),
                    date.formatted(date: .omitted, time: .shortened)
                )
            case .needsLogin(let message), .failed(let message):
                return message
            }
        }

        var isFailure: Bool {
            switch self {
            case .needsLogin, .failed:
                return true
            case .idle, .renewing, .renewed:
                return false
            }
        }
    }

    @Published var authState: AuthState = .loading
    @Published var credentials: AuthCredentials?
    @Published var mimoCookieRenewalState: MimoCookieRenewalState = .idle

    private let authService = AuthService()
    private let mimoCookieRenewalService = MimoCookieRenewalService()
    let quotaViewModel = QuotaViewModel()
    let openAIQuotaViewModel = OpenAIQuotaViewModel()
    let mimoQuotaViewModel = MimoQuotaViewModel()
    let deepSeekQuotaViewModel = DeepSeekQuotaViewModel()
    let updateViewModel = UpdateViewModel()
    let notificationService = NotificationService()
    let weChatViewModel = WeChatViewModel()
    let deviceRelayManager = DeviceRelayManager()
    let antiSleepService = AntiSleepService()
    let agentWatcherService = AgentWatcherService.shared
    private let providerPingSettingsStore = UserDefaultsProviderPingSettingsStore()
    private let providerPingAPIClient = BigModelAPIClient()
    private let providerPingScheduler = ProviderPingScheduler()
    private let providerPingScheduleCalculator = ProviderPingScheduleCalculator()
    private var statusTextUpdateTask: Task<Void, Never>?
    private var antiSleepStatusCancellable: AnyCancellable?
    private var childObservers = Set<AnyCancellable>()
    /// Prevents duplicate handleLoginSuccess calls
    private var isHandlingLogin = false
    private var settingsWindow: NSWindow?
    private var previousGLMNotificationItems: [NotificationQuotaItem]?
    private var previousOpenAINotificationItems: [NotificationQuotaItem]?
    private var hasLaunched = false
    private var handledRelayRequestIDs: Set<String> = []
    private var recentSMSAlertDedupKeys: [String: Date] = [:]
    private var mimoCookieRenewalTimer: Timer?
    weak var languageManager: LanguageManager?

    // MARK: - Account Configs

    @Published var accountConfigs: [AccountConfig] {
        didSet {
            saveAccountConfigs()
            WidgetDataManager.shared.saveEnabledProviders(enabledProviders)
            rescheduleProviderPing()
        }
    }
    @Published var providerAccounts: [ProviderAccount] {
        didSet {
            accountSettingsStore.saveProviderAccounts(providerAccounts)
            // Rebuild via normalizedConfigs so this path matches init() exactly,
            // keeping accountConfigs (menu bar) in lockstep with providerAccounts
            // (settings list).
            accountConfigs = UserDefaultsAccountSettingsStore.normalizedConfigs(
                providerAccounts
                    .reduce(into: [QuotaProvider: AccountConfig]()) { result, account in
                        if result[account.provider] == nil {
                            result[account.provider] = account.legacyConfig
                        }
                    }
                    .values
                    .map { $0 }
            )
        }
    }
    @Published var providerPingConfigs: [ProviderPingConfig] = UserDefaultsProviderPingSettingsStore.defaultConfigs {
        didSet {
            providerPingSettingsStore.saveProviderPingConfigs(providerPingConfigs)
            rescheduleProviderPing()
        }
    }

    private let accountSettingsStore = UserDefaultsAccountSettingsStore()
    private var lastProviderSnapshotPushByPeer: [String: Date] = [:]

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

    var enabledProviderAccounts: [ProviderAccount] {
        providerAccounts
            .filter(\.isEnabled)
            .sorted { $0.order < $1.order }
    }

    func hasAuthenticatedSession(for provider: QuotaProvider) -> Bool {
        switch provider {
        case .glm:
            return effectiveGLMCredentials != nil
        case .openai:
            let token = KeychainService.shared.load(key: Constants.Keychain.openAIAccessTokenKey)
            return token?.isEmpty == false
        case .mimo:
            let token = KeychainService.shared.load(key: DevBarCoreConstants.Keychain.mimoServiceTokenKey)
            return token?.isEmpty == false
        case .deepseek:
            return providerAccounts.contains { account in
                guard account.provider == .deepseek,
                      let credential = KeychainService.shared.loadProviderCredential(for: account) else {
                    return false
                }
                return (credential.token?.isEmpty == false) && (credential.cookieString?.isEmpty == false)
            }
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

    func markMimoCookieUpdated() {
        UserDefaults.standard.set(Date(), forKey: DevBarCoreConstants.Defaults.mimoCookieLastRenewedAtKey)
        UserDefaults.standard.removeObject(forKey: DevBarCoreConstants.Defaults.mimoCookieLastRenewFailedAtKey)
        mimoCookieRenewalState = .renewed(Date())
        updateMimoCookieRenewalTimer()
    }

    func isProviderEnabled(_ provider: QuotaProvider) -> Bool {
        accountConfigs.first(where: { $0.provider == provider })?.isEnabled ?? false
    }

    func providerDisplayTitle(for provider: QuotaProvider) -> String {
        guard let account = providerAccounts
            .filter({ $0.provider == provider && $0.isEnabled })
            .sorted(by: { $0.order < $1.order })
            .first else {
            return provider.localizedName
        }

        let label = account.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !label.isEmpty, label != provider.localizedName else {
            return provider.localizedName
        }
        return "\(provider.localizedName)(\(label))"
    }

    func providerDisplayTitle(for account: ProviderAccount) -> String {
        let label = account.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !label.isEmpty, label != account.provider.localizedName {
            return "\(account.provider.localizedName)(\(label))"
        }

        let siblingAccounts = enabledProviderAccounts.filter { $0.provider == account.provider }
        if siblingAccounts.count > 1,
           let index = siblingAccounts.firstIndex(where: { $0.id == account.id }) {
            return "\(account.provider.localizedName) \(index + 1)"
        }

        return account.provider.localizedName
    }

    func updateAccountConfig(provider: QuotaProvider, isEnabled: Bool) {
        // `providerAccounts` is the source of truth; its didSet rebuilds and
        // persists `accountConfigs`. Writing only `accountConfigs` here would let
        // the two diverge — the settings toggle reads `providerAccounts` while the
        // menu bar reads `accountConfigs`.
        let updatedAccounts = providerAccounts.map { account -> ProviderAccount in
            guard account.provider == provider, account.isEnabled != isEnabled else { return account }
            var updated = account
            updated.isEnabled = isEnabled
            updated.updatedAt = Date()
            return updated
        }
        if updatedAccounts != providerAccounts {
            providerAccounts = updatedAccounts
        } else if let idx = accountConfigs.firstIndex(where: { $0.provider == provider }) {
            // Fallback for providers without a backing account record.
            accountConfigs[idx].isEnabled = isEnabled
        }
        syncAuthState()
        updateStatusText()
        if provider == .mimo {
            updateMimoCookieRenewalTimer()
        }
        if provider == .glm {
            rescheduleProviderPing(checkMissed: isEnabled)
        }
    }

    func updateProviderAccountEnabled(id accountID: String, isEnabled: Bool) {
        guard let index = providerAccounts.firstIndex(where: { $0.id == accountID }) else { return }
        providerAccounts[index].isEnabled = isEnabled
        providerAccounts[index].updatedAt = Date()
        syncAuthState()
        updateStatusText()
        if providerAccounts[index].provider == .mimo {
            updateMimoCookieRenewalTimer()
        }
        if providerAccounts[index].provider == .glm {
            rescheduleProviderPing(checkMissed: isEnabled)
        }
    }

    func updateProviderAccountDisplayName(id accountID: String, displayName: String) {
        guard let index = providerAccounts.firstIndex(where: { $0.id == accountID }) else { return }
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        providerAccounts[index].displayName = trimmed.isEmpty
            ? providerAccounts[index].provider.localizedName
            : trimmed
        providerAccounts[index].updatedAt = Date()
    }

    func updateProviderAccountCredentialSync(id accountID: String, isEnabled: Bool) {
        guard let index = providerAccounts.firstIndex(where: { $0.id == accountID }) else { return }
        providerAccounts[index].syncPolicy.credentialSyncEnabled = isEnabled
        providerAccounts[index].updatedAt = Date()
        if isEnabled {
            broadcastCredentialIfPossible(for: providerAccounts[index])
        }
    }

    @discardableResult
    func saveCredential(
        for accountID: String,
        token: String?,
        cookieString: String?,
        accountIdentifier: String?
    ) -> ProviderAccount? {
        guard let account = providerAccounts.first(where: { $0.id == accountID }) else { return nil }
        let currentRevision = KeychainService.shared.loadProviderCredential(for: account)?.revision ?? 0
        let credential = ProviderCredentialEnvelope(
            accountID: account.id,
            provider: account.provider,
            token: token,
            cookieString: cookieString,
            accountIdentifier: accountIdentifier,
            revision: currentRevision + 1
        )
        guard KeychainService.shared.saveProviderCredential(credential, for: account) else {
            return nil
        }
        broadcastCredentialIfPossible(for: account)
        syncAuthState()
        updateStatusText()
        return account
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
        let restoredProviders = Self.providersWithLegacyStoredCredentials()
        let loadedAccounts = accountSettingsStore.loadProviderAccounts(restoringEnabledProviders: restoredProviders)
        for account in loadedAccounts {
            KeychainService.shared.migrateLegacyCredentialIfNeeded(for: account)
        }
        let configs = UserDefaultsAccountSettingsStore.normalizedConfigs(
            loadedAccounts
                .reduce(into: [QuotaProvider: AccountConfig]()) { result, account in
                    if result[account.provider] == nil {
                        result[account.provider] = account.legacyConfig
                    }
                }
                .values
                .map { $0 }
        )
        providerAccounts = loadedAccounts
        accountConfigs = configs
        providerPingConfigs = providerPingSettingsStore.loadProviderPingConfigs()
        WidgetDataManager.shared.saveEnabledProviders(
            configs
                .filter(\.isEnabled)
                .sorted { $0.order < $1.order }
                .map(\.provider)
        )

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
            if saved.cookieString.isEmpty {
                KeychainService.shared.save(
                    key: DevBarCoreConstants.Keychain.glmAPIKeyKey,
                    value: BigModelAPIClient.normalizedBearerToken(saved.token)
                )
                authService.logout()
                credentials = nil
            } else {
                credentials = saved
            }
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
        providerPingScheduler.onFire = { [weak self] in
            Task { @MainActor in
                await self?.runAutomaticProviderPingIfNeeded()
            }
        }
        providerPingScheduler.onWake = { [weak self] in
            Task { @MainActor in
                await self?.runAutomaticProviderPingIfNeeded()
            }
        }

        if hasAuthenticatedSession(for: .glm) {
            Task { @MainActor [weak self] in
                await Task.yield()
                guard let self else { return }
                await self.quotaViewModel.loadInitialData(credentials: self.effectiveGLMCredentials)
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
                    await self?.refreshMimoQuotaWithAutoRenew(silent: true)
                    self?.checkAndNotify()
                }
            }
        }
        updateMimoCookieRenewalTimer()

        // Load DeepSeek data if enabled
        if isProviderEnabled(.deepseek) {
            if let account = providerAccounts.first(where: { $0.provider == .deepseek }),
               let credential = KeychainService.shared.loadProviderCredential(for: account),
               let token = credential.token, !token.isEmpty,
               let cookie = credential.cookieString, !cookie.isEmpty {
                Task { @MainActor [weak self] in
                    await self?.deepSeekQuotaViewModel.fetchUsage(
                        token: token,
                        cookieString: cookie,
                        silent: true
                    )
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
                await MacPushNotificationCoordinator.shared.syncRegistration(
                    relayDeviceToken: self.deviceRelayManager.deviceToken
                )
            }
        }

        NotificationCenter.default.publisher(for: .macAPNsTokenChanged)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    await MacPushNotificationCoordinator.shared.syncRegistration(
                        relayDeviceToken: self.deviceRelayManager.deviceToken
                    )
                }
            }
            .store(in: &childObservers)

        if DevBarCoreConstants.Features.agentWatcherEnabled {
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.agentWatcherService.relayManager = self.deviceRelayManager
                if self.agentWatcherService.isEnabled {
                    self.agentWatcherService.startServer()
                }
            }

            NotificationCenter.default.addObserver(
                forName: .agentWatcherStatusChanged,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                Task { @MainActor [weak self] in
                    self?.updateMenuBarBadge(from: notification)
                }
            }
        }

        rescheduleProviderPing(checkMissed: true)
    }

    private static func providersWithLegacyStoredCredentials() -> Set<QuotaProvider> {
        var providers: Set<QuotaProvider> = []
        let keychain = KeychainService.shared
        if keychain.load(key: DevBarCoreConstants.Keychain.tokenKey)?.isEmpty == false ||
            keychain.load(key: DevBarCoreConstants.Keychain.glmAPIKeyKey)?.isEmpty == false {
            providers.insert(.glm)
        }
        if keychain.load(key: DevBarCoreConstants.Keychain.openAIAccessTokenKey)?.isEmpty == false {
            providers.insert(.openai)
        }
        if keychain.load(key: DevBarCoreConstants.Keychain.mimoServiceTokenKey)?.isEmpty == false {
            providers.insert(.mimo)
        }
        return providers
    }

    func addProviderAccount(provider: QuotaProvider) -> ProviderAccount {
        let nextOrder = (providerAccounts.map(\.order).max() ?? -1) + 1
        let sameProviderCount = providerAccounts.filter { $0.provider == provider }.count
        let account = ProviderAccount(
            provider: provider,
            displayName: sameProviderCount == 0 ? provider.localizedName : "\(provider.localizedName) \(sameProviderCount + 1)",
            isEnabled: true,
            order: nextOrder
        )
        providerAccounts.append(account)
        return account
    }

    func removeProviderAccount(id accountID: String) {
        guard let account = providerAccounts.first(where: { $0.id == accountID }) else { return }
        KeychainService.shared.deleteProviderCredential(for: account)
        WidgetDataManager.shared.clearQuotaSnapshot(accountID: accountID)
        providerAccounts.removeAll { $0.id == accountID }
        normalizeProviderAccountOrders()
        refreshAuthenticationState()
    }

    func updateProviderAccount(_ account: ProviderAccount) {
        if let index = providerAccounts.firstIndex(where: { $0.id == account.id }) {
            providerAccounts[index] = account
            providerAccounts[index].updatedAt = Date()
        } else {
            providerAccounts.append(account)
        }
    }

    func moveProviderAccount(id accountID: String, to targetAccountID: String) {
        guard accountID != targetAccountID else { return }

        var accounts = providerAccounts.sorted { $0.order < $1.order }
        guard let fromIndex = accounts.firstIndex(where: { $0.id == accountID }),
              let toIndex = accounts.firstIndex(where: { $0.id == targetAccountID }) else {
            return
        }

        let moving = accounts.remove(at: fromIndex)
        accounts.insert(moving, at: toIndex)
        for index in accounts.indices {
            accounts[index].order = index
            accounts[index].updatedAt = Date()
        }
        providerAccounts = accounts
    }

    private func normalizeProviderAccountOrders() {
        providerAccounts.sort { $0.order < $1.order }
        for index in providerAccounts.indices {
            providerAccounts[index].order = index
        }
    }

    private func updateMenuBarBadge(from notification: Notification) {
        guard let userInfo = notification.userInfo,
              let waitingCount = userInfo["waitingCount"] as? Int else {
            return
        }

        // 更新菜单栏 badge
        if waitingCount > 0 {
            statusBarButton?.appearsDisabled = false
            // 可以在这里更新额外的 badge 显示
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
            await sendCurrentProviderSnapshotsIfNeeded(to: message.fromDeviceId)
        case .smsAlert:
            await handleRelaySMSAlert(message)
        case .relayPaired, .relayHeartbeat, .relayPing:
            await sendCurrentProviderSnapshotsIfNeeded(to: message.fromDeviceId)
        default:
            return
        }
    }

    private func handleRelaySMSAlert(_ message: DeviceRelayMessage) async {
        if let targetDeviceId = message.targetDeviceId,
           targetDeviceId != deviceRelayManager.localDeviceID {
            return
        }
        guard let sourceDeviceId = message.fromDeviceId else { return }

        let messageText = message.payload["messageText"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !messageText.isEmpty else {
            await sendRelaySMSAlertAck(
                requestId: message.requestId,
                targetDeviceId: sourceDeviceId,
                status: "ignored",
                detail: "短信内容为空"
            )
            return
        }

        let dedupKey = message.payload["dedupKey"] ?? message.requestId ?? "\(sourceDeviceId)-\(message.timestamp)"
        guard !isDuplicateSMSAlert(dedupKey: dedupKey) else {
            await sendRelaySMSAlertAck(
                requestId: message.requestId,
                targetDeviceId: sourceDeviceId,
                status: "duplicate",
                detail: "重复短信提醒已忽略"
            )
            return
        }
        recordSMSAlertDedupKey(dedupKey)

        let sender = message.payload["sender"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        let customTitle = message.payload["notificationTitle"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        let title: String
        if let customTitle, !customTitle.isEmpty {
            title = customTitle
        } else {
            title = sender?.isEmpty == false ? "短信提醒 · \(sender!)" : "短信提醒"
        }
        let summary = DeviceRelaySMSAlert.summary(for: messageText)
        notificationService.send(title: title, body: summary)

        let safeKey = String(dedupKey.prefix(8))
        print("[DevBar:SMSAlert] shown sender=\(sender ?? "-") length=\(messageText.count) dedup=\(safeKey)")
        await sendRelaySMSAlertAck(
            requestId: message.requestId,
            targetDeviceId: sourceDeviceId,
            status: "shown",
            detail: "Mac 已提醒"
        )
    }

    private func sendRelaySMSAlertAck(
        requestId: String?,
        targetDeviceId: String,
        status: String,
        detail: String
    ) async {
        guard let localDeviceID = deviceRelayManager.localDeviceID else { return }
        do {
            try await deviceRelayManager.send(
                DeviceRelayManager.makeSMSAlertAckMessage(
                    localDeviceID: localDeviceID,
                    targetDeviceId: targetDeviceId,
                    requestId: requestId,
                    status: status,
                    detail: detail
                )
            )
        } catch {
            print("[DevBar:SMSAlert] ack send failed: \(error)")
        }
    }

    private func isDuplicateSMSAlert(dedupKey: String) -> Bool {
        pruneSMSAlertDedupKeys()
        return recentSMSAlertDedupKeys[dedupKey] != nil
    }

    private func recordSMSAlertDedupKey(_ dedupKey: String) {
        pruneSMSAlertDedupKeys()
        recentSMSAlertDedupKeys[dedupKey] = Date()
        if recentSMSAlertDedupKeys.count > 100 {
            let sortedKeys = recentSMSAlertDedupKeys.sorted { $0.value < $1.value }.map(\.key)
            for key in sortedKeys.prefix(recentSMSAlertDedupKeys.count - 100) {
                recentSMSAlertDedupKeys.removeValue(forKey: key)
            }
        }
    }

    private func pruneSMSAlertDedupKeys() {
        let cutoff = Date().addingTimeInterval(-300)
        recentSMSAlertDedupKeys = recentSMSAlertDedupKeys.filter { $0.value >= cutoff }
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
                displayAwake: MacDisplayStateProvider.isDisplayAwake(),
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

        guard authService.saveCredentials(credentials) else {
            print("[DevBar] ⑥① Keychain save failed")
            isHandlingLogin = false
            return
        }
        self.credentials = credentials
        upsertCredentialForPrimaryAccount(
            provider: .glm,
            token: credentials.token,
            cookieString: credentials.cookieString,
            accountIdentifier: nil
        )
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
        mimoCookieRenewalTimer?.invalidate()
        print("[DevBar] AppViewModel DEINIT")
    }

    func logout(provider: QuotaProvider) {
        statusTextUpdateTask?.cancel()
        switch provider {
        case .glm:
            quotaViewModel.resetForLogout()
            credentials = nil
            authService.logout()
            KeychainService.shared.delete(key: DevBarCoreConstants.Keychain.glmAPIKeyKey)
        case .openai:
            openAIQuotaViewModel.resetForLogout()
            KeychainService.shared.delete(key: Constants.Keychain.openAIAccessTokenKey)
        case .mimo:
            mimoQuotaViewModel.resetForLogout()
            KeychainService.shared.delete(key: DevBarCoreConstants.Keychain.mimoServiceTokenKey)
            for account in providerAccounts where account.provider == .mimo {
                KeychainService.shared.deleteProviderCredential(for: account)
                WidgetDataManager.shared.clearQuotaSnapshot(accountID: account.id)
            }
            mimoCookieRenewalState = .idle
            updateMimoCookieRenewalTimer()
        case .deepseek:
            deepSeekQuotaViewModel.resetForLogout()
            for account in providerAccounts where account.provider == .deepseek {
                KeychainService.shared.deleteProviderCredential(for: account)
                WidgetDataManager.shared.clearQuotaSnapshot(accountID: account.id)
            }
        }
        refreshAuthenticationState()
        if provider == .glm {
            rescheduleProviderPing()
        }
    }

    func makeTransferPayload(expirationInterval: TimeInterval = 300) -> TransferPayload {
        let exportedAt = Date()
        let glmCredentials = effectiveGLMCredentials.map {
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
        let primaryMimoAccountID = providerAccounts
            .filter { $0.provider == .mimo }
            .sorted { $0.order < $1.order }
            .first?.id

        let accounts = providerAccounts.sorted { $0.order < $1.order }.map { account in
            let credential = KeychainService.shared.loadProviderCredential(for: account)
            let accountCredentials: ProviderTransferCredentials?
            if account.provider == .mimo, account.id == primaryMimoAccountID {
                accountCredentials = Self.transferCredentials(
                    token: credential?.token,
                    cookieString: mimoServiceToken ?? credential?.cookieString
                )
            } else {
                accountCredentials = Self.transferCredentials(
                    token: credential?.token,
                    cookieString: credential?.cookieString
                )
            }
            return ProviderAccountTransferPayload(
                id: account.id,
                provider: account.provider,
                displayName: account.displayName,
                isEnabled: account.isEnabled,
                order: account.order,
                credentials: accountCredentials,
                accountIdentifier: credential?.accountIdentifier ?? account.providerAccountIdentifier,
                credentialRevision: credential?.revision ?? 1
            )
        }

        return TransferPayload(
            schemaVersion: 2,
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
            ],
            accounts: accounts
        )
    }

    private static func transferCredentials(token: String?, cookieString: String?) -> ProviderTransferCredentials? {
        let trimmedToken = token?.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCookie = cookieString?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedToken?.isEmpty == false || trimmedCookie?.isEmpty == false else {
            return nil
        }
        return ProviderTransferCredentials(token: trimmedToken, cookieString: trimmedCookie)
    }

    @discardableResult
    func upsertCredentialForPrimaryAccount(
        provider: QuotaProvider,
        token: String?,
        cookieString: String?,
        accountIdentifier: String?
    ) -> ProviderAccount {
        let account: ProviderAccount
        if let existing = providerAccounts.first(where: { $0.provider == provider }) {
            account = existing
        } else {
            account = addProviderAccount(provider: provider)
        }
        let currentRevision = KeychainService.shared.loadProviderCredential(for: account)?.revision ?? 0
        let credential = ProviderCredentialEnvelope(
            accountID: account.id,
            provider: provider,
            token: token,
            cookieString: cookieString,
            accountIdentifier: accountIdentifier,
            revision: currentRevision + 1
        )
        _ = KeychainService.shared.saveProviderCredential(credential, for: account)
        broadcastCredentialIfPossible(for: account)
        return account
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
        if isProviderEnabled(.glm), let glmCredentials = effectiveGLMCredentials {
            await quotaViewModel.fetchQuota(credentials: glmCredentials, silent: silent)
            await broadcastQuotaSnapshotIfPossible(for: .glm)
            updateStatusText(after: .milliseconds(200))
            if quotaViewModel.errorMessage == String(localized: "login_expired") {
                authState = hasAuthenticatedSession(for: .openai) ? .loggedIn : .expired
                updateStatusText()
            }
        }

        if isProviderEnabled(.openai), hasAuthenticatedSession(for: .openai) {
            await openAIQuotaViewModel.fetchUsage(silent: true)
            await broadcastQuotaSnapshotIfPossible(for: .openai)
        }

        if isProviderEnabled(.mimo), hasAuthenticatedSession(for: .mimo) {
            await refreshMimoQuotaWithAutoRenew(silent: silent)
            await broadcastQuotaSnapshotIfPossible(for: .mimo)
        }

        if isProviderEnabled(.deepseek), hasAuthenticatedSession(for: .deepseek) {
            if let account = providerAccounts.first(where: { $0.provider == .deepseek }),
               let credential = KeychainService.shared.loadProviderCredential(for: account),
               let token = credential.token, !token.isEmpty,
               let cookie = credential.cookieString, !cookie.isEmpty {
                await deepSeekQuotaViewModel.fetchUsage(
                    token: token,
                    cookieString: cookie,
                    silent: silent
                )
                await broadcastQuotaSnapshotIfPossible(for: .deepseek)
            }
        }

        checkAndNotify()
    }

    private func refreshMimoQuotaWithAutoRenew(silent: Bool) async {
        guard let serviceToken = KeychainService.shared.load(key: DevBarCoreConstants.Keychain.mimoServiceTokenKey),
              !serviceToken.isEmpty else {
            mimoQuotaViewModel.errorMessage = String(localized: "mimo_cookie_required")
            return
        }

        do {
            _ = try await mimoQuotaViewModel.fetchUsage(serviceToken: serviceToken, silent: silent)
            await mimoQuotaViewModel.fetchPlanDetailIfNeeded(serviceToken: serviceToken)
        } catch APIError.mimoCookieExpired {
            await renewMimoCookieAndRetryUsage(silent: silent)
        } catch {
            return
        }
    }

    private func renewMimoCookieAndRetryUsage(silent: Bool) async {
        mimoCookieRenewalState = .renewing
        let result = await mimoCookieRenewalService.forceRenew(reason: .apiExpired)
        await handleMimoCookieRenewalResult(result, retryUsage: true, silent: silent)
    }

    private func handleMimoCookieRenewalResult(
        _ result: MimoCookieRenewalResult,
        retryUsage: Bool,
        silent: Bool
    ) async {
        switch result {
        case .skipped:
            mimoCookieRenewalState = .idle
        case .renewed(let cookie), .unchanged(let cookie):
            mimoCookieRenewalState = .renewed(Date())
            upsertCredentialForPrimaryAccount(
                provider: .mimo,
                token: nil,
                cookieString: cookie,
                accountIdentifier: nil
            )
            guard retryUsage else { return }
            do {
                _ = try await mimoQuotaViewModel.fetchUsage(serviceToken: cookie, silent: silent)
                await mimoQuotaViewModel.fetchPlanDetailIfNeeded(serviceToken: cookie)
            } catch let error as APIError {
                mimoQuotaViewModel.errorMessage = error.errorDescription
                if case .mimoCookieExpired = error {
                    mimoCookieRenewalState = .needsLogin(String(localized: "mimo_cookie_renewal_needs_login"))
                }
            } catch {
                mimoQuotaViewModel.errorMessage = error.localizedDescription
            }
        case .needsLogin(let message):
            mimoCookieRenewalState = .needsLogin(message)
            mimoQuotaViewModel.errorMessage = message
        case .failed(let message):
            mimoCookieRenewalState = .failed(message)
            mimoQuotaViewModel.errorMessage = message
        }
    }

    private func updateMimoCookieRenewalTimer() {
        mimoCookieRenewalTimer?.invalidate()
        mimoCookieRenewalTimer = nil

        guard isProviderEnabled(.mimo), hasAuthenticatedSession(for: .mimo) else { return }

        mimoCookieRenewalTimer = Timer.scheduledTimer(withTimeInterval: 6 * 60 * 60, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.renewMimoCookieIfNeededFromTimer()
            }
        }

        Task { @MainActor [weak self] in
            await self?.renewMimoCookieIfNeededFromTimer(reason: .startup)
        }
    }

    private func renewMimoCookieIfNeededFromTimer(reason: MimoCookieRenewalReason = .timer) async {
        guard isProviderEnabled(.mimo), hasAuthenticatedSession(for: .mimo) else { return }

        let result = await mimoCookieRenewalService.renewIfNeeded(reason: reason)
        if result != .skipped {
            await handleMimoCookieRenewalResult(result, retryUsage: false, silent: true)
        }
    }

    private func broadcastQuotaSnapshotIfPossible(for provider: QuotaProvider) async {
        guard let account = providerAccounts.first(where: { $0.provider == provider && $0.syncPolicy.quotaSyncEnabled }),
              let snapshot = makeQuotaSnapshot(for: account) else {
            return
        }

        WidgetDataManager.shared.saveQuotaSnapshot(snapshot)

        let peers = await providerSyncIPhonePeers()
        guard let localDeviceID = deviceRelayManager.localDeviceID else { return }

        for peer in peers {
            await sendProviderQuotaSnapshot(snapshot, account: account, to: peer, localDeviceID: localDeviceID)
        }
    }

    private func broadcastCredentialIfPossible(for account: ProviderAccount) {
        guard account.syncPolicy.credentialSyncEnabled,
              let credential = KeychainService.shared.loadProviderCredential(for: account) else {
            return
        }

        Task { @MainActor [weak self] in
            guard let self else { return }
            let peers = await self.providerSyncIPhonePeers()
            guard let localDeviceID = self.deviceRelayManager.localDeviceID else { return }

            for peer in peers {
                do {
                    let accountMessage = try DeviceRelayManager.makeProviderAccountUpsertMessage(
                        localDeviceID: localDeviceID,
                        targetDeviceId: peer.deviceId,
                        account: account
                    )
                    try await self.deviceRelayManager.send(accountMessage)

                    let message = try DeviceRelayManager.makeProviderCredentialUpdateMessage(
                        localDeviceID: localDeviceID,
                        targetDeviceId: peer.deviceId,
                        credential: credential
                    )
                    try await self.deviceRelayManager.send(message)
                } catch {
                    print("[DevBar:ProviderSync] credential send failed peer=\(peer.deviceId) account=\(credential.accountID.suffix(6)) \(error)")
                }
            }
        }
    }

    private func providerSyncIPhonePeers() async -> [DeviceRelayDevice] {
        if deviceRelayManager.localDeviceID == nil || deviceRelayManager.deviceToken == nil {
            await deviceRelayManager.setup(deviceType: .mac, deviceName: Self.currentDeviceName)
        } else {
            await deviceRelayManager.resumeConnectivity(deviceType: .mac, deviceName: Self.currentDeviceName)
        }

        let peers = deviceRelayManager.peers.filter { $0.deviceType == .iPhone }
        if peers.isEmpty {
            print("[DevBar:ProviderSync] no iPhone peers available after refresh")
        }
        return peers
    }

    private func sendCurrentProviderSnapshotsIfNeeded(to peerDeviceID: String?) async {
        guard let peerDeviceID,
              peerDeviceID != deviceRelayManager.localDeviceID,
              let peer = deviceRelayManager.peers.first(where: { $0.deviceId == peerDeviceID && $0.deviceType == .iPhone }),
              let localDeviceID = deviceRelayManager.localDeviceID else {
            return
        }

        let now = Date()
        if let lastPushed = lastProviderSnapshotPushByPeer[peerDeviceID],
           now.timeIntervalSince(lastPushed) < 20 {
            return
        }
        lastProviderSnapshotPushByPeer[peerDeviceID] = now

        for account in providerAccounts
            .filter({ $0.isEnabled && $0.syncPolicy.quotaSyncEnabled })
            .sorted(by: { $0.order < $1.order }) {
            guard let snapshot = makeQuotaSnapshot(for: account)
                ?? WidgetDataManager.shared.loadQuotaSnapshot(accountID: account.id) else {
                continue
            }
            await sendProviderQuotaSnapshot(snapshot, account: account, to: peer, localDeviceID: localDeviceID)
        }
    }

    private func sendProviderQuotaSnapshot(
        _ snapshot: ProviderQuotaSnapshot,
        account: ProviderAccount,
        to peer: DeviceRelayDevice,
        localDeviceID: String
    ) async {
        do {
            let accountMessage = try DeviceRelayManager.makeProviderAccountUpsertMessage(
                localDeviceID: localDeviceID,
                targetDeviceId: peer.deviceId,
                account: account
            )
            try await deviceRelayManager.send(accountMessage)

            let message = try DeviceRelayManager.makeProviderQuotaSnapshotMessage(
                localDeviceID: localDeviceID,
                targetDeviceId: peer.deviceId,
                snapshot: snapshot
            )
            try await deviceRelayManager.send(message)
        } catch {
            print("[DevBar:ProviderSync] quota send failed peer=\(peer.deviceId) account=\(snapshot.accountID.suffix(6)) \(error)")
        }
    }

    private func makeQuotaSnapshot(for account: ProviderAccount) -> ProviderQuotaSnapshot? {
        switch account.provider {
        case .glm:
            guard let limits = quotaViewModel.quotaData?.limits,
                  let fetchedAt = quotaViewModel.lastUpdated else { return nil }
            return ProviderQuotaSnapshot(
                accountID: account.id,
                provider: .glm,
                displayName: account.displayName,
                limits: limits.map { $0.toWidgetLimit() },
                level: quotaViewModel.quotaData?.level,
                subscriptionName: quotaViewModel.subscription?.productName,
                subscriptionExpireDate: quotaViewModel.subscription?.formattedNextRenewDate,
                fetchedAt: fetchedAt,
                sourceDeviceID: deviceRelayManager.localDeviceID
            )
        case .openai:
            guard let fetchedAt = openAIQuotaViewModel.lastUpdated else { return nil }
            return ProviderQuotaSnapshot(
                accountID: account.id,
                provider: .openai,
                displayName: account.displayName,
                limits: openAIQuotaViewModel.quotaRows.map {
                    WidgetQuotaLimit(
                        type: $0.name,
                        displayName: $0.name,
                        percentage: $0.percentage,
                        unitDescription: $0.unitDescription,
                        formattedResetTime: $0.resetTime
                    )
                },
                level: openAIQuotaViewModel.planType,
                subscriptionName: nil,
                subscriptionExpireDate: nil,
                availableResetCount: openAIQuotaViewModel.availableResetCount,
                fetchedAt: fetchedAt,
                sourceDeviceID: deviceRelayManager.localDeviceID
            )
        case .mimo:
            guard let fetchedAt = mimoQuotaViewModel.lastUpdated else { return nil }
            return ProviderQuotaSnapshot(
                accountID: account.id,
                provider: .mimo,
                displayName: account.displayName,
                limits: mimoQuotaViewModel.quotaRows.map {
                    WidgetQuotaLimit(
                        type: $0.name,
                        displayName: $0.name,
                        percentage: $0.percentage,
                        unitDescription: $0.unitDescription,
                        formattedResetTime: $0.resetTime
                    )
                },
                level: mimoQuotaViewModel.planName,
                subscriptionName: mimoQuotaViewModel.planName,
                subscriptionExpireDate: mimoQuotaViewModel.planDetail?.currentPeriodEnd,
                fetchedAt: fetchedAt,
                sourceDeviceID: deviceRelayManager.localDeviceID
            )
        case .deepseek:
            guard let data = deepSeekQuotaViewModel.usageData,
                  let fetchedAt = deepSeekQuotaViewModel.lastUpdated else { return nil }
            return ProviderQuotaSnapshot(
                accountID: account.id,
                provider: .deepseek,
                displayName: account.displayName,
                limits: data.quotaRows.map {
                    WidgetQuotaLimit(
                        type: $0.name,
                        displayName: $0.name,
                        percentage: $0.percentage,
                        unitDescription: $0.unitDescription,
                        formattedResetTime: nil
                    )
                },
                level: nil,
                subscriptionName: nil,
                subscriptionExpireDate: nil,
                fetchedAt: fetchedAt,
                sourceDeviceID: deviceRelayManager.localDeviceID
            )
        }
    }

    /// Start refresh if not already running (prevents duplicate timers)
    func startRefreshIfNeeded() {
        guard refreshInterval > 0 else { return } // Don't start if "Never"
        guard let glmCredentials = effectiveGLMCredentials else { return }
        print("[DevBar] ⑦ startRefreshIfNeeded, hasCredentials=\(glmCredentials.token.isEmpty == false)")
        quotaViewModel.startAutoRefresh(
            credentials: glmCredentials,
            interval: refreshInterval,
            onFetchComplete: { [weak self] in
                self?.updateStatusText(after: .milliseconds(200))
                self?.checkAndNotify()
            }
        )
    }

    private func checkAndNotify() {
        guard DevBarCoreConstants.Features.notificationRemindersEnabled else { return }
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

    var glmAPIKeyForModelCall: String? {
        if let key = KeychainService.shared.load(key: DevBarCoreConstants.Keychain.glmAPIKeyKey) {
            let normalized = BigModelAPIClient.normalizedBearerToken(key)
            if !normalized.isEmpty {
                return normalized
            }
        }

        guard let account = providerAccounts.first(where: { $0.provider == .glm }),
              let credential = KeychainService.shared.loadProviderCredential(for: account),
              credential.cookieString?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false,
              let token = credential.token else {
            return nil
        }

        let normalized = BigModelAPIClient.normalizedBearerToken(token)
        return normalized.isEmpty ? nil : normalized
    }

    var effectiveGLMCredentials: AuthCredentials? {
        if let credentials,
           !credentials.token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           !credentials.cookieString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return credentials
        }

        guard let glmAPIKeyForModelCall else { return nil }
        return AuthCredentials(token: glmAPIKeyForModelCall, cookieString: "")
    }

    func saveGLMAPIKey(_ rawValue: String) {
        let normalized = BigModelAPIClient.normalizedBearerToken(rawValue)
        guard !normalized.isEmpty else { return }

        KeychainService.shared.save(key: DevBarCoreConstants.Keychain.glmAPIKeyKey, value: normalized)
        authService.logout()
        credentials = nil
        upsertCredentialForPrimaryAccount(
            provider: .glm,
            token: normalized,
            cookieString: nil,
            accountIdentifier: nil
        )
        if !isProviderEnabled(.glm) {
            updateAccountConfig(provider: .glm, isEnabled: true)
        }
        refreshAuthenticationState()
        startRefreshIfNeeded()
        rescheduleProviderPing(checkMissed: true)
    }

    func providerPingConfig(for provider: QuotaProvider) -> ProviderPingConfig {
        providerPingConfigs.first(where: { $0.provider == provider }) ?? .defaultGLM
    }

    func updateProviderPingConfig(_ config: ProviderPingConfig) {
        if let index = providerPingConfigs.firstIndex(where: { $0.provider == config.provider }) {
            providerPingConfigs[index] = config
        } else {
            providerPingConfigs.append(config)
        }
    }

    func testProviderPing(_ provider: QuotaProvider) async throws {
        guard provider == .glm, let apiKey = glmAPIKeyForModelCall else {
            throw APIError.notLoggedIn
        }

        do {
            try await providerPingAPIClient.sendPing(apiKey: apiKey)
            recordProviderPingResult(provider: provider, automatic: false, errorMessage: nil)
        } catch {
            recordProviderPingResult(
                provider: provider,
                automatic: false,
                errorMessage: sanitizedPingErrorMessage(error)
            )
            throw error
        }
    }

    private func runAutomaticProviderPingIfNeeded() async {
        let config = providerPingConfig(for: .glm)
        defer { rescheduleProviderPing() }

        guard providerPingScheduleCalculator.shouldRunAutomaticPing(for: config, now: Date()),
              isProviderEnabled(.glm),
              let apiKey = glmAPIKeyForModelCall else {
            return
        }

        do {
            try await providerPingAPIClient.sendPing(apiKey: apiKey)
            recordProviderPingResult(provider: .glm, automatic: true, errorMessage: nil)
        } catch {
            recordProviderPingResult(
                provider: .glm,
                automatic: true,
                errorMessage: sanitizedPingErrorMessage(error)
            )
        }
    }

    private func recordProviderPingResult(provider: QuotaProvider, automatic: Bool, errorMessage: String?) {
        var config = providerPingConfig(for: provider)
        let now = Date()
        if automatic {
            config.lastAutomaticRunDay = providerPingScheduleCalculator.todayKey(now: now)
            config.lastAutomaticRunAt = now
        } else {
            config.lastTestAt = now
        }

        if let errorMessage {
            config.lastErrorMessage = errorMessage
        } else {
            config.lastSuccessAt = now
            config.lastErrorMessage = nil
        }
        updateProviderPingConfig(config)
    }

    private func rescheduleProviderPing(checkMissed: Bool = false) {
        guard let config = providerPingConfigs.first(where: { $0.provider == .glm }),
              config.isEnabled,
              isProviderEnabled(.glm),
              glmAPIKeyForModelCall != nil else {
            providerPingScheduler.stop()
            return
        }

        providerPingScheduler.schedule(config: config)
        if checkMissed {
            Task { @MainActor [weak self] in
                await self?.runAutomaticProviderPingIfNeeded()
            }
        }
    }

    private func sanitizedPingErrorMessage(_ error: Error) -> String {
        if let apiError = error as? APIError {
            return apiError.errorDescription ?? String(describing: apiError)
        }
        return error.localizedDescription
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
            .environmentObject(deepSeekQuotaViewModel)
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
