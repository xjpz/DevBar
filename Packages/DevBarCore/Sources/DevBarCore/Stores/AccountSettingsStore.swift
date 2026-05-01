import Foundation

public protocol AccountSettingsStore {
    func loadAccountConfigs() -> [AccountConfig]
    func saveAccountConfigs(_ configs: [AccountConfig])
    func loadOpenAIAccountId() -> String?
    func saveOpenAIAccountId(_ accountId: String?)
}

public struct UserDefaultsAccountSettingsStore: AccountSettingsStore {
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func loadAccountConfigs() -> [AccountConfig] {
        guard let data = defaults.data(forKey: DevBarCoreConstants.Defaults.accountConfigsKey),
              let configs = try? JSONDecoder().decode([AccountConfig].self, from: data) else {
            return Self.defaultConfigs
        }
        return Self.normalizedConfigs(configs)
    }

    public func saveAccountConfigs(_ configs: [AccountConfig]) {
        guard let data = try? JSONEncoder().encode(configs) else { return }
        defaults.set(data, forKey: DevBarCoreConstants.Defaults.accountConfigsKey)
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
    ]

    public static func normalizedConfigs(_ configs: [AccountConfig]) -> [AccountConfig] {
        var normalized = configs.sorted { $0.order < $1.order }
        let existing = Set(normalized.map(\.provider))
        for provider in QuotaProvider.allCases where !existing.contains(provider) {
            normalized.append(AccountConfig(provider: provider, isEnabled: false, order: normalized.count))
        }
        for index in normalized.indices {
            normalized[index].order = index
        }
        return normalized
    }
}
