import Foundation

public struct ProviderPingConfig: Codable, Sendable, Equatable, Identifiable {
    public var id: String { provider.rawValue }
    public var provider: QuotaProvider
    public var isEnabled: Bool
    public var hour: Int
    public var minute: Int
    public var lastAutomaticRunDay: String?
    public var lastAutomaticRunAt: Date?
    public var lastSuccessAt: Date?
    public var lastTestAt: Date?
    public var lastErrorMessage: String?

    public init(
        provider: QuotaProvider,
        isEnabled: Bool,
        hour: Int,
        minute: Int,
        lastAutomaticRunDay: String? = nil,
        lastAutomaticRunAt: Date? = nil,
        lastSuccessAt: Date? = nil,
        lastTestAt: Date? = nil,
        lastErrorMessage: String? = nil
    ) {
        self.provider = provider
        self.isEnabled = isEnabled
        self.hour = hour
        self.minute = minute
        self.lastAutomaticRunDay = lastAutomaticRunDay
        self.lastAutomaticRunAt = lastAutomaticRunAt
        self.lastSuccessAt = lastSuccessAt
        self.lastTestAt = lastTestAt
        self.lastErrorMessage = lastErrorMessage
    }

    public static var defaultGLM: ProviderPingConfig {
        ProviderPingConfig(provider: .glm, isEnabled: false, hour: 10, minute: 0)
    }
}
