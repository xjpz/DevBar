import Foundation

public struct TransferPayload: Codable, Sendable, Equatable, Identifiable {
    public var id: String {
        "\(schemaVersion)-\(exportedAt.timeIntervalSince1970)-\(expiresAt.timeIntervalSince1970)"
    }

    public let schemaVersion: Int
    public let exportedAt: Date
    public let expiresAt: Date
    public let deviceName: String?
    public let accountConfigs: [AccountConfig]
    public let providers: [ProviderTransferPayload]

    public init(
        schemaVersion: Int = 1,
        exportedAt: Date,
        expiresAt: Date,
        deviceName: String?,
        accountConfigs: [AccountConfig],
        providers: [ProviderTransferPayload]
    ) {
        self.schemaVersion = schemaVersion
        self.exportedAt = exportedAt
        self.expiresAt = expiresAt
        self.deviceName = deviceName
        self.accountConfigs = accountConfigs
        self.providers = providers
    }

    public var importedProviders: [QuotaProvider] {
        providers.map(\.provider)
    }

    public var isExpired: Bool {
        expiresAt <= Date()
    }
}

public struct ProviderTransferPayload: Codable, Sendable, Equatable, Identifiable {
    public var id: QuotaProvider { provider }

    public let provider: QuotaProvider
    public let credentials: ProviderTransferCredentials?
    public let accountId: String?

    public init(
        provider: QuotaProvider,
        credentials: ProviderTransferCredentials?,
        accountId: String? = nil
    ) {
        self.provider = provider
        self.credentials = credentials
        self.accountId = accountId
    }
}

public struct ProviderTransferCredentials: Codable, Sendable, Equatable {
    public let token: String?
    public let cookieString: String?

    public init(token: String? = nil, cookieString: String? = nil) {
        self.token = token
        self.cookieString = cookieString
    }
}
