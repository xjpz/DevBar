import Combine
import DevBarCore
import Foundation
import SwiftUI
import UIKit

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
    @Published var relayDeviceName: String {
        didSet {
            let normalized = Self.normalizedRelayDeviceName(relayDeviceName)
            UserDefaults.standard.set(normalized, forKey: DevBarCoreConstants.Defaults.relayIPhoneDeviceNameKey)
            if relayDeviceName != normalized {
                relayDeviceName = normalized
            } else {
                Task {
                    await deviceRelayManager.resumeConnectivity(deviceType: .iPhone, deviceName: normalized)
                }
            }
        }
    }
    @Published private(set) var availableHomeScreenShortcutActions: [DeviceRelayHomeScreenShortcutAction]
    @Published private(set) var selectedHomeScreenShortcutActions: [DeviceRelayHomeScreenShortcutAction]

    let quotaViewModel = QuotaViewModel()
    let openAIQuotaViewModel = OpenAIQuotaViewModel()
    let mimoQuotaViewModel = MimoQuotaViewModel()
    let deviceRelayManager = DeviceRelayManager()

    private let authService = AuthService()
    private let settingsStore = UserDefaultsAccountSettingsStore()
    private let liveActivitySettingsStore = LiveActivitySettingsStore()
    private var childObservers = Set<AnyCancellable>()
    private var hasRefreshedOnLaunch = false
    private var lastRefreshAttemptAt: Date?
    private let automaticRefreshCooldown: TimeInterval = 20
    private var usesDefaultHomeScreenShortcutSelection: Bool
    private var hasPairedMacForShortcuts = false

    init() {
        self.accountConfigs = settingsStore.loadAccountConfigs()
        self.glmCredentials = authService.credentials
        self.refreshInterval = UserDefaults.standard.double(forKey: DevBarCoreConstants.Defaults.refreshIntervalKey)
            .nonZero ?? DevBarCoreConstants.Defaults.defaultRefreshInterval
        self.liveActivitySettings = liveActivitySettingsStore.load()
        self.relayDeviceName = Self.loadRelayDeviceName()
        let storedShortcutActions = IOSHomeScreenShortcutPreferences.loadSelectedActions()
        self.usesDefaultHomeScreenShortcutSelection = storedShortcutActions == nil
        self.selectedHomeScreenShortcutActions = storedShortcutActions
            ?? DeviceRelayHomeScreenShortcutPolicy.defaultSelection(hasPairedMac: false)
        self.availableHomeScreenShortcutActions = DeviceRelayHomeScreenShortcutPolicy.availableActions(hasPairedMac: false)
        bindChildViewModels()
        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.deviceRelayManager.setup(deviceType: .iPhone, deviceName: self.relayDeviceName)
            await self.refreshHomeScreenShortcuts()
        }
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
        authService.saveCredentials(credentials)
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

        KeychainService.shared.save(key: DevBarCoreConstants.Keychain.openAIAccessTokenKey, value: trimmedToken)
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

        KeychainService.shared.save(key: DevBarCoreConstants.Keychain.mimoServiceTokenKey, value: credential)
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
        await refreshHomeScreenShortcuts()
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
    }

    func refreshHomeScreenShortcutsForCurrentState() async {
        await refreshHomeScreenShortcuts()
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
                    authService.saveCredentials(credentials)
                    glmCredentials = credentials
                } else {
                    authService.logout()
                    glmCredentials = nil
                }
                quotaViewModel.resetForLogout()

            case .openai:
                if let token = providerPayload.credentials?.token?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !token.isEmpty {
                    KeychainService.shared.save(
                        key: DevBarCoreConstants.Keychain.openAIAccessTokenKey,
                        value: token
                    )
                } else {
                    KeychainService.shared.delete(key: DevBarCoreConstants.Keychain.openAIAccessTokenKey)
                }

                settingsStore.saveOpenAIAccountId(providerPayload.accountId)
                openAIQuotaViewModel.resetForLogout()

            case .mimo:
                if let cookie = providerPayload.credentials?.cookieString?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !cookie.isEmpty {
                    KeychainService.shared.save(
                        key: DevBarCoreConstants.Keychain.mimoServiceTokenKey,
                        value: cookie
                    )
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
                self?.objectWillChange.send()
            }
            .store(in: &childObservers)
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
