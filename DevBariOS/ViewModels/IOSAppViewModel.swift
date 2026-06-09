import Combine
import DevBarCore
import Foundation
import Security
import SwiftUI
import UIKit
import UserNotifications

enum IOSScannedCodeResolution {
    case macPaired
    case providerTransfer(preview: TransferImportPreview, relayURL: URL?)
}

@MainActor
final class IOSAppViewModel: ObservableObject {
    enum RefreshTrigger {
        case launch
        case foreground
        case manual
        case importTransfer
    }

    enum TabSelection: Hashable {
        case dashboard
        case webkit
        case tools
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
                "可本机上岛"
            case .ready:
                "可上岛"
            case .enabling:
                "正在上岛"
            case .active:
                "已上岛"
            case .failed:
                "上岛失败"
            }
        }

        var detail: String {
            switch self {
            case .notReady:
                "本机输入文案可直接上岛；完成 Relay 绑定后，服务端 API 也可远程推送上岛。"
            case .ready:
                "输入一句文案即可本机上岛；服务端 API 也可远程推送上岛。"
            case .enabling:
                "正在把文案显示到灵动岛。"
            case .active:
                "文案已显示在灵动岛；后续 API 推送会显示 API 的新文案。"
            case .failed(let message):
                message
            }
        }
    }

    @Published var selectedTab: TabSelection = .dashboard
    @Published var accountConfigs: [AccountConfig] {
        didSet {
            settingsStore.saveAccountConfigs(accountConfigs)
            Task { await syncLiveActivity() }
        }
    }
    @Published var glmCredentials: AuthCredentials?
    @Published private(set) var lastRefreshTrigger: RefreshTrigger?
    @Published var refreshInterval: TimeInterval {
        didSet {
            UserDefaults.standard.set(refreshInterval, forKey: DevBarCoreConstants.Defaults.refreshIntervalKey)
        }
    }
    @Published var liveActivitySettings: LiveActivitySettings {
        didSet {
            liveActivitySettingsStore.save(liveActivitySettings)
            Task { await syncLiveActivity() }
        }
    }
    @Published var pushNotificationPreferences: PushNotificationPreferences {
        didSet {
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
    @Published var devBarLiveMessageDraft: String = ""

    let quotaViewModel = QuotaViewModel()
    let openAIQuotaViewModel = OpenAIQuotaViewModel()
    let mimoQuotaViewModel = MimoQuotaViewModel()
    let deviceRelayManager = DeviceRelayManager()

    private let authService = AuthService()
    private let settingsStore = UserDefaultsAccountSettingsStore()
    private let liveActivitySettingsStore = LiveActivitySettingsStore()
    private let macThemeWidgetAvatarStore = MacThemeWidgetAvatarStore()
    private var childObservers = Set<AnyCancellable>()
    private var hasRefreshedOnLaunch = false
    private var lastRefreshAttemptAt: Date?
    private let automaticRefreshCooldown: TimeInterval = 20
    private var usesDefaultHomeScreenShortcutSelection: Bool
    private var hasPairedMacForShortcuts = false

    init() {
        self.accountConfigs = settingsStore.loadAccountConfigs(
            restoringEnabledProviders: Self.providersWithStoredCredentials()
        )
        self.glmCredentials = authService.credentials
        self.refreshInterval = UserDefaults.standard.double(forKey: DevBarCoreConstants.Defaults.refreshIntervalKey)
            .nonZero ?? DevBarCoreConstants.Defaults.defaultRefreshInterval
        self.liveActivitySettings = liveActivitySettingsStore.load()
        var pushPreferences = IOSPushNotificationCoordinator.shared.loadPreferences()
        if !DevBarCoreConstants.Features.agentWatcherEnabled {
            pushPreferences.agentWatcherEnabled = false
        }
        self.pushNotificationPreferences = pushPreferences
        let relayDeviceName = Self.loadRelayDeviceName()
        self.relayDeviceName = relayDeviceName
        self.macThemeWidgetUserName = Self.loadMacThemeWidgetUserName()
        self.macThemeWidgetAvatarFileName = Self.loadMacThemeWidgetAvatarFileName()
        let storedShortcutActions = IOSHomeScreenShortcutPreferences.loadSelectedActions()
        self.usesDefaultHomeScreenShortcutSelection = storedShortcutActions == nil
        self.selectedHomeScreenShortcutActions = storedShortcutActions
            ?? DeviceRelayHomeScreenShortcutPolicy.defaultSelection(hasPairedMac: false)
        self.availableHomeScreenShortcutActions = DeviceRelayHomeScreenShortcutPolicy.availableActions(hasPairedMac: false)
        bindChildViewModels()
        NotificationCenter.default.publisher(for: .iosAPNsTokenChanged)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    await IOSPushNotificationCoordinator.shared.syncRegistration(
                        relayDeviceToken: self.deviceRelayManager.deviceToken,
                        force: true
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
        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.deviceRelayManager.setup(deviceType: .iPhone, deviceName: self.relayDeviceName)
            await IOSPushNotificationCoordinator.shared.syncRegistration(
                relayDeviceToken: self.deviceRelayManager.deviceToken,
                force: true
            )
            await IOSPushNotificationCoordinator.shared.syncLiveActivityPushToStart(
                relayDeviceToken: self.deviceRelayManager.deviceToken,
                force: true
            )
            self.refreshDevBarLiveMessageReadiness()
            await self.refreshHomeScreenShortcuts()
            self.syncMacThemeWidgetSnapshot()
        }
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
        KeychainService.shared.load(key: DevBarCoreConstants.Keychain.mimoServiceTokenKey) ?? ""
    }

    func hasAuthenticatedSession(for provider: QuotaProvider) -> Bool {
        switch provider {
        case .glm:
            return glmCredentials?.token.isEmpty == false
        case .openai:
            return !openAIAccessToken.isEmpty
        case .mimo:
            return !mimoServiceToken.isEmpty
        }
    }

    func isProviderEnabled(_ provider: QuotaProvider) -> Bool {
        accountConfigs.first(where: { $0.provider == provider })?.isEnabled ?? false
    }

    func updateProvider(_ provider: QuotaProvider, enabled: Bool) {
        guard let index = accountConfigs.firstIndex(where: { $0.provider == provider }) else { return }
        accountConfigs[index].isEnabled = enabled
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
        guard !hasRefreshedOnLaunch else { return }
        hasRefreshedOnLaunch = true
        await refreshAll(trigger: .launch, silent: true)
        await refreshHomeScreenShortcuts()
    }

    func refreshOnForeground() async {
        await deviceRelayManager.resumeConnectivity(deviceType: .iPhone, deviceName: relayDeviceName)
        await IOSPushNotificationCoordinator.shared.syncRegistration(relayDeviceToken: deviceRelayManager.deviceToken, force: true)
        await IOSPushNotificationCoordinator.shared.syncLiveActivityPushToStart(relayDeviceToken: deviceRelayManager.deviceToken, force: true)
        refreshDevBarLiveMessageReadiness()
        await refreshHomeScreenShortcuts()

        guard let lastRefresh = latestRefreshDate else {
            await refreshAll(trigger: .foreground, silent: true)
            return
        }
        guard refreshInterval > 0 else { return }
        if Date().timeIntervalSince(lastRefresh) >= refreshInterval {
            await refreshAll(trigger: .foreground, silent: true)
        } else {
            await syncLiveActivity()
        }
    }

    func refreshAll(trigger: RefreshTrigger = .manual, silent: Bool = false) async {
        guard shouldRefresh(for: trigger) else {
            await syncLiveActivity()
            return
        }
        lastRefreshAttemptAt = Date()
        lastRefreshTrigger = trigger

        if isProviderEnabled(.glm), let glmCredentials {
            if quotaViewModel.subscription == nil && quotaViewModel.quotaData == nil {
                await quotaViewModel.loadInitialData(credentials: glmCredentials)
            } else {
                await quotaViewModel.fetchQuota(credentials: glmCredentials, silent: silent)
            }
        }

        if isProviderEnabled(.openai), !openAIAccessToken.isEmpty {
            await openAIQuotaViewModel.fetchUsage(
                storedAccessToken: openAIAccessToken,
                storedAccountId: settingsStore.loadOpenAIAccountId(),
                silent: silent
            )
        }

        if isProviderEnabled(.mimo), !mimoServiceToken.isEmpty {
            await mimoQuotaViewModel.fetchUsage(
                storedServiceToken: mimoServiceToken,
                silent: silent
            )
        }

        await syncLiveActivity()
    }

    func syncLiveActivity() async {
        await IOSLiveActivityManager.shared.sync(
            settings: liveActivitySettings,
            configs: accountConfigs,
            dataByProvider: liveActivityProviderData()
        )
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
        if !isProviderEnabled(.mimo) {
            updateProvider(.mimo, enabled: true)
        }
    }

    func clearMimoCredentials() {
        KeychainService.shared.delete(key: DevBarCoreConstants.Keychain.mimoServiceTokenKey)
        mimoQuotaViewModel.resetForLogout()
        Task { await syncLiveActivity() }
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
        guard let token = store.loadDeviceToken(), !token.isEmpty else {
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
            return MacStatusWidgetSnapshot(
                deviceID: mac.deviceId,
                deviceName: deviceRelayManager.displayName(for: mac),
                isOnline: connectionStatus != .offline,
                lastSeenAt: mac.lastSeenAt.map { Date(timeIntervalSince1970: TimeInterval($0) / 1000) },
                screenState: screenLocked.map { $0 ? .locked : .unlocked } ?? .unknown,
                displayState: .unknown,
                keepAwakeState: .unknown,
                connectionMode: macThemeConnectionMode(for: connectionStatus),
                batteryPercent: nil,
                cpuPercent: nil,
                memoryPercent: nil,
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

    func makeTransferImportPreview(for payload: TransferPayload) -> TransferImportPreview {
        TransferImportPlanner.makePreview(
            payload: payload,
            localStates: localProviderStates,
            existingConfigs: accountConfigs
        )
    }

    func importTransferPayload(_ payload: TransferPayload) async throws {
        guard !payload.isExpired else {
            throw TransferPayloadError.expired
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
            }
        }

        await refreshAll(trigger: .importTransfer, silent: true)
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
        default:
            break
        }
    }

    private func handleApprovalRequest(_ message: DeviceRelayMessage) {
        let payload = message.payload

        let alert = AgentWatcherAlert(
            id: message.requestId ?? UUID().uuidString,
            source: payload["source"] ?? "Unknown",
            projectName: payload["projectName"] ?? "Unknown",
            message: payload["message"] ?? "任务等待处理",
            severity: payload["severity"] ?? "important",
            receivedAt: Date()
        )

        agentWatcherAlerts.append(alert)

        // 发送本地通知
        let content = UNMutableNotificationContent()
        content.title = "\(alert.source) 需要处理"
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
            devBarLiveMessageStatus = .failed("请输入要显示在灵动岛的一句文案。")
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
            devBarLiveMessageStatus = .failed("Live Activity 启动失败，请稍后重试。")
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

    private var latestRefreshDate: Date? {
        [quotaViewModel.lastUpdated, openAIQuotaViewModel.lastUpdated, mimoQuotaViewModel.lastUpdated]
            .compactMap { $0 }
            .max()
    }

    private var localProviderStates: [LocalProviderState] {
        [
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

    private func shouldRefresh(for trigger: RefreshTrigger) -> Bool {
        switch trigger {
        case .manual, .importTransfer:
            return true
        case .launch, .foreground:
            guard let lastRefreshAttemptAt else { return true }
            return Date().timeIntervalSince(lastRefreshAttemptAt) >= automaticRefreshCooldown
        }
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
            case .keychainSaveFailed:
                return "无法安全保存凭据，请重试"
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
