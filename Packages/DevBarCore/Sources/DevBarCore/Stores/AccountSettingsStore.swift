import Foundation

public protocol AccountSettingsStore {
    func loadAccountConfigs(restoringEnabledProviders: Set<QuotaProvider>) -> [AccountConfig]
    func saveAccountConfigs(_ configs: [AccountConfig])
    func loadProviderAccounts(restoringEnabledProviders: Set<QuotaProvider>) -> [ProviderAccount]
    func saveProviderAccounts(_ accounts: [ProviderAccount])
    func loadOpenAIAccountId() -> String?
    func saveOpenAIAccountId(_ accountId: String?)
}

public extension AccountSettingsStore {
    func loadAccountConfigs() -> [AccountConfig] {
        loadAccountConfigs(restoringEnabledProviders: [])
    }

    func loadProviderAccounts() -> [ProviderAccount] {
        loadProviderAccounts(restoringEnabledProviders: [])
    }
}

public struct UserDefaultsAccountSettingsStore: AccountSettingsStore {
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func loadAccountConfigs(restoringEnabledProviders: Set<QuotaProvider> = []) -> [AccountConfig] {
        guard let data = defaults.data(forKey: DevBarCoreConstants.Defaults.accountConfigsKey),
              let configs = try? JSONDecoder().decode([AccountConfig].self, from: data) else {
            return Self.configsRestoringEnabledProviders(restoringEnabledProviders)
        }
        return Self.normalizedConfigs(configs)
    }

    public func saveAccountConfigs(_ configs: [AccountConfig]) {
        guard let data = try? JSONEncoder().encode(configs) else { return }
        defaults.set(data, forKey: DevBarCoreConstants.Defaults.accountConfigsKey)
    }

    public func loadProviderAccounts(restoringEnabledProviders: Set<QuotaProvider> = []) -> [ProviderAccount] {
        if let data = defaults.data(forKey: DevBarCoreConstants.Defaults.providerAccountsKey),
           let accounts = try? JSONDecoder().decode([ProviderAccount].self, from: data) {
            return Self.normalizedAccounts(accounts)
        }

        let configs = loadAccountConfigs(restoringEnabledProviders: restoringEnabledProviders)
        let migrated = Self.migratedAccounts(from: configs)
        saveProviderAccounts(migrated)
        return migrated
    }

    public func saveProviderAccounts(_ accounts: [ProviderAccount]) {
        let normalized = Self.normalizedAccounts(accounts)
        guard let data = try? JSONEncoder().encode(normalized) else { return }
        defaults.set(data, forKey: DevBarCoreConstants.Defaults.providerAccountsKey)

        let firstByProvider = Dictionary(grouping: normalized, by: \.provider)
            .compactMapValues { accounts in accounts.sorted { $0.order < $1.order }.first }
        let configs = QuotaProvider.allCases.compactMap { firstByProvider[$0]?.legacyConfig }
        saveAccountConfigs(Self.normalizedConfigs(configs))
    }

    public func loadOpenAIAccountId() -> String? {
        defaults.string(forKey: DevBarCoreConstants.OpenAI.accountIdKey)
    }

    public func saveOpenAIAccountId(_ accountId: String?) {
        let trimmed = accountId?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmed, !trimmed.isEmpty {
            defaults.set(trimmed, forKey: DevBarCoreConstants.OpenAI.accountIdKey)
        } else {
            defaults.removeObject(forKey: DevBarCoreConstants.OpenAI.accountIdKey)
        }
    }

    public static let defaultConfigs: [AccountConfig] = [
        AccountConfig(provider: .glm, isEnabled: true, order: 0),
        AccountConfig(provider: .openai, isEnabled: false, order: 1),
        AccountConfig(provider: .mimo, isEnabled: false, order: 2),
        AccountConfig(provider: .deepseek, isEnabled: false, order: 3),
    ]

    public static func configsRestoringEnabledProviders(_ providers: Set<QuotaProvider>) -> [AccountConfig] {
        defaultConfigs.map { config in
            AccountConfig(
                provider: config.provider,
                isEnabled: config.isEnabled || providers.contains(config.provider),
                order: config.order
            )
        }
    }

    public static func normalizedConfigs(_ configs: [AccountConfig]) -> [AccountConfig] {
        var normalized = configs
            .reduce(into: [QuotaProvider: AccountConfig]()) { result, config in
                if result[config.provider] == nil {
                    result[config.provider] = config
                }
            }
            .values
            .sorted { $0.order < $1.order }
        let existing = Set(normalized.map(\.provider))
        for provider in QuotaProvider.allCases where !existing.contains(provider) {
            normalized.append(AccountConfig(provider: provider, isEnabled: false, order: normalized.count))
        }
        for index in normalized.indices {
            normalized[index].order = index
        }
        return normalized
    }

    public static func migratedAccounts(from configs: [AccountConfig]) -> [ProviderAccount] {
        normalizedConfigs(configs).map { config in
            ProviderAccount(
                id: ProviderAccount.migratedID(for: config.provider),
                provider: config.provider,
                displayName: config.provider.localizedName,
                isEnabled: config.isEnabled,
                order: config.order,
                credentialRef: ProviderCredentialRef(
                    keychainAccount: DevBarCoreConstants.Keychain.providerAccountCredentialKey(
                        for: ProviderAccount.migratedID(for: config.provider)
                    )
                ),
                syncPolicy: ProviderAccountSyncPolicy(
                    quotaSyncEnabled: true,
                    credentialSyncEnabled: false
                )
            )
        }
    }

    public static func normalizedAccounts(_ accounts: [ProviderAccount]) -> [ProviderAccount] {
        var seenIDs: Set<String> = []
        var normalized = accounts
            .filter { account in
                guard !seenIDs.contains(account.id) else { return false }
                seenIDs.insert(account.id)
                return true
            }
            .sorted { lhs, rhs in
                if lhs.order == rhs.order {
                    return lhs.displayName < rhs.displayName
                }
                return lhs.order < rhs.order
            }

        let existingProviders = Set(normalized.map(\.provider))
        for provider in QuotaProvider.allCases where !existingProviders.contains(provider) {
            normalized.append(ProviderAccount(
                id: ProviderAccount.migratedID(for: provider),
                provider: provider,
                isEnabled: provider == .glm,
                order: normalized.count
            ))
        }

        for index in normalized.indices {
            normalized[index].order = index
        }
        return normalized
    }
}
