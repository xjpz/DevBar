import Combine
import DevBarCore
import Foundation
import Security
import SwiftUI
import UIKit
import UserNotifications

enum IOSScannedCodeResolution {
    case macPaired
    case accountBinding(DeviceAccountBindScan)
    case providerTransfer(preview: TransferImportPreview, relayURL: URL?)
}

enum IOSDebugLogger {
    private static let processStart = CFAbsoluteTimeGetCurrent()

    static func log(_ scope: String, _ message: String) {
        print("[DevBar:iOS:\(scope)] t=\(timestamp()) \(message)")
    }

    private static func timestamp() -> String {
        String(format: "%.3f", CFAbsoluteTimeGetCurrent() - processStart)
    }
}

@MainActor
final class IOSAppViewModel: ObservableObject {
    private var isApplyingSyncedPushPreferences = false
    enum RefreshTrigger {
        case launch
        case foreground
        case manual
        case importTransfer
    }

    enum TabSelection: Hashable {
        case dashboard
        case tool(String)
        case tools

        var debugLabel: String {
            switch self {
            case .dashboard:
                return "dashboard"
            case .tool(let id):
                return "tool.\(id)"
            case .tools:
                return "tools"
            }
        }
    }

    enum DevBarLiveMessageStatus: Equatable {
        case notReady
        case ready
        case enabling
        case active
        case failed(String)

        var title: String {
            switch self {
            case .notReady:
                String(localized: "ios_live_message_status_not_ready_title")
            case .ready:
                String(localized: "ios_live_message_status_ready_title")
            case .enabling:
                String(localized: "ios_live_message_status_enabling_title")
            case .active:
                String(localized: "ios_live_message_status_active_title")
            case .failed:
                String(localized: "ios_live_message_status_failed_title")
            }
        }

        var detail: String {
            switch self {
            case .notReady:
                String(localized: "ios_live_message_status_not_ready_detail")
            case .ready:
                String(localized: "ios_live_message_status_ready_detail")
            case .enabling:
                String(localized: "ios_live_message_status_enabling_detail")
            case .active:
                String(localized: "ios_live_message_status_active_detail")
            case .failed(let message):
                message
            }
        }
    }

    @Published var selectedTab: TabSelection = .dashboard {
        didSet {
            handleSelectedTabChange(from: oldValue)
        }
    }
    @Published var accountConfigs: [AccountConfig] {
        didSet {
            settingsStore.saveAccountConfigs(accountConfigs)
            WidgetDataManager.shared.saveEnabledProviders(enabledProviders)
            Task { await syncLiveActivity() }
        }
    }
    @Published var providerAccounts: [ProviderAccount] {
        didSet {
            settingsStore.saveProviderAccounts(providerAccounts)
            accountConfigs = providerAccounts
                .reduce(into: [QuotaProvider: AccountConfig]()) { result, account in
                    if result[account.provider] == nil {
                        result[account.provider] = account.legacyConfig
                    }
                }
                .values
                .sorted { $0.order < $1.order }
        }
    }
    @Published var glmCredentials: AuthCredentials?
    @Published private(set) var lastRefreshTrigger: RefreshTrigger?
    @Published private(set) var isRefreshingQuota = false
    @Published var refreshInterval: TimeInterval {
        didSet {
            UserDefaults.standard.set(refreshInterval, forKey: DevBarCoreConstants.Defaults.refreshIntervalKey)
            restartQuotaAutoRefreshTimerIfNeeded()
        }
    }
    @Published var liveActivitySettings: LiveActivitySettings {
        didSet {
            liveActivitySettingsStore.save(liveActivitySettings)
            Task { await syncLiveActivity() }
        }
    }
    @Published var hermesSettings: HermesSettings {
        didSet {
            if !isApplyingICloudSyncedHermesSettings {
                hermesSettingsStore.save(hermesSettings)
            }
        }
    }
    @Published private(set) var hermesSettingsRevision = 0
    @Published private(set) var pinnedToolTabIDs: [String]
    @Published var pushNotificationPreferences: PushNotificationPreferences {
        didSet {
            guard !isApplyingSyncedPushPreferences else { return }
            if !DevBarCoreConstants.Features.agentWatcherEnabled,
               pushNotificationPreferences.agentWatcherEnabled {
                pushNotificationPreferences.agentWatcherEnabled = false
                return
            }
            Task {
                await IOSPushNotificationCoordinator.shared.syncPreferences(
                    pushNotificationPreferences,
                    relayDeviceToken: deviceRelayManager.deviceToken
                )
            }
        }
    }

    func updateBadgeEnabled(_ enabled: Bool) async throws {
        var candidate = pushNotificationPreferences
        candidate.badgeEnabled = enabled
        let saved = try await IOSPushNotificationCoordinator.shared.updatePreferences(
            candidate,
            relayDeviceToken: deviceRelayManager.deviceToken
        )
        isApplyingSyncedPushPreferences = true
        pushNotificationPreferences = saved
        isApplyingSyncedPushPreferences = false
    }
    @Published var relayDeviceName: String {
        didSet {
            let normalized = Self.normalizedRelayDeviceName(relayDeviceName)
            UserDefaults.standard.set(normalized, forKey: DevBarCoreConstants.Defaults.relayIPhoneDeviceNameKey)
            if relayDeviceName != normalized {
                relayDeviceName = normalized
            } else {
                syncMacThemeWidgetSnapshot()
                Task {
                    await deviceRelayManager.resumeConnectivity(deviceType: .iPhone, deviceName: normalized)
                }
            }
        }
    }
    @Published var macThemeWidgetUserName: String {
        didSet {
            let normalized = Self.normalizedMacThemeWidgetUserName(macThemeWidgetUserName)
            UserDefaults.standard.set(normalized, forKey: DevBarCoreConstants.Defaults.macThemeWidgetUserNameKey)
            if macThemeWidgetUserName != normalized {
                macThemeWidgetUserName = normalized
            } else {
                syncMacThemeWidgetSnapshot()
            }
        }
    }
    @Published private(set) var macThemeWidgetAvatarFileName: String?
    @Published private(set) var availableHomeScreenShortcutActions: [DeviceRelayHomeScreenShortcutAction]
    @Published private(set) var selectedHomeScreenShortcutActions: [DeviceRelayHomeScreenShortcutAction]
    @Published private(set) var dashboardScanRequestID: UUID?
    @Published private(set) var devBarLiveMessageStatus: DevBarLiveMessageStatus = .ready
    @Published private(set) var syncedQuotaSnapshots: [String: ProviderQuotaSnapshot]
    @Published var devBarLiveMessageDraft: String = ""

    let quotaViewModel = QuotaViewModel()
    let openAIQuotaViewModel = OpenAIQuotaViewModel()
    let mimoQuotaViewModel = MimoQuotaViewModel()
    let deepSeekQuotaViewModel = DeepSeekQuotaViewModel()
    let deviceRelayManager = DeviceRelayManager()

    private let authService = AuthService()
    private let settingsStore = UserDefaultsAccountSettingsStore()
    private let liveActivitySettingsStore = LiveActivitySettingsStore()
    private let hermesSettingsStore: UserDefaultsHermesSettingsStore
    private let toolTabStore = IOSToolTabStore()
    private let macThemeWidgetAvatarStore = MacThemeWidgetAvatarStore()
    private var childObservers = Set<AnyCancellable>()
    private var hasStartedDeferredLaunchWork = false
    private var hasRefreshedOnLaunch = false
    private var isLaunchRefreshInProgress = false
    private var deferredLaunchRefreshTask: Task<Void, Never>?
    private var activeLaunchRefreshTask: Task<Void, Never>?
    private var deferredHermesInteractionEndTask: Task<Void, Never>?
    private var hermesNavigationReservationTask: Task<Void, Never>?
    private var hasPendingHermesNavigationReservation = false
    private var isApplyingICloudSyncedHermesSettings = false
    private var hermesChatActivityDepth = 0
    private var quotaRefreshTimer: Timer?
    private var isQuotaAutoRefreshActive = false
    private var latestQuotaRefreshAttemptByProvider: [QuotaProvider: Date] = [:]
    private var providerQuotaOperationThrottle = ProviderQuotaOperationThrottle()
    private var usesDefaultHomeScreenShortcutSelection: Bool
    private var hasPairedMacForShortcuts = false
    private var relayStartupTask: Task<Void, Never>?
    private var diagnosticsFlushTask: Task<Void, Never>?
    private var diagnosticsFlushRequestedWhileRunning = false
    private var lastMacThemeStatusRequestAt: Date?
    private let macThemeStatusRequestCooldown: TimeInterval = 60
    private let macThemeSystemMetricsTTL: TimeInterval = 120

    init() {
        let accounts = settingsStore.loadProviderAccounts(
            restoringEnabledProviders: Self.providersWithStoredCredentials()
        )
        for account in accounts {
            KeychainService.shared.migrateLegacyCredentialIfNeeded(for: account)
        }
        let configs = UserDefaultsAccountSettingsStore.normalizedConfigs(
            accounts
                .reduce(into: [QuotaProvider: AccountConfig]()) { result, account in
                    if result[account.provider] == nil {
                        result[account.provider] = account.legacyConfig
                    }
                }
                .values
                .map { $0 }
        )
        self.providerAccounts = accounts
        self.accountConfigs = configs
        WidgetDataManager.shared.saveEnabledProviders(
            configs
                .filter(\.isEnabled)
                .sorted { $0.order < $1.order }
                .map(\.provider)
        )
        self.glmCredentials = authService.credentials
        self.refreshInterval = UserDefaults.standard.double(forKey: DevBarCoreConstants.Defaults.refreshIntervalKey)
            .nonZero ?? DevBarCoreConstants.Defaults.defaultRefreshInterval
        self.liveActivitySettings = liveActivitySettingsStore.load()
        let hermesStore = UserDefaultsHermesSettingsStore()
        self.hermesSettingsStore = hermesStore
        self.hermesSettings = hermesStore.load()
        self.pinnedToolTabIDs = toolTabStore.load()
        var pushPreferences = IOSPushNotificationCoordinator.shared.loadPreferences()
        if !DevBarCoreConstants.Features.agentWatcherEnabled {
            pushPreferences.agentWatcherEnabled = false
        }
        self.pushNotificationPreferences = pushPreferences
        let relayDeviceName = Self.loadRelayDeviceName()
        self.relayDeviceName = relayDeviceName
        DiagnosticLogger.shared.configure(
            platform: "ios",
            deviceName: relayDeviceName,
            osName: UIDevice.current.systemName,
            osVersion: UIDevice.current.systemVersion
        )
        DiagnosticLogger.shared.record(
            level: .info,
            category: "diagnostics",
            name: "diagnostics_bootstrap",
            message: "iOS diagnostics initialized",
            tags: ["diagnostics"],
            details: [
                "relayBaseURL": DevBarCoreConstants.DeviceRelay.baseURL,
                "hasRelayDeviceName": String(!relayDeviceName.isEmpty),
            ]
        )
        self.macThemeWidgetUserName = Self.loadMacThemeWidgetUserName()
        self.macThemeWidgetAvatarFileName = Self.loadMacThemeWidgetAvatarFileName()
        let storedShortcutActions = IOSHomeScreenShortcutPreferences.loadSelectedActions()
        self.usesDefaultHomeScreenShortcutSelection = storedShortcutActions == nil
        self.selectedHomeScreenShortcutActions = storedShortcutActions
            ?? DeviceRelayHomeScreenShortcutPolicy.defaultSelection(hasPairedMac: false)
        self.availableHomeScreenShortcutActions = DeviceRelayHomeScreenShortcutPolicy.availableActions(hasPairedMac: false)
        self.syncedQuotaSnapshots = Self.loadSyncedQuotaSnapshots(for: accounts)
        bindChildViewModels()
        NotificationCenter.default.publisher(for: .iosAPNsTokenChanged)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    await IOSPushNotificationCoordinator.shared.syncRegistration(
                        relayDeviceToken: self.deviceRelayManager.deviceToken
                    )
                }
            }
            .store(in: &childObservers)
        NotificationCenter.default.publisher(for: .iosLiveActivityPushToStartTokenChanged)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    await IOSPushNotificationCoordinator.shared.syncLiveActivityPushToStart(
                        relayDeviceToken: self.deviceRelayManager.deviceToken,
                        force: true
                    )
                    self.refreshDevBarLiveMessageReadiness()
                }
            }
            .store(in: &childObservers)
        NotificationCenter.default.publisher(for: .iCloudSyncedPreferencesDidChange)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.isApplyingICloudSyncedHermesSettings = true
                    self.hermesSettings = self.hermesSettingsStore.load()
                    self.isApplyingICloudSyncedHermesSettings = false
                    self.hermesSettingsRevision += 1
                }
            }
            .store(in: &childObservers)
        NotificationCenter.default.publisher(for: .homeAssistantDiagnosticRecorded)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.scheduleDiagnosticsFlush(after: .milliseconds(750))
                }
            }
            .store(in: &childObservers)
    }

    private static func providersWithStoredCredentials(
        keychain: KeychainService = .shared
    ) -> Set<QuotaProvider> {
        var providers: Set<QuotaProvider> = []
        if keychain.load(key: DevBarCoreConstants.Keychain.tokenKey)?.isEmpty == false {
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

    private static func loadSyncedQuotaSnapshots(for accounts: [ProviderAccount]) -> [String: ProviderQuotaSnapshot] {
        var result: [String: ProviderQuotaSnapshot] = [:]
        for account in accounts {
            if let snapshot = WidgetDataManager.shared.loadQuotaSnapshot(accountID: account.id) {
                result[account.id] = snapshot
            }
        }
        return result
    }

    var enabledProviders: [QuotaProvider] {
        accountConfigs
            .filter(\.isEnabled)
            .sorted { $0.order < $1.order }
            .map(\.provider)
    }

    var openAIAccessToken: String {
        KeychainService.shared.load(key: DevBarCoreConstants.Keychain.openAIAccessTokenKey) ?? ""
    }

    var openAIAccountId: String {
        settingsStore.loadOpenAIAccountId() ?? ""
    }

    var mimoServiceToken: String {
        let accountToken = providerAccounts
            .filter { $0.provider == .mimo && $0.isEnabled }
            .sorted { $0.order < $1.order }
            .compactMap { KeychainService.shared.loadProviderCredential(for: $0)?.cookieString }
            .first
        if let accountToken {
            return accountToken
        }

        return KeychainService.shared.load(key: DevBarCoreConstants.Keychain.mimoServiceTokenKey) ?? ""
    }

    var hermesAPIKey: String {
        KeychainService.shared.load(key: DevBarCoreConstants.Keychain.hermesAPIKeyKey) ?? ""
    }

    var isHermesConfigured: Bool {
        HermesAPIClient.chatURL(from: hermesSettings.apiBaseURL) != nil && !hermesAPIKey.isEmpty
    }

    var chatTabProvider: ChatBotProviderKind {
        hermesSettings.normalizedChatTabProvider
    }

    var toolsChatProviders: [ChatBotProviderKind] {
        hermesSettings.toolsChatProviders
    }

    func resolvedPinnedToolTabs(availableToolIDs: [String]) -> [String] {
        IOSToolTabSelection.resolvedPinnedTabs(
            savedIDs: pinnedToolTabIDs,
            availableIDs: availableToolIDs
        )
    }

    func isToolPinnedToTab(_ id: String, availableToolIDs: [String]) -> Bool {
        resolvedPinnedToolTabs(availableToolIDs: availableToolIDs).contains(id)
    }

    func canPinMoreTools(availableToolIDs: [String]) -> Bool {
        resolvedPinnedToolTabs(availableToolIDs: availableToolIDs).count < IOSToolTabSelection.defaultLimit
    }

    @discardableResult
    func addPinnedToolTab(_ id: String, availableToolIDs: [String]) -> Bool {
        let updatedIDs = IOSToolTabSelection.adding(
            id,
            to: pinnedToolTabIDs,
            availableIDs: availableToolIDs
        )

        guard updatedIDs != resolvedPinnedToolTabs(availableToolIDs: availableToolIDs) else {
            pinnedToolTabIDs = updatedIDs
            toolTabStore.save(updatedIDs)
            return false
        }

        pinnedToolTabIDs = updatedIDs
        toolTabStore.save(updatedIDs)
        return true
    }

    func removePinnedToolTab(_ id: String, availableToolIDs: [String]) {
        let updatedIDs = IOSToolTabSelection.resolvedPinnedTabs(
            savedIDs: IOSToolTabSelection.removing(id, from: pinnedToolTabIDs),
            availableIDs: availableToolIDs
        )

        pinnedToolTabIDs = updatedIDs
        toolTabStore.save(updatedIDs)

        if selectedTab == .tool(id) {
            selectedTab = .dashboard
        }
    }

    func isChatProviderConfigured(_ provider: ChatBotProviderKind) -> Bool {
        isHermesConfigured
    }

    func syncedQuotaSnapshot(for provider: QuotaProvider) -> ProviderQuotaSnapshot? {
        providerAccounts
            .filter { $0.provider == provider }
            .sorted { $0.order < $1.order }
            .compactMap { syncedQuotaSnapshots[$0.id] }
            .first
    }

    func preferredSyncedQuotaSnapshot(for provider: QuotaProvider, localLastUpdated: Date?) -> ProviderQuotaSnapshot? {
        guard let snapshot = syncedQuotaSnapshot(for: provider),
              !snapshot.limits.isEmpty else {
            return nil
        }
        return snapshot.shouldReplace(existing: nil, localLastUpdated: localLastUpdated) ? snapshot : nil
    }

    private func localQuotaLastUpdated(for provider: QuotaProvider) -> Date? {
        switch provider {
        case .glm:
            return quotaViewModel.lastUpdated
        case .openai:
            return openAIQuotaViewModel.lastUpdated
        case .mimo:
            return mimoQuotaViewModel.lastUpdated
        case .deepseek:
            return deepSeekQuotaViewModel.lastUpdated
        }
    }

    private func latestQuotaRefreshDate(for provider: QuotaProvider) -> Date? {
        let localDate = localQuotaLastUpdated(for: provider)
        let syncedDate = syncedQuotaSnapshots.values
            .filter { $0.provider == provider }
            .map(\.fetchedAt)
            .max()
        return [localDate, syncedDate].compactMap { $0 }.max()
    }

    func hasAuthenticatedSession(for provider: QuotaProvider) -> Bool {
        switch provider {
        case .glm:
            return glmCredentials?.token.isEmpty == false
        case .openai:
            return !openAIAccessToken.isEmpty
        case .mimo:
            return !mimoServiceToken.isEmpty
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

    func isProviderEnabled(_ provider: QuotaProvider) -> Bool {
        accountConfigs.first(where: { $0.provider == provider })?.isEnabled ?? false
    }

    func updateProvider(_ provider: QuotaProvider, enabled: Bool) {
        guard let index = accountConfigs.firstIndex(where: { $0.provider == provider }) else { return }
        accountConfigs[index].isEnabled = enabled
        for accountIndex in providerAccounts.indices where providerAccounts[accountIndex].provider == provider {
            providerAccounts[accountIndex].isEnabled = enabled
            providerAccounts[accountIndex].updatedAt = Date()
            break
        }
    }

    func moveProvider(_ provider: QuotaProvider, to target: QuotaProvider) {
        guard provider != target else { return }

        var configs = accountConfigs.sorted { $0.order < $1.order }
        guard let fromIndex = configs.firstIndex(where: { $0.provider == provider }),
              let toIndex = configs.firstIndex(where: { $0.provider == target }) else {
            return
        }

        let moving = configs.remove(at: fromIndex)
        configs.insert(moving, at: toIndex)
        accountConfigs = configs
        normalizeOrders()
    }

    func moveProviders(fromOffsets source: IndexSet, toOffset destination: Int) {
        var configs = accountConfigs.sorted { $0.order < $1.order }
        configs.move(fromOffsets: source, toOffset: destination)
        accountConfigs = configs
        normalizeOrders()
    }

    func moveProviderUp(_ provider: QuotaProvider) {
        guard let currentIndex = accountConfigs.firstIndex(where: { $0.provider == provider }),
              currentIndex > 0 else { return }
        accountConfigs.swapAt(currentIndex, currentIndex - 1)
        normalizeOrders()
    }

    func moveProviderDown(_ provider: QuotaProvider) {
        guard let currentIndex = accountConfigs.firstIndex(where: { $0.provider == provider }),
              currentIndex < accountConfigs.count - 1 else { return }
        accountConfigs.swapAt(currentIndex, currentIndex + 1)
        normalizeOrders()
    }

    func refreshOnLaunch() async {
        guard !hasRefreshedOnLaunch, !isLaunchRefreshInProgress else {
            debugLog("launch refresh skip refreshed=\(hasRefreshedOnLaunch) inProgress=\(isLaunchRefreshInProgress)")
            return
        }
        guard !shouldDeferAutomaticLaunchRefresh else {
            debugLog("launch refresh skip route=\(selectedTab.debugLabel) depth=\(hermesChatActivityDepth)")
            return
        }
        guard !Task.isCancelled else { return }
        isLaunchRefreshInProgress = true
        defer { isLaunchRefreshInProgress = false }
        let start = CFAbsoluteTimeGetCurrent()
        debugLog("launch refresh begin")
        await refreshAll(trigger: .launch, silent: true)
        guard !Task.isCancelled else {
            debugLog("launch refresh cancelled dt=\(elapsedMilliseconds(since: start))ms")
            return
        }
        debugLog("launch refresh end dt=\(elapsedMilliseconds(since: start))ms")
        hasRefreshedOnLaunch = true
        await refreshHomeScreenShortcuts()
    }

    func startDeferredLaunchWork() async {
        guard !hasStartedDeferredLaunchWork else { return }
        hasStartedDeferredLaunchWork = true
        debugLog("deferred launch work begin route=\(selectedTab.debugLabel)")

        try? await Task.sleep(for: .milliseconds(800))

        await startRelayIfNeeded()
        flushDiagnosticsInBackground()
        debugLog("deferred launch work relay ready route=\(selectedTab.debugLabel)")
        syncPushStateInBackground(force: true)
        refreshDevBarLiveMessageReadiness()
        await refreshHomeScreenShortcuts()
        syncMacThemeWidgetSnapshot()
        scheduleDeferredLaunchRefresh()
        debugLog("deferred launch work end route=\(selectedTab.debugLabel)")
    }

    func reserveHermesChatInteraction(reason: String) {
        if hasPendingHermesNavigationReservation {
            cancelLaunchRefreshForHermes(reason: "reservation refresh \(reason)")
            scheduleHermesNavigationReservationTimeout()
            debugLog("hermes reservation refreshed reason=\(reason) depth=\(hermesChatActivityDepth)")
            return
        }

        hasPendingHermesNavigationReservation = true
        beginHermesChatInteraction(reason: "reservation \(reason)")
        scheduleHermesNavigationReservationTimeout()
        debugLog("hermes reservation begin reason=\(reason) depth=\(hermesChatActivityDepth)")
    }

    func claimHermesChatInteractionReservation(reason: String) -> Bool {
        guard hasPendingHermesNavigationReservation else { return false }
        hasPendingHermesNavigationReservation = false
        hermesNavigationReservationTask?.cancel()
        hermesNavigationReservationTask = nil
        cancelLaunchRefreshForHermes(reason: "reservation claimed \(reason)")
        debugLog("hermes reservation claimed reason=\(reason) depth=\(hermesChatActivityDepth)")
        return true
    }

    func beginHermesChatInteraction(reason: String = "screen") {
        if let deferredHermesInteractionEndTask {
            deferredHermesInteractionEndTask.cancel()
            self.deferredHermesInteractionEndTask = nil
            debugLog("hermes interaction end cancelled by nested begin reason=\(reason) depth=\(hermesChatActivityDepth)")
        } else {
            hermesChatActivityDepth += 1
        }
        debugLog("hermes interaction begin reason=\(reason) depth=\(hermesChatActivityDepth)")
        cancelLaunchRefreshForHermes(reason: "interaction \(reason)")
    }

    func endHermesChatInteraction() {
        guard deferredHermesInteractionEndTask == nil else { return }
        debugLog("hermes interaction end scheduled depth=\(hermesChatActivityDepth)")
        deferredHermesInteractionEndTask = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled else {
                self.deferredHermesInteractionEndTask = nil
                self.debugLog("hermes interaction end cancelled before commit")
                return
            }
            self.hermesChatActivityDepth = max(0, self.hermesChatActivityDepth - 1)
            self.deferredHermesInteractionEndTask = nil
            self.debugLog("hermes interaction end depth=\(self.hermesChatActivityDepth)")
            if self.hermesChatActivityDepth == 0,
               self.hasStartedDeferredLaunchWork,
               !self.hasRefreshedOnLaunch {
                self.scheduleDeferredLaunchRefresh()
            }
        }
    }

    var isHermesToolSelectionActive: Bool {
        switch selectedTab {
        case .tools, .tool("chatbot-hermes"):
            return true
        case .dashboard, .tool:
            return false
        }
    }

    func forceEndHermesChatInteraction(reason: String) {
        deferredHermesInteractionEndTask?.cancel()
        deferredHermesInteractionEndTask = nil
        hermesNavigationReservationTask?.cancel()
        hermesNavigationReservationTask = nil
        hasPendingHermesNavigationReservation = false
        hermesChatActivityDepth = 0
        debugLog("hermes interaction force end reason=\(reason)")
        if hasStartedDeferredLaunchWork, !hasRefreshedOnLaunch {
            scheduleDeferredLaunchRefresh()
        }
    }

    private func scheduleDeferredLaunchRefresh() {
        guard deferredLaunchRefreshTask == nil else { return }
        debugLog("deferred launch refresh scheduled route=\(selectedTab.debugLabel) depth=\(hermesChatActivityDepth)")
        deferredLaunchRefreshTask = Task(priority: .utility) { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else {
                self.deferredLaunchRefreshTask = nil
                self.debugLog("deferred launch refresh cancelled before wake")
                return
            }
            while self.shouldDeferAutomaticLaunchRefresh || self.isLaunchRefreshInProgress {
                self.debugLog("deferred launch refresh waiting route=\(self.selectedTab.debugLabel) depth=\(self.hermesChatActivityDepth) inProgress=\(self.isLaunchRefreshInProgress)")
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else {
                    self.deferredLaunchRefreshTask = nil
                    self.debugLog("deferred launch refresh cancelled while waiting")
                    return
                }
            }
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else {
                self.deferredLaunchRefreshTask = nil
                self.debugLog("deferred launch refresh cancelled before start")
                return
            }
            self.debugLog("deferred launch refresh starting")
            let refreshTask = Task(priority: .utility) { @MainActor [weak self] in
                guard let self else { return }
                await self.refreshOnLaunch()
            }
            self.activeLaunchRefreshTask = refreshTask
            await refreshTask.value
            self.activeLaunchRefreshTask = nil
            self.deferredLaunchRefreshTask = nil
        }
    }

    private var shouldDeferAutomaticLaunchRefresh: Bool {
        hermesChatActivityDepth > 0 || isAutomaticRefreshDeferred(for: selectedTab)
    }

    private func isAutomaticRefreshDeferred(for tab: TabSelection) -> Bool {
        switch tab {
        case .tools, .tool("chatbot-hermes"):
            return true
        case .dashboard, .tool:
            return false
        }
    }

    private func handleSelectedTabChange(from oldValue: TabSelection) {
        guard oldValue != selectedTab else { return }
        debugLog("selected tab changed from=\(oldValue.debugLabel) to=\(selectedTab.debugLabel)")

        if case .tool("chatbot-hermes") = selectedTab {
            reserveHermesChatInteraction(reason: "tab selection")
            return
        }

        if isAutomaticRefreshDeferred(for: selectedTab) {
            cancelLaunchRefreshForHermes(reason: "tab selection \(selectedTab.debugLabel)")
            return
        }

        if isAutomaticRefreshDeferred(for: oldValue),
           hasStartedDeferredLaunchWork,
           !hasRefreshedOnLaunch {
            scheduleDeferredLaunchRefresh()
        }
    }

    private func cancelLaunchRefreshForHermes(reason: String) {
        guard !hasRefreshedOnLaunch else { return }
        let hadDeferredTask = deferredLaunchRefreshTask != nil
        let hadActiveTask = activeLaunchRefreshTask != nil

        deferredLaunchRefreshTask?.cancel()
        deferredLaunchRefreshTask = nil
        activeLaunchRefreshTask?.cancel()
        activeLaunchRefreshTask = nil

        if hadDeferredTask || hadActiveTask {
            debugLog("launch refresh cancelled reason=\(reason) deferred=\(hadDeferredTask) active=\(hadActiveTask)")
        }
    }

    private func scheduleHermesNavigationReservationTimeout() {
        hermesNavigationReservationTask?.cancel()
        hermesNavigationReservationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .seconds(8))
            guard !Task.isCancelled, self.hasPendingHermesNavigationReservation else { return }
            self.hasPendingHermesNavigationReservation = false
            self.hermesNavigationReservationTask = nil
            self.debugLog("hermes reservation timeout depth=\(self.hermesChatActivityDepth)")
            self.endHermesChatInteraction()
        }
    }

    func refreshOnForeground() async {
        startAutoRefreshIfNeeded()
        guard hasStartedDeferredLaunchWork else { return }
        debugLog("foreground refresh begin route=\(selectedTab.debugLabel) depth=\(hermesChatActivityDepth)")
        guard !shouldDeferAutomaticLaunchRefresh else {
            await syncLiveActivity()
            debugLog("foreground refresh deferred route=\(selectedTab.debugLabel) depth=\(hermesChatActivityDepth)")
            return
        }

        await startRelayIfNeeded(resume: true)
        flushDiagnosticsInBackground()
        syncPushStateInBackground(force: true)
        refreshDevBarLiveMessageReadiness()
        await refreshHomeScreenShortcuts()

        guard refreshInterval > 0 else {
            debugLog("foreground refresh end disabled")
            return
        }
        await refreshStaleProviders(trigger: .foreground, silent: true)
        debugLog("foreground refresh end")
    }

    func startAutoRefreshIfNeeded() {
        isQuotaAutoRefreshActive = true
        guard refreshInterval > 0, quotaRefreshTimer == nil else { return }
        scheduleNextQuotaAutoRefresh()
    }

    private func scheduleNextQuotaAutoRefresh() {
        quotaRefreshTimer?.invalidate()
        quotaRefreshTimer = nil
        guard isQuotaAutoRefreshActive, refreshInterval > 0 else { return }

        let refreshableProviders = enabledProviders.filter { hasAuthenticatedSession(for: $0) }
        let latestRefreshByProvider = Dictionary(
            uniqueKeysWithValues: refreshableProviders.compactMap { provider in
                latestQuotaRefreshDate(for: provider).map { (provider, $0) }
            }
        )
        guard let delay = ProviderQuotaRefreshPolicy.nextRefreshDelay(
            refreshableProviders,
            latestRefreshByProvider: latestRefreshByProvider,
            latestAttemptByProvider: latestQuotaRefreshAttemptByProvider,
            interval: refreshInterval
        ) else { return }

        quotaRefreshTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.quotaRefreshTimer = nil
                await self.refreshStaleProviders(trigger: .foreground, silent: true)
                self.scheduleNextQuotaAutoRefresh()
            }
        }
        debugLog("quota auto refresh scheduled interval=\(refreshInterval) delay=\(delay)")
    }

    func stopAutoRefresh() {
        isQuotaAutoRefreshActive = false
        quotaRefreshTimer?.invalidate()
        quotaRefreshTimer = nil
        debugLog("quota auto refresh stopped")
    }

    private func restartQuotaAutoRefreshTimerIfNeeded() {
        guard isQuotaAutoRefreshActive else { return }
        scheduleNextQuotaAutoRefresh()
    }

    private func startRelayIfNeeded(resume: Bool = false) async {
        if let relayStartupTask {
            await relayStartupTask.value
            return
        }

        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            if resume {
                await self.deviceRelayManager.resumeConnectivity(deviceType: .iPhone, deviceName: self.relayDeviceName)
            } else if self.deviceRelayManager.localDeviceID == nil || self.deviceRelayManager.deviceToken == nil {
                await self.deviceRelayManager.setup(deviceType: .iPhone, deviceName: self.relayDeviceName)
            } else {
                await self.deviceRelayManager.resumeConnectivity(deviceType: .iPhone, deviceName: self.relayDeviceName)
            }
        }

        relayStartupTask = task
        await task.value
        relayStartupTask = nil
        flushDiagnosticsInBackground()
    }

    func flushDiagnosticsInBackground() {
        scheduleDiagnosticsFlush(after: .zero)
    }

    private func scheduleDiagnosticsFlush(after delay: Duration) {
        if diagnosticsFlushTask != nil {
            diagnosticsFlushRequestedWhileRunning = true
            return
        }
        guard let token = deviceRelayManager.deviceToken else {
            print("[DevBar:Diagnostics] iOS flush skipped: missing relay device token")
            return
        }
        DiagnosticLogger.shared.configure(
            platform: "ios",
            deviceId: deviceRelayManager.localDeviceID,
            deviceName: relayDeviceName,
            osName: UIDevice.current.systemName,
            osVersion: UIDevice.current.systemVersion
        )
        diagnosticsFlushTask = Task(priority: .utility) { @MainActor [weak self] in
            if delay != .zero {
                try? await Task.sleep(for: delay)
            }
            guard !Task.isCancelled else {
                self?.finishDiagnosticsFlush()
                return
            }
            do {
                let result = try await DiagnosticsUploadService.shared.flush(deviceToken: token)
                print("[DevBar:Diagnostics] iOS flush accepted=\(result.accepted) duplicate=\(result.duplicate) rejected=\(result.rejected)")
            } catch {
                print("[DevBar:Diagnostics] iOS flush failed: \(error)")
                DiagnosticLogger.shared.record(
                    level: .warning,
                    category: "diagnostics",
                    name: "diagnostics_flush_failed",
                    message: "Diagnostics upload failed",
                    tags: ["diagnostics"],
                    details: [
                        "error": String(describing: error),
                    ]
                )
            }
            self?.finishDiagnosticsFlush()
        }
    }

    private func finishDiagnosticsFlush() {
        diagnosticsFlushTask = nil
        guard diagnosticsFlushRequestedWhileRunning else { return }
        diagnosticsFlushRequestedWhileRunning = false
        scheduleDiagnosticsFlush(after: .milliseconds(250))
    }

    private func syncPushStateInBackground(force: Bool) {
        let token = deviceRelayManager.deviceToken
        Task { @MainActor in
            await IOSPushNotificationCoordinator.shared.syncRegistration(
                relayDeviceToken: token,
                force: force
            )
            await IOSPushNotificationCoordinator.shared.syncLiveActivityPushToStart(
                relayDeviceToken: token,
                force: force
            )
        }
    }

    func refreshAll(trigger: RefreshTrigger = .manual, silent: Bool = false) async {
        let refreshableProviders = enabledProviders.filter { hasAuthenticatedSession(for: $0) }
        await refreshProviders(Set(refreshableProviders), trigger: trigger, silent: silent)
    }

    private func refreshStaleProviders(trigger: RefreshTrigger, silent: Bool) async {
        let refreshableProviders = enabledProviders.filter { hasAuthenticatedSession(for: $0) }
        let latestRefreshByProvider = Dictionary(
            uniqueKeysWithValues: refreshableProviders.compactMap { provider in
                latestQuotaRefreshDate(for: provider).map { (provider, $0) }
            }
        )
        let staleProviders = ProviderQuotaRefreshPolicy.providersNeedingRefresh(
            refreshableProviders,
            latestRefreshByProvider: latestRefreshByProvider,
            interval: refreshInterval
        )
        await refreshProviders(staleProviders, trigger: trigger, silent: silent)
    }

    private func refreshProviders(
        _ providers: Set<QuotaProvider>,
        trigger: RefreshTrigger,
        silent: Bool
    ) async {
        guard !providers.isEmpty else {
            await syncLiveActivity()
            return
        }
        guard !isRefreshingQuota,
              providerQuotaOperationThrottle.shouldStartRefresh() else {
            debugLog("quota refresh skipped trigger=\(trigger.summaryText)")
            await syncLiveActivity()
            return
        }

        isRefreshingQuota = true
        let attemptDate = Date()
        for provider in providers {
            latestQuotaRefreshAttemptByProvider[provider] = attemptDate
        }
        defer {
            isRefreshingQuota = false
            if isQuotaAutoRefreshActive {
                scheduleNextQuotaAutoRefresh()
            }
        }
        lastRefreshTrigger = trigger
        guard !Task.isCancelled else { return }

        let glmRefresh = providers.contains(.glm) && isProviderEnabled(.glm) ? glmCredentials : nil
        let openAIRefresh = providers.contains(.openai) && isProviderEnabled(.openai) && !openAIAccessToken.isEmpty
            ? (accessToken: openAIAccessToken, accountId: settingsStore.loadOpenAIAccountId())
            : nil
        let mimoRefresh = providers.contains(.mimo) && isProviderEnabled(.mimo) && !mimoServiceToken.isEmpty
            ? mimoServiceToken
            : nil
        let deepSeekRefresh = providers.contains(.deepseek) ? deepSeekRefreshCredentials() : nil

        async let glmTask: Void = refreshGLMQuota(credentials: glmRefresh, silent: silent)
        async let openAITask: Void = refreshOpenAIQuota(refresh: openAIRefresh, silent: silent)
        async let mimoTask: Void = refreshMimoQuota(serviceToken: mimoRefresh, silent: silent)
        async let deepSeekTask: Void = refreshDeepSeekQuota(refresh: deepSeekRefresh, silent: silent)

        _ = await (glmTask, openAITask, mimoTask, deepSeekTask)

        guard !Task.isCancelled else { return }
        await syncLiveActivity()
    }

    private func deepSeekRefreshCredentials() -> (token: String, cookieString: String)? {
        guard isProviderEnabled(.deepseek),
              let account = providerAccounts.first(where: { $0.provider == .deepseek }),
              let credential = KeychainService.shared.loadProviderCredential(for: account),
              let token = credential.token, !token.isEmpty,
              let cookie = credential.cookieString, !cookie.isEmpty else {
            return nil
        }
        return (token, cookie)
    }

    private func refreshGLMQuota(credentials: AuthCredentials?, silent: Bool) async {
        guard let credentials else { return }
        if quotaViewModel.subscription == nil && quotaViewModel.quotaData == nil {
            await quotaViewModel.loadInitialData(credentials: credentials)
        } else {
            await quotaViewModel.fetchQuota(credentials: credentials, silent: silent)
        }
    }

    private func refreshOpenAIQuota(
        refresh: (accessToken: String, accountId: String?)?,
        silent: Bool
    ) async {
        guard let refresh else { return }
        await openAIQuotaViewModel.fetchUsage(
            storedAccessToken: refresh.accessToken,
            storedAccountId: refresh.accountId,
            silent: silent
        )
    }

    private func refreshMimoQuota(serviceToken: String?, silent: Bool) async {
        guard let serviceToken else { return }
        await mimoQuotaViewModel.fetchUsage(
            storedServiceToken: serviceToken,
            silent: silent
        )
    }

    private func refreshDeepSeekQuota(
        refresh: (token: String, cookieString: String)?,
        silent: Bool
    ) async {
        guard let refresh else { return }
        await deepSeekQuotaViewModel.fetchUsage(
            token: refresh.token,
            cookieString: refresh.cookieString,
            silent: silent
        )
    }

    func syncLiveActivity() async {
        let outcome = await IOSLiveActivityManager.shared.sync(
            settings: liveActivitySettings,
            configs: accountConfigs,
            dataByProvider: liveActivityProviderData()
        )
        let relayDeviceToken = deviceRelayManager.deviceToken
        if let registration = outcome.registration {
            await IOSPushNotificationCoordinator.shared.syncLiveActivityRegistration(
                registration,
                relayDeviceToken: relayDeviceToken
            )
        }
        for activityId in outcome.endedActivityIDs {
            await IOSPushNotificationCoordinator.shared.unregisterLiveActivity(
                activityId: activityId,
                relayDeviceToken: relayDeviceToken
            )
        }
    }

    private func debugLog(_ message: String) {
        IOSDebugLogger.log("App", message)
    }

    private func elapsedMilliseconds(since start: CFAbsoluteTime) -> Int {
        Int((CFAbsoluteTimeGetCurrent() - start) * 1_000)
    }

    func saveGLMAPIKey(_ rawValue: String) async throws {
        let normalized = normalizeGLMAuthorization(rawValue)
        guard !normalized.isEmpty else {
            throw CredentialsError.emptyGLMAPIKey
        }

        guard await validateGLMToken(normalized) else {
            throw CredentialsError.invalidGLMAPIKey
        }

        let credentials = AuthCredentials(token: normalized, cookieString: "")
        guard authService.saveCredentials(credentials) else {
            throw CredentialsError.keychainSaveFailed
        }
        glmCredentials = credentials
        upsertCredentialForPrimaryAccount(
            provider: .glm,
            token: credentials.token,
            cookieString: credentials.cookieString,
            accountIdentifier: nil
        )
        quotaViewModel.resetForLogout()
        if !isProviderEnabled(.glm) {
            updateProvider(.glm, enabled: true)
        }
        await quotaViewModel.loadInitialData(credentials: credentials)
    }

    func clearGLMCredentials() {
        glmCredentials = nil
        authService.logout()
        quotaViewModel.resetForLogout()
        Task { await syncLiveActivity() }
    }

    func saveOpenAICredentials(accessToken: String, accountId: String) async throws {
        let trimmedToken = accessToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedToken.isEmpty else {
            throw CredentialsError.emptyOpenAIToken
        }

        let trimmedAccountId = accountId.trimmingCharacters(in: .whitespacesAndNewlines)
        _ = try await openAIQuotaViewModel.fetchUsage(
            accessToken: trimmedToken,
            accountId: trimmedAccountId.isEmpty ? nil : trimmedAccountId,
            silent: true
        )

        guard KeychainService.shared.save(
            key: DevBarCoreConstants.Keychain.openAIAccessTokenKey,
            value: trimmedToken
        ) == errSecSuccess else {
            throw CredentialsError.keychainSaveFailed
        }
        settingsStore.saveOpenAIAccountId(trimmedAccountId.isEmpty ? nil : trimmedAccountId)
        upsertCredentialForPrimaryAccount(
            provider: .openai,
            token: trimmedToken,
            cookieString: nil,
            accountIdentifier: trimmedAccountId.isEmpty ? nil : trimmedAccountId
        )
        if !isProviderEnabled(.openai) {
            updateProvider(.openai, enabled: true)
        }
    }

    func clearOpenAICredentials() {
        KeychainService.shared.delete(key: DevBarCoreConstants.Keychain.openAIAccessTokenKey)
        settingsStore.saveOpenAIAccountId(nil)
        openAIQuotaViewModel.resetForLogout()
        Task { await syncLiveActivity() }
    }

    func saveMimoCookie(_ rawValue: String) async throws {
        let credential = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let serviceToken = MimoAPIClient.normalizedServiceToken(from: credential)
        guard !serviceToken.isEmpty else {
            throw CredentialsError.emptyMimoCookie
        }

        _ = try await mimoQuotaViewModel.fetchUsage(serviceToken: credential, silent: true)
        await mimoQuotaViewModel.fetchPlanDetailIfNeeded(serviceToken: credential, force: true)

        guard KeychainService.shared.save(
            key: DevBarCoreConstants.Keychain.mimoServiceTokenKey,
            value: credential
        ) == errSecSuccess else {
            throw CredentialsError.keychainSaveFailed
        }
        upsertCredentialForPrimaryAccount(
            provider: .mimo,
            token: nil,
            cookieString: credential,
            accountIdentifier: nil
        )
        if !isProviderEnabled(.mimo) {
            updateProvider(.mimo, enabled: true)
        }
    }

    func clearMimoCredentials() {
        KeychainService.shared.delete(key: DevBarCoreConstants.Keychain.mimoServiceTokenKey)
        for account in providerAccounts where account.provider == .mimo {
            KeychainService.shared.deleteProviderCredential(for: account)
            WidgetDataManager.shared.clearQuotaSnapshot(accountID: account.id)
            var snapshots = syncedQuotaSnapshots
            snapshots.removeValue(forKey: account.id)
            syncedQuotaSnapshots = snapshots
        }
        mimoQuotaViewModel.resetForLogout()
        Task { await syncLiveActivity() }
    }

    func clearDeepSeekCredentials() {
        for account in providerAccounts where account.provider == .deepseek {
            KeychainService.shared.deleteProviderCredential(for: account)
            WidgetDataManager.shared.clearQuotaSnapshot(accountID: account.id)
            var snapshots = syncedQuotaSnapshots
            snapshots.removeValue(forKey: account.id)
            syncedQuotaSnapshots = snapshots
        }
        deepSeekQuotaViewModel.resetForLogout()
        Task { await syncLiveActivity() }
    }

    func saveHermesSettings(
        apiBaseURL: String,
        apiKey: String,
        hermesModel: String = "",
        hermesProvider: String = "",
        isStreamingEnabled: Bool,
        chatTabProvider: ChatBotProviderKind = .hermes
    ) throws {
        let trimmedBaseURL = apiBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedBaseURL.isEmpty, HermesAPIClient.chatURL(from: trimmedBaseURL) == nil {
            throw CredentialsError.invalidHermesBaseURL
        }

        let trimmedAPIKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedBaseURL.isEmpty, trimmedAPIKey.isEmpty {
            throw CredentialsError.emptyHermesAPIKey
        }

        let trimmedHermesModel = hermesModel.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedHermesProvider = hermesProvider.trimmingCharacters(in: .whitespacesAndNewlines)

        if !trimmedAPIKey.isEmpty,
           KeychainService.shared.save(
            key: DevBarCoreConstants.Keychain.hermesAPIKeyKey,
            value: trimmedAPIKey
           ) != errSecSuccess {
            throw CredentialsError.keychainSaveFailed
        }
        if trimmedAPIKey.isEmpty {
            KeychainService.shared.delete(key: DevBarCoreConstants.Keychain.hermesAPIKeyKey)
        }

        let normalizedSettings = HermesSettings(
            apiBaseURL: trimmedBaseURL,
            hermesModel: trimmedHermesModel,
            hermesProvider: trimmedHermesProvider,
            isStreamingEnabled: isStreamingEnabled,
            chatTabProvider: chatTabProvider,
            hermesChatRemark: hermesSettings.hermesChatRemark,
            hermesChatTag: hermesSettings.hermesChatTag
        )
        hermesSettings = HermesSettings(
            apiBaseURL: normalizedSettings.apiBaseURL,
            hermesModel: normalizedSettings.hermesModel,
            hermesProvider: normalizedSettings.hermesProvider,
            isStreamingEnabled: normalizedSettings.isStreamingEnabled,
            chatTabProvider: normalizedSettings.normalizedChatTabProvider,
            hermesChatRemark: normalizedSettings.hermesChatRemark,
            hermesChatTag: normalizedSettings.hermesChatTag
        )
        hermesSettingsRevision += 1
    }

    func updateHermesModelSelection(model: String?, provider: String?) {
        let trimmedModel = model?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let trimmedProvider = provider?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        hermesSettings = HermesSettings(
            apiBaseURL: hermesSettings.apiBaseURL,
            hermesModel: trimmedModel,
            hermesProvider: trimmedProvider,
            isStreamingEnabled: hermesSettings.isStreamingEnabled,
            chatTabProvider: hermesSettings.normalizedChatTabProvider,
            hermesChatRemark: hermesSettings.hermesChatRemark,
            hermesChatTag: hermesSettings.hermesChatTag
        )
        hermesSettingsRevision += 1
    }

    func updateChatProviderMetadata(provider: ChatBotProviderKind, remark: String, tag: String) {
        let trimmedRemark = remark.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedTag = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        switch provider {
        case .hermes:
            hermesSettings.hermesChatRemark = trimmedRemark
            hermesSettings.hermesChatTag = trimmedTag
        }
        hermesSettingsRevision += 1
    }

    func clearHermesSettings() {
        KeychainService.shared.delete(key: DevBarCoreConstants.Keychain.hermesAPIKeyKey)
        hermesSettings = .defaults
        hermesSettingsRevision += 1
    }

    func saveDeepSeekCredentials(token: String, cookieString: String) async throws {
        let trimmedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCookie = cookieString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedToken.isEmpty, !trimmedCookie.isEmpty else {
            throw CredentialsError.emptyDeepseekToken
        }

        let apiClient = DeepSeekAPIClient()
        _ = try await apiClient.fetchUsage(
            token: trimmedToken,
            cookieString: trimmedCookie
        )

        upsertCredentialForPrimaryAccount(
            provider: .deepseek,
            token: trimmedToken,
            cookieString: trimmedCookie,
            accountIdentifier: nil
        )
        if !isProviderEnabled(.deepseek) {
            updateProvider(.deepseek, enabled: true)
        }
    }

    func prepareTransferImport(from rawValue: String) async throws -> TransferPayload {
        try await TransferPayloadCodec.decodeResolvingRelay(from: rawValue)
    }

    func pairMacDevice(from rawValue: String) async throws {
        try await deviceRelayManager.confirmPairing(from: rawValue, deviceName: relayDeviceName)
        await IOSPushNotificationCoordinator.shared.syncRegistration(relayDeviceToken: deviceRelayManager.deviceToken, force: true)
        await IOSPushNotificationCoordinator.shared.syncLiveActivityPushToStart(relayDeviceToken: deviceRelayManager.deviceToken, force: true)
        await refreshHomeScreenShortcuts()
        syncMacThemeWidgetSnapshot()
    }

    func resolveScannedCode(_ rawValue: String) async throws -> IOSScannedCodeResolution {
        if DeviceAccountBindQRCodeCodec.matchesType(rawValue) {
            let scan = try await deviceRelayManager.previewAccountBinding(
                from: rawValue,
                deviceName: relayDeviceName
            )
            return .accountBinding(scan)
        }

        if DeviceRelayPairQRCodeCodec.canDecode(rawValue) {
            try await pairMacDevice(from: rawValue)
            return .macPaired
        }

        let payload = try await prepareTransferImport(from: rawValue)
        let relayURL = TransferPayloadCodec.isRelayTransferURL(rawValue) ? URL(string: rawValue) : nil
        return .providerTransfer(
            preview: makeTransferImportPreview(for: payload),
            relayURL: relayURL
        )
    }

    private static func loadRelayDeviceName() -> String {
        let stored = UserDefaults.standard.string(forKey: DevBarCoreConstants.Defaults.relayIPhoneDeviceNameKey)
        return normalizedRelayDeviceName(stored ?? UIDevice.current.name)
    }

    private static func normalizedRelayDeviceName(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "iPhone" : trimmed
    }

    private static func loadMacThemeWidgetUserName() -> String {
        let stored = UserDefaults.standard.string(forKey: DevBarCoreConstants.Defaults.macThemeWidgetUserNameKey)
        return normalizedMacThemeWidgetUserName(stored ?? "")
    }

    private static func normalizedMacThemeWidgetUserName(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func loadMacThemeWidgetAvatarFileName() -> String? {
        let fileName = DevBarCoreConstants.AppGroup.macThemeWidgetAvatarFileName
        return MacThemeWidgetAvatarStore().load(fileName: fileName) == nil ? nil : fileName
    }

    var macThemeWidgetAvatarData: Data? {
        macThemeWidgetAvatarStore.load(fileName: macThemeWidgetAvatarFileName)
    }

    func saveMacThemeWidgetAvatarData(_ data: Data) throws {
        macThemeWidgetAvatarFileName = try macThemeWidgetAvatarStore.save(data)
        syncMacThemeWidgetSnapshot()
    }

    func clearMacThemeWidgetAvatar() {
        macThemeWidgetAvatarStore.clear(fileName: macThemeWidgetAvatarFileName)
        macThemeWidgetAvatarFileName = nil
        syncMacThemeWidgetSnapshot()
    }

    private func refreshHomeScreenShortcuts() async {
        let hasPairedMac = await hasPairedMacForHomeScreenShortcut()
        hasPairedMacForShortcuts = hasPairedMac
        availableHomeScreenShortcutActions = DeviceRelayHomeScreenShortcutPolicy.availableActions(hasPairedMac: hasPairedMac)
        if usesDefaultHomeScreenShortcutSelection {
            selectedHomeScreenShortcutActions = DeviceRelayHomeScreenShortcutPolicy.defaultSelection(hasPairedMac: hasPairedMac)
        }
        IOSHomeScreenShortcutController.apply(
            selectedActions: selectedHomeScreenShortcutActions,
            hasPairedMac: hasPairedMac
        )
        syncMacThemeWidgetSnapshot()
    }

    func refreshHomeScreenShortcutsForCurrentState() async {
        await refreshHomeScreenShortcuts()
    }

    func requestDashboardScanner() {
        dashboardScanRequestID = UUID()
    }

    func setHomeScreenShortcutAction(_ action: DeviceRelayHomeScreenShortcutAction, enabled: Bool) {
        var next = DeviceRelayHomeScreenShortcutPolicy.normalizedSelection(
            selectedHomeScreenShortcutActions,
            hasPairedMac: hasPairedMacForShortcuts
        )

        if enabled {
            guard !next.contains(action), next.count < DeviceRelayHomeScreenShortcutPolicy.maxSelectedActions else {
                return
            }
            next.append(action)
        } else {
            next.removeAll { $0 == action }
        }

        usesDefaultHomeScreenShortcutSelection = false
        selectedHomeScreenShortcutActions = next
        IOSHomeScreenShortcutPreferences.saveSelectedActions(next)
        IOSHomeScreenShortcutController.apply(
            selectedActions: selectedHomeScreenShortcutActions,
            hasPairedMac: hasPairedMacForShortcuts
        )
    }

    func canEnableHomeScreenShortcutAction(_ action: DeviceRelayHomeScreenShortcutAction) -> Bool {
        if selectedHomeScreenShortcutActions.contains(action) {
            return true
        }
        let activeSelection = DeviceRelayHomeScreenShortcutPolicy.normalizedSelection(
            selectedHomeScreenShortcutActions,
            hasPairedMac: hasPairedMacForShortcuts
        )
        return activeSelection.count < DeviceRelayHomeScreenShortcutPolicy.maxSelectedActions
    }

    private func hasPairedMacForHomeScreenShortcut() async -> Bool {
        if deviceRelayManager.peers.contains(where: { $0.deviceType == .mac }) {
            return true
        }

        let store = DeviceRelayStore()
        guard let token = store.loadDeviceToken(for: .iPhone), !token.isEmpty else {
            return false
        }

        do {
            let peers = try await DeviceRelayService.shared.fetchPeers(deviceToken: token)
            return peers.contains { $0.deviceType == .mac }
        } catch {
            return false
        }
    }

    private func syncMacThemeWidgetSnapshot() {
        let now = Date()
        let mac = deviceRelayManager.peers.first { $0.deviceType == .mac }
        let macStatus = mac.map { mac in
            let connectionStatus = deviceRelayManager.connectionStatus(for: mac, now: now)
            let screenLocked = deviceRelayManager.screenLocked(for: mac)
            let displayAwake = deviceRelayManager.displayAwake(for: mac)
            let cpuPercent = deviceRelayManager.cpuPercent(for: mac)
            let memoryPercent = deviceRelayManager.memoryPercent(for: mac)
            let networkDownBytesPerSecond = deviceRelayManager.networkDownBytesPerSecond(for: mac)
            let networkUpBytesPerSecond = deviceRelayManager.networkUpBytesPerSecond(for: mac)
            requestMacThemeStatusIfNeeded(
                for: mac,
                connectionStatus: connectionStatus,
                screenLocked: screenLocked,
                displayAwake: displayAwake,
                hasSystemMetrics: cpuPercent != nil ||
                    memoryPercent != nil ||
                    networkDownBytesPerSecond != nil ||
                    networkUpBytesPerSecond != nil,
                now: now
            )
            return MacStatusWidgetSnapshot(
                deviceID: mac.deviceId,
                deviceName: deviceRelayManager.displayName(for: mac),
                isOnline: connectionStatus != .offline,
                lastSeenAt: mac.lastSeenAt.map { Date(timeIntervalSince1970: TimeInterval($0) / 1000) },
                screenState: screenLocked.map { $0 ? .locked : .unlocked } ?? .unknown,
                displayState: macThemeDisplayState(for: displayAwake),
                keepAwakeState: .unknown,
                connectionMode: macThemeConnectionMode(for: connectionStatus),
                batteryPercent: nil,
                cpuPercent: cpuPercent,
                memoryPercent: memoryPercent,
                networkDownBytesPerSecond: networkDownBytesPerSecond,
                networkUpBytesPerSecond: networkUpBytesPerSecond,
                lastUpdated: now
            )
        }

        WidgetDataManager.shared.saveAndReload(
            MacThemeWidgetSnapshot(
                schemaVersion: MacThemeWidgetSnapshot.currentSchemaVersion,
                user: MacThemeWidgetUserSnapshot(
                    displayName: macThemeWidgetUserName.isEmpty ? relayDeviceName : macThemeWidgetUserName,
                    avatarSymbol: "person.crop.circle.fill",
                    avatarFileName: macThemeWidgetAvatarFileName
                ),
                macStatus: macStatus,
                lastUpdated: now
            )
        )
    }

    private func requestMacThemeStatusIfNeeded(
        for mac: DeviceRelayDevice,
        connectionStatus: DeviceRelayPeerConnectionStatus,
        screenLocked: Bool?,
        displayAwake: Bool?,
        hasSystemMetrics: Bool,
        now: Date
    ) {
        guard connectionStatus != .offline else { return }
        let metricsUpdatedAt = deviceRelayManager.systemMetricsUpdatedAt(for: mac)
        let metricsAreStale = metricsUpdatedAt.map { now.timeIntervalSince($0) > macThemeSystemMetricsTTL } ?? true
        guard screenLocked == nil || displayAwake == nil || !hasSystemMetrics || metricsAreStale else { return }
        if let lastMacThemeStatusRequestAt,
           now.timeIntervalSince(lastMacThemeStatusRequestAt) < macThemeStatusRequestCooldown {
            return
        }
        lastMacThemeStatusRequestAt = now

        Task { @MainActor [weak self, deviceID = mac.deviceId] in
            guard let self else { return }
            try? await self.deviceRelayManager.sendSystemStatusRequest(targetDeviceId: deviceID)
        }
    }

    private func macThemeConnectionMode(for status: DeviceRelayPeerConnectionStatus) -> MacWidgetConnectionMode {
        switch status {
        case .local:
            return .local
        case .remote:
            return .relay
        case .offline:
            return .unknown
        }
    }

    private func macThemeDisplayState(for displayAwake: Bool?) -> MacWidgetDisplayState {
        guard let displayAwake else { return .unknown }
        return displayAwake ? .awake : .sleeping
    }

    func makeTransferImportPreview(for payload: TransferPayload) -> TransferImportPreview {
        if payload.schemaVersion >= 2 {
            return TransferImportPlanner.makePreview(
                payload: payload,
                localStates: localProviderStates,
                existingAccounts: providerAccounts
            )
        } else {
            return TransferImportPlanner.makePreview(
                payload: payload,
                localStates: localProviderStates,
                existingConfigs: accountConfigs
            )
        }
    }

    func importTransferPayload(_ payload: TransferPayload) async throws {
        guard !payload.isExpired else {
            throw TransferPayloadError.expired
        }

        if payload.schemaVersion >= 2 {
            try importProviderAccounts(payload.accounts)
            await refreshAll(trigger: .importTransfer, silent: true)
            return
        }

        let importedProviders = Set(payload.importedProviders)
        var mergedConfigs = accountConfigs

        for importedConfig in payload.accountConfigs where importedProviders.contains(importedConfig.provider) {
            if let index = mergedConfigs.firstIndex(where: { $0.provider == importedConfig.provider }) {
                mergedConfigs[index] = importedConfig
            } else {
                mergedConfigs.append(importedConfig)
            }
        }

        mergedConfigs.sort { $0.order < $1.order }
        for index in mergedConfigs.indices {
            mergedConfigs[index].order = index
        }
        accountConfigs = mergedConfigs

        for providerPayload in payload.providers {
            switch providerPayload.provider {
            case .glm:
                if let credentialsPayload = providerPayload.credentials,
                   let token = credentialsPayload.token?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !token.isEmpty {
                    let credentials = AuthCredentials(
                        token: token,
                        cookieString: credentialsPayload.cookieString ?? ""
                    )
                    guard authService.saveCredentials(credentials) else {
                        throw CredentialsError.keychainSaveFailed
                    }
                    glmCredentials = credentials
                } else {
                    authService.logout()
                    glmCredentials = nil
                }
                quotaViewModel.resetForLogout()

            case .openai:
                if let token = providerPayload.credentials?.token?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !token.isEmpty {
                    guard KeychainService.shared.save(
                        key: DevBarCoreConstants.Keychain.openAIAccessTokenKey,
                        value: token
                    ) == errSecSuccess else {
                        throw CredentialsError.keychainSaveFailed
                    }
                } else {
                    KeychainService.shared.delete(key: DevBarCoreConstants.Keychain.openAIAccessTokenKey)
                }

                settingsStore.saveOpenAIAccountId(providerPayload.accountId)
                openAIQuotaViewModel.resetForLogout()

            case .mimo:
                if let cookie = providerPayload.credentials?.cookieString?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !cookie.isEmpty {
                    guard KeychainService.shared.save(
                        key: DevBarCoreConstants.Keychain.mimoServiceTokenKey,
                        value: cookie
                    ) == errSecSuccess else {
                        throw CredentialsError.keychainSaveFailed
                    }
                } else {
                    KeychainService.shared.delete(key: DevBarCoreConstants.Keychain.mimoServiceTokenKey)
                }

                mimoQuotaViewModel.resetForLogout()
            case .deepseek:
                let account = ProviderAccount(
                    id: ProviderAccount.migratedID(for: .deepseek),
                    provider: .deepseek,
                    isEnabled: true,
                    order: mergedConfigs.count
                )
                let credential = ProviderCredentialEnvelope(
                    accountID: account.id,
                    provider: .deepseek,
                    token: providerPayload.credentials?.token,
                    cookieString: providerPayload.credentials?.cookieString,
                    accountIdentifier: providerPayload.accountId
                )
                if credential.hasCredential,
                   !KeychainService.shared.saveProviderCredential(credential, for: account) {
                    throw CredentialsError.keychainSaveFailed
                }
            }
        }

        await refreshAll(trigger: .importTransfer, silent: true)
    }

    private func importProviderAccounts(_ accountPayloads: [ProviderAccountTransferPayload]) throws {
        var mergedAccounts = providerAccounts
        var importedCredentials: [(account: ProviderAccount, credential: ProviderCredentialEnvelope)] = []

        for accountPayload in accountPayloads {
            let account = accountPayload.account
            if let index = mergedAccounts.firstIndex(where: { $0.id == account.id }) {
                mergedAccounts[index] = account
            } else {
                mergedAccounts.append(account)
            }

            if let credentialsPayload = accountPayload.credentials {
                let credential = ProviderCredentialEnvelope(
                    accountID: account.id,
                    provider: account.provider,
                    token: credentialsPayload.token,
                    cookieString: credentialsPayload.cookieString,
                    accountIdentifier: accountPayload.accountIdentifier,
                    revision: accountPayload.credentialRevision
                )
                if credential.hasCredential,
                   !KeychainService.shared.saveProviderCredential(credential, for: account) {
                    throw CredentialsError.keychainSaveFailed
                }

                if credential.hasCredential {
                    importedCredentials.append((account: account, credential: credential))
                }
            }
        }

        mergedAccounts.sort { $0.order < $1.order }
        for index in mergedAccounts.indices {
            mergedAccounts[index].order = index
        }
        providerAccounts = mergedAccounts
        mirrorImportedLegacyCredentials(importedCredentials, accounts: mergedAccounts)
    }

    private func mirrorImportedLegacyCredentials(
        _ entries: [(account: ProviderAccount, credential: ProviderCredentialEnvelope)],
        accounts: [ProviderAccount]
    ) {
        for provider in QuotaProvider.allCases {
            let selectedEntry = entries
                .filter { $0.account.provider == provider && $0.credential.hasCredential }
                .sorted {
                    order(for: $0.account, in: accounts) < order(for: $1.account, in: accounts)
                }
                .first

            guard let selectedEntry else { continue }
            mirrorLegacyCredential(selectedEntry.credential, account: selectedEntry.account)
        }
    }

    private func order(for account: ProviderAccount, in accounts: [ProviderAccount]) -> Int {
        accounts.first(where: { $0.id == account.id })?.order ?? account.order
    }

    private func mirrorPrimaryLegacyCredentialIfNeeded(
        _ credential: ProviderCredentialEnvelope,
        account: ProviderAccount,
        accounts: [ProviderAccount]? = nil
    ) {
        let accountsForPrimaryCheck = accounts ?? providerAccounts
        let isFirstProviderAccount = accountsForPrimaryCheck
            .filter { $0.provider == account.provider }
            .sorted { $0.order < $1.order }
            .first?.id == account.id

        guard isFirstProviderAccount else { return }

        mirrorLegacyCredential(credential, account: account)
    }

    private func mirrorLegacyCredential(_ credential: ProviderCredentialEnvelope, account: ProviderAccount) {
        switch account.provider {
        case .glm:
            guard let token = credential.token else { return }
            let credentials = AuthCredentials(token: token, cookieString: credential.cookieString ?? "")
            _ = authService.saveCredentials(credentials)
            glmCredentials = credentials
            quotaViewModel.resetForLogout()
        case .openai:
            if let token = credential.token {
                _ = KeychainService.shared.save(key: DevBarCoreConstants.Keychain.openAIAccessTokenKey, value: token)
            }
            settingsStore.saveOpenAIAccountId(credential.accountIdentifier)
            openAIQuotaViewModel.resetForLogout()
        case .mimo:
            if let cookie = credential.cookieString {
                _ = KeychainService.shared.save(key: DevBarCoreConstants.Keychain.mimoServiceTokenKey, value: cookie)
            }
            mimoQuotaViewModel.resetForLogout()
        case .deepseek:
            break
        }
    }

    @discardableResult
    private func upsertCredentialForPrimaryAccount(
        provider: QuotaProvider,
        token: String?,
        cookieString: String?,
        accountIdentifier: String?
    ) -> ProviderAccount {
        let account: ProviderAccount
        if let existing = providerAccounts.first(where: { $0.provider == provider }) {
            account = existing
        } else {
            account = ProviderAccount(
                provider: provider,
                isEnabled: true,
                order: (providerAccounts.map(\.order).max() ?? -1) + 1
            )
            providerAccounts.append(account)
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
        return account
    }

    private func normalizeOrders() {
        for index in accountConfigs.indices {
            accountConfigs[index].order = index
        }
    }

    private func bindChildViewModels() {
        quotaViewModel.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &childObservers)

        openAIQuotaViewModel.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &childObservers)

        mimoQuotaViewModel.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &childObservers)

        deviceRelayManager.objectWillChange
            .sink { [weak self] _ in
                guard let self else { return }
                self.objectWillChange.send()
                DispatchQueue.main.async { [weak self] in
                    self?.syncMacThemeWidgetSnapshot()
                    self?.refreshDevBarLiveMessageReadiness()
                }
            }
            .store(in: &childObservers)

        // 监听 Relay 消息
        deviceRelayManager.messageHandler = { [weak self] message in
            Task { @MainActor [weak self] in
                self?.handleRelayMessage(message)
            }
        }
    }

    // MARK: - Relay Message Handling

    @Published var agentWatcherAlerts: [AgentWatcherAlert] = []

    struct AgentWatcherAlert: Identifiable {
        let id: String
        let source: String
        let projectName: String
        let message: String
        let severity: String
        let receivedAt: Date
    }

    private func handleRelayMessage(_ message: DeviceRelayMessage) {
        switch message.type {
        case .approvalRequest:
            guard DevBarCoreConstants.Features.agentWatcherEnabled else { return }
            handleApprovalRequest(message)
        case .providerQuotaSnapshot:
            handleProviderQuotaSnapshot(message)
        case .providerCredentialUpdate:
            handleProviderCredentialUpdate(message)
        case .providerAccountUpsert:
            handleProviderAccountUpsert(message)
        default:
            break
        }
    }

    private func handleProviderQuotaSnapshot(_ message: DeviceRelayMessage) {
        guard let encoded = message.payload["encodedPayload"],
              let snapshot = try? DeviceRelayProviderSyncPayloadCodec.decode(ProviderQuotaSnapshot.self, from: encoded),
              accountForIncomingQuotaSnapshot(snapshot) != nil else {
            return
        }
        let didApply = WidgetDataManager.shared.applyQuotaSnapshot(
            snapshot,
            localLastUpdated: localQuotaLastUpdated(for: snapshot.provider)
        )
        if didApply {
            WidgetDataManager.shared.saveAndReload(snapshot)
            var snapshots = syncedQuotaSnapshots
            snapshots[snapshot.accountID] = snapshot
            syncedQuotaSnapshots = snapshots
        }
        sendProviderSyncAckIfPossible(
            to: message.fromDeviceId,
            requestId: message.requestId,
            accountID: snapshot.accountID,
            provider: snapshot.provider,
            revision: snapshot.revision,
            status: didApply ? "applied" : "stale"
        )
    }

    @discardableResult
    private func accountForIncomingQuotaSnapshot(_ snapshot: ProviderQuotaSnapshot) -> ProviderAccount? {
        if let account = providerAccounts.first(where: { $0.id == snapshot.accountID }) {
            return account.provider == snapshot.provider ? account : nil
        }

        let account = ProviderAccount(
            id: snapshot.accountID,
            provider: snapshot.provider,
            displayName: snapshot.displayName,
            isEnabled: true,
            order: (providerAccounts.map(\.order).max() ?? -1) + 1,
            syncPolicy: ProviderAccountSyncPolicy(
                quotaSyncEnabled: true,
                credentialSyncEnabled: false
            ),
            createdAt: snapshot.fetchedAt,
            updatedAt: snapshot.fetchedAt
        )
        providerAccounts.append(account)
        return account
    }

    private func handleProviderCredentialUpdate(_ message: DeviceRelayMessage) {
        guard let encoded = message.payload["encodedPayload"],
              let credential = try? DeviceRelayProviderSyncPayloadCodec.decode(
                ProviderCredentialEnvelope.self,
                from: encoded
              ) else {
            return
        }

        guard let account = providerAccounts.first(where: {
            $0.id == credential.accountID && $0.provider == credential.provider
        }) else {
            sendProviderSyncAckIfPossible(
                to: message.fromDeviceId,
                requestId: message.requestId,
                accountID: credential.accountID,
                provider: credential.provider,
                revision: credential.revision,
                status: "missing_account",
                message: "Provider account must be synchronized before its credential"
            )
            return
        }

        guard account.syncPolicy.credentialSyncEnabled else {
            sendProviderSyncAckIfPossible(
                to: message.fromDeviceId,
                requestId: message.requestId,
                accountID: credential.accountID,
                provider: credential.provider,
                revision: credential.revision,
                status: "disabled",
                message: "Credential synchronization is disabled for this account"
            )
            return
        }

        let currentRevision = KeychainService.shared.loadProviderCredential(for: account)?.revision ?? 0
        guard credential.revision >= currentRevision else {
            sendProviderSyncAckIfPossible(
                to: message.fromDeviceId,
                requestId: message.requestId,
                accountID: credential.accountID,
                provider: credential.provider,
                revision: credential.revision,
                status: "stale"
            )
            return
        }

        let saved = KeychainService.shared.saveProviderCredential(credential, for: account)
        if saved {
            mirrorPrimaryLegacyCredentialIfNeeded(credential, account: account)
        }
        sendProviderSyncAckIfPossible(
            to: message.fromDeviceId,
            requestId: message.requestId,
            accountID: credential.accountID,
            provider: credential.provider,
            revision: credential.revision,
            status: saved ? "applied" : "failed"
        )
    }

    private func handleProviderAccountUpsert(_ message: DeviceRelayMessage) {
        guard let encoded = message.payload["encodedPayload"],
              let account = try? DeviceRelayProviderSyncPayloadCodec.decode(ProviderAccount.self, from: encoded) else {
            return
        }
        if let index = providerAccounts.firstIndex(where: { $0.id == account.id }) {
            guard providerAccounts[index].provider == account.provider else { return }
            providerAccounts[index] = account
        } else {
            providerAccounts.append(account)
        }
        sendProviderSyncAckIfPossible(
            to: message.fromDeviceId,
            requestId: message.requestId,
            accountID: account.id,
            provider: account.provider,
            revision: Int(account.updatedAt.timeIntervalSince1970),
            status: "applied"
        )
    }

    private func sendProviderSyncAckIfPossible(
        to targetDeviceID: String?,
        requestId: String?,
        accountID: String,
        provider: QuotaProvider,
        revision: Int,
        status: String,
        message: String? = nil
    ) {
        guard let targetDeviceID,
              let localDeviceID = deviceRelayManager.localDeviceID else {
            return
        }
        Task {
            let ack = DeviceRelayProviderSyncAck(
                accountID: accountID,
                provider: provider,
                status: status,
                revision: revision,
                message: message
            )
            if let message = try? DeviceRelayManager.makeProviderSyncAckMessage(
                localDeviceID: localDeviceID,
                targetDeviceId: targetDeviceID,
                requestId: requestId,
                ack: ack
            ) {
                try? await deviceRelayManager.send(message)
            }
        }
    }

    private func handleApprovalRequest(_ message: DeviceRelayMessage) {
        let payload = message.payload

        let alert = AgentWatcherAlert(
            id: message.requestId ?? UUID().uuidString,
            source: payload["source"] ?? "Unknown",
            projectName: payload["projectName"] ?? "Unknown",
            message: payload["message"] ?? String(localized: "ios_agent_watcher_default_message"),
            severity: payload["severity"] ?? "important",
            receivedAt: Date()
        )

        agentWatcherAlerts.append(alert)

        // 发送本地通知
        let content = UNMutableNotificationContent()
        content.title = String(
            format: String(localized: "ios_agent_watcher_needs_attention_format"),
            alert.source
        )
        content.body = alert.message
        content.sound = .default
        content.categoryIdentifier = "AGENT_WATCHER"

        let request = UNNotificationRequest(
            identifier: "agent-watcher-\(alert.id)",
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("[IOSAppViewModel] Failed to send notification: \(error)")
            }
        }

        // 更新 Live Activity
        updateAgentWatcherLiveActivity()
    }

    private func updateAgentWatcherLiveActivity() {
        let manager = AgentWatcherLiveActivityManager.shared

        if agentWatcherAlerts.isEmpty {
            Task { await manager.endActivity() }
        } else {
            let firstAlert = agentWatcherAlerts.first
            Task {
                await manager.updateActivity(
                    waitingCount: agentWatcherAlerts.count,
                    activeCount: 0,
                    waitingSource: firstAlert?.source,
                    waitingProject: firstAlert?.projectName,
                    waitingMessage: firstAlert?.message,
                    waitingSince: firstAlert?.receivedAt
                )
            }
        }
    }

    func dismissAgentWatcherAlert(_ alertId: String) {
        agentWatcherAlerts.removeAll { $0.id == alertId }
        updateAgentWatcherLiveActivity()
    }

    func enableDevBarLiveMessageIsland() async {
        await enableDevBarLiveMessageIsland(message: devBarLiveMessageDraft)
    }

    func enableDevBarLiveMessageIsland(message rawMessage: String) async {
        let message = rawMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else {
            devBarLiveMessageStatus = .failed(String(localized: "ios_live_message_empty_message_error"))
            return
        }
        devBarLiveMessageStatus = .enabling
        let registration = await DevBarLiveMessageActivityManager.shared.showMessage(
            String(message.prefix(80)),
            source: "iPhone",
            bundleId: IOSPushNotificationCoordinator.bundleIdentifier,
            environment: IOSPushNotificationCoordinator.pushEnvironment,
            startedBy: .local
        )

        let hasActiveActivity = await DevBarLiveMessageActivityManager.shared.hasActiveActivity()
        guard registration != nil || hasActiveActivity else {
            devBarLiveMessageStatus = .failed(String(localized: "ios_live_message_start_failed"))
            return
        }

        if let relayDeviceToken = deviceRelayManager.deviceToken, !relayDeviceToken.isEmpty {
            await IOSPushNotificationCoordinator.shared.syncRegistration(relayDeviceToken: relayDeviceToken)
            await IOSPushNotificationCoordinator.shared.syncLiveActivityPushToStart(relayDeviceToken: relayDeviceToken)
            if let registration {
                await IOSPushNotificationCoordinator.shared.syncLiveActivityRegistration(
                    registration,
                    relayDeviceToken: relayDeviceToken
                )
            }
        }
        devBarLiveMessageStatus = .active
    }

    func disableDevBarLiveMessageIsland() async {
        await DevBarLiveMessageActivityManager.shared.endActivity()
        refreshDevBarLiveMessageReadiness()
    }

    func refreshDevBarLiveMessageReadiness() {
        if case .active = devBarLiveMessageStatus {
            return
        }
        devBarLiveMessageStatus = .ready
    }

    private var localProviderStates: [LocalProviderState] {
        let accountStates = providerAccounts.map { account in
            let credential = KeychainService.shared.loadProviderCredential(for: account)
            return LocalProviderState(
                accountID: account.id,
                provider: account.provider,
                isEnabled: account.isEnabled,
                hasCredential: credential?.hasCredential == true,
                accountIdentifier: credential?.accountIdentifier ?? account.providerAccountIdentifier
            )
        }
        guard !accountStates.isEmpty else {
            return [
                LocalProviderState(
                    provider: .glm,
                    isEnabled: isProviderEnabled(.glm),
                    hasCredential: glmCredentials?.token.isEmpty == false
                ),
                LocalProviderState(
                    provider: .openai,
                    isEnabled: isProviderEnabled(.openai),
                    hasCredential: !openAIAccessToken.isEmpty,
                    accountIdentifier: openAIAccountId
                ),
                LocalProviderState(
                    provider: .mimo,
                    isEnabled: isProviderEnabled(.mimo),
                    hasCredential: !mimoServiceToken.isEmpty
                ),
            ]
        }
        return accountStates + [
            LocalProviderState(
                provider: .glm,
                isEnabled: isProviderEnabled(.glm),
                hasCredential: glmCredentials?.token.isEmpty == false
            ),
            LocalProviderState(
                provider: .openai,
                isEnabled: isProviderEnabled(.openai),
                hasCredential: !openAIAccessToken.isEmpty,
                accountIdentifier: openAIAccountId
            ),
            LocalProviderState(
                provider: .mimo,
                isEnabled: isProviderEnabled(.mimo),
                hasCredential: !mimoServiceToken.isEmpty
            ),
        ]
    }

    private func liveActivityProviderData() -> [WidgetProvider: WidgetSharedData] {
        var result: [WidgetProvider: WidgetSharedData] = [:]
        for provider in WidgetProvider.allCases {
            if let data = WidgetDataManager.shared.loadSharedData(for: provider.rawValue) {
                result[provider] = data
            }
        }
        return result
    }

    private func normalizeGLMAuthorization(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        return trimmed.hasPrefix("Bearer ") ? trimmed : "Bearer \(trimmed)"
    }

    private func validateGLMToken(_ authorization: String) async -> Bool {
        var request = URLRequest(url: URL(string: DevBarCoreConstants.API.quotaLimitURL)!)
        request.setValue(authorization, forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 10

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return false
            }

            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let success = json["success"] as? Bool ?? false
                let code = json["code"] as? Int ?? -1
                return success || code == 0
            }

            return false
        } catch {
            return false
        }
    }
}

extension IOSAppViewModel {
    enum CredentialsError: LocalizedError {
        case emptyGLMAPIKey
        case invalidGLMAPIKey
        case emptyOpenAIToken
        case emptyMimoCookie
        case emptyDeepseekToken
        case emptyHermesAPIKey
        case invalidHermesBaseURL
        case keychainSaveFailed

        var errorDescription: String? {
            switch self {
            case .emptyGLMAPIKey:
                return String(localized: "ios_error_enter_glm_api_key")
            case .invalidGLMAPIKey:
                return String(localized: "ios_error_invalid_glm_api_key")
            case .emptyOpenAIToken:
                return String(localized: "ios_error_enter_openai_token")
            case .emptyMimoCookie:
                return String(localized: "mimo_cookie_required")
            case .emptyDeepseekToken:
                return String(localized: "deepseek_credential_required")
            case .emptyHermesAPIKey:
                return String(localized: "ios_error_enter_hermes_api_key")
            case .invalidHermesBaseURL:
                return String(localized: "ios_error_invalid_hermes_base_url")
            case .keychainSaveFailed:
                return String(localized: "ios_error_keychain_save_failed")
            }
        }
    }
}

extension IOSAppViewModel.RefreshTrigger {
    var summaryText: String {
        switch self {
        case .launch:
            return String(localized: "ios_refresh_initial")
        case .foreground:
            return String(localized: "ios_refresh_auto")
        case .manual:
            return String(localized: "ios_refresh_manual")
        case .importTransfer:
            return String(localized: "ios_refresh_after_import")
        }
    }
}

private extension Double {
    var nonZero: Double? {
        self > 0 ? self : nil
    }
}
