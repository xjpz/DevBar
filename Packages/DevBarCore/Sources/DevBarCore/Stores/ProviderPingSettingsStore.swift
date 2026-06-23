import Foundation

public protocol ProviderPingSettingsStore {
    func loadProviderPingConfigs() -> [ProviderPingConfig]
    func saveProviderPingConfigs(_ configs: [ProviderPingConfig])
}

public struct UserDefaultsProviderPingSettingsStore: ProviderPingSettingsStore {
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func loadProviderPingConfigs() -> [ProviderPingConfig] {
        guard let data = defaults.data(forKey: DevBarCoreConstants.Defaults.providerPingConfigsKey),
              let configs = try? JSONDecoder().decode([ProviderPingConfig].self, from: data) else {
            return Self.defaultConfigs
        }
        return Self.normalizedConfigs(configs)
    }

    public func saveProviderPingConfigs(_ configs: [ProviderPingConfig]) {
        guard let data = try? JSONEncoder().encode(Self.normalizedConfigs(configs)) else { return }
        defaults.set(data, forKey: DevBarCoreConstants.Defaults.providerPingConfigsKey)
    }

    public static let defaultConfigs: [ProviderPingConfig] = [
        .defaultGLM,
    ]

    public static func normalizedConfigs(_ configs: [ProviderPingConfig]) -> [ProviderPingConfig] {
        var normalized = configs.map { config in
            var copy = config
            if !(0...23).contains(copy.hour) {
                copy.hour = ProviderPingConfig.defaultGLM.hour
            }
            if !(0...59).contains(copy.minute) {
                copy.minute = ProviderPingConfig.defaultGLM.minute
            }
            return copy
        }

        if !normalized.contains(where: { $0.provider == .glm }) {
            normalized.append(.defaultGLM)
        }

        normalized.sort { lhs, rhs in
            guard let lhsIndex = QuotaProvider.allCases.firstIndex(of: lhs.provider),
                  let rhsIndex = QuotaProvider.allCases.firstIndex(of: rhs.provider) else {
                return lhs.provider.rawValue < rhs.provider.rawValue
            }
            return lhsIndex < rhsIndex
        }
        return normalized
    }
}
