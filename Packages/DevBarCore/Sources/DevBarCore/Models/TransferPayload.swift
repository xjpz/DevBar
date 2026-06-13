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
    public let accounts: [ProviderAccountTransferPayload]

    public init(
        schemaVersion: Int = 1,
        exportedAt: Date,
        expiresAt: Date,
        deviceName: String?,
        accountConfigs: [AccountConfig],
        providers: [ProviderTransferPayload],
        accounts: [ProviderAccountTransferPayload] = []
    ) {
        self.schemaVersion = schemaVersion
        self.exportedAt = exportedAt
        self.expiresAt = expiresAt
        self.deviceName = deviceName
        self.accountConfigs = accountConfigs
        self.providers = providers
        if accounts.isEmpty {
            self.accounts = providers.enumerated().map { index, payload in
                ProviderAccountTransferPayload(
                    id: ProviderAccount.migratedID(for: payload.provider),
                    provider: payload.provider,
                    displayName: payload.provider.localizedName,
                    isEnabled: accountConfigs.first(where: { $0.provider == payload.provider })?.isEnabled ?? true,
                    order: accountConfigs.first(where: { $0.provider == payload.provider })?.order ?? index,
                    credentials: payload.credentials,
                    accountIdentifier: payload.accountId,
                    credentialRevision: 1
                )
            }
        } else {
            self.accounts = accounts
        }
    }

    public var importedProviders: [QuotaProvider] {
        if !accounts.isEmpty {
            return accounts.map(\.provider)
        }
        return providers.map(\.provider)
    }

    public var isExpired: Bool {
        expiresAt <= Date()
    }
}

public struct ProviderAccountTransferPayload: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let provider: QuotaProvider
    public let displayName: String
    public let isEnabled: Bool
    public let order: Int
    public let credentials: ProviderTransferCredentials?
    public let accountIdentifier: String?
    public let credentialRevision: Int

    public init(
        id: String,
        provider: QuotaProvider,
        displayName: String,
        isEnabled: Bool,
        order: Int,
        credentials: ProviderTransferCredentials?,
        accountIdentifier: String? = nil,
        credentialRevision: Int = 1
    ) {
        self.id = id
        self.provider = provider
        self.displayName = displayName
        self.isEnabled = isEnabled
        self.order = order
        self.credentials = credentials
        self.accountIdentifier = accountIdentifier
        self.credentialRevision = credentialRevision
    }

    public var providerPayload: ProviderTransferPayload {
        ProviderTransferPayload(provider: provider, credentials: credentials, accountId: accountIdentifier)
    }

    public var account: ProviderAccount {
        ProviderAccount(
            id: id,
            provider: provider,
            displayName: displayName,
            isEnabled: isEnabled,
            order: order,
            providerAccountIdentifier: accountIdentifier
        )
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
