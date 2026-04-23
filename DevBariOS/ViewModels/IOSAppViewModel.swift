import Combine
import DevBarCore
import Foundation
import SwiftUI

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
        case accounts
        case settings
    }

    @Published var selectedTab: TabSelection = .dashboard
    @Published var accountConfigs: [AccountConfig] {
        didSet {
            settingsStore.saveAccountConfigs(accountConfigs)
        }
    }
    @Published var glmCredentials: AuthCredentials?
    @Published private(set) var lastRefreshTrigger: RefreshTrigger?
    @Published var refreshInterval: TimeInterval {
        didSet {
            UserDefaults.standard.set(refreshInterval, forKey: DevBarCoreConstants.Defaults.refreshIntervalKey)
        }
    }

    let quotaViewModel = QuotaViewModel()
    let openAIQuotaViewModel = OpenAIQuotaViewModel()

    private let authService = AuthService()
    private let settingsStore = UserDefaultsAccountSettingsStore()
    private var childObservers = Set<AnyCancellable>()
    private var hasRefreshedOnLaunch = false
    private var lastRefreshAttemptAt: Date?
    private let automaticRefreshCooldown: TimeInterval = 20

    init() {
        self.accountConfigs = settingsStore.loadAccountConfigs()
        self.glmCredentials = authService.credentials
        self.refreshInterval = UserDefaults.standard.double(forKey: DevBarCoreConstants.Defaults.refreshIntervalKey)
            .nonZero ?? DevBarCoreConstants.Defaults.defaultRefreshInterval
        bindChildViewModels()
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

    func hasAuthenticatedSession(for provider: QuotaProvider) -> Bool {
        switch provider {
        case .glm:
            return glmCredentials?.token.isEmpty == false
        case .openai:
            return !openAIAccessToken.isEmpty
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
    }

    func refreshOnForeground() async {
        guard let lastRefresh = latestRefreshDate else {
            await refreshAll(trigger: .foreground, silent: true)
            return
        }
        guard refreshInterval > 0 else { return }
        if Date().timeIntervalSince(lastRefresh) >= refreshInterval {
            await refreshAll(trigger: .foreground, silent: true)
        }
    }

    func refreshAll(trigger: RefreshTrigger = .manual, silent: Bool = false) async {
        guard shouldRefresh(for: trigger) else { return }
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
    }

    func prepareTransferImport(from rawValue: String) throws -> TransferPayload {
        try TransferPayloadCodec.decode(from: rawValue)
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
            }
        }

        await refreshAll(trigger: .importTransfer, silent: true)
    }

    func openAccountsTab() {
        selectedTab = .accounts
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
    }

    private var latestRefreshDate: Date? {
        [quotaViewModel.lastUpdated, openAIQuotaViewModel.lastUpdated]
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
        ]
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

        var errorDescription: String? {
            switch self {
            case .emptyGLMAPIKey:
                return String(localized: "ios_error_enter_glm_api_key")
            case .invalidGLMAPIKey:
                return String(localized: "ios_error_invalid_glm_api_key")
            case .emptyOpenAIToken:
                return String(localized: "ios_error_enter_openai_token")
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
