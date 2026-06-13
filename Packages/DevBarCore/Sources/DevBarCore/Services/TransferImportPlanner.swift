import Foundation

public struct LocalProviderState: Sendable, Equatable {
    public let accountID: String?
    public let provider: QuotaProvider
    public let isEnabled: Bool
    public let hasCredential: Bool
    public let accountIdentifier: String?

    public init(
        accountID: String? = nil,
        provider: QuotaProvider,
        isEnabled: Bool,
        hasCredential: Bool,
        accountIdentifier: String? = nil
    ) {
        self.accountID = accountID
        self.provider = provider
        self.isEnabled = isEnabled
        self.hasCredential = hasCredential
        self.accountIdentifier = accountIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public struct TransferImportProviderChange: Sendable, Equatable, Identifiable {
    public enum CredentialAction: Sendable, Equatable {
        case keepMissing
        case importNew
        case replaceExisting
        case clearExisting
    }

    public enum ConfigAction: Sendable, Equatable {
        case unchanged
        case enable
        case disable
        case reorder(from: Int, to: Int)
        case add
    }

    public var id: QuotaProvider { provider }

    public let provider: QuotaProvider
    public let credentialAction: CredentialAction
    public let configAction: ConfigAction
    public let accountIdentifierChanged: Bool

    public init(
        provider: QuotaProvider,
        credentialAction: CredentialAction,
        configAction: ConfigAction,
        accountIdentifierChanged: Bool
    ) {
        self.provider = provider
        self.credentialAction = credentialAction
        self.configAction = configAction
        self.accountIdentifierChanged = accountIdentifierChanged
    }

    public var hasConflict: Bool {
        switch credentialAction {
        case .replaceExisting, .clearExisting:
            return true
        case .keepMissing, .importNew:
            break
        }

        switch configAction {
        case .disable:
            return true
        case .unchanged, .enable, .reorder, .add:
            break
        }

        return accountIdentifierChanged
    }
}

public struct TransferImportAccountChange: Sendable, Equatable, Identifiable {
    public var id: String { accountID }

    public let accountID: String
    public let provider: QuotaProvider
    public let credentialAction: TransferImportProviderChange.CredentialAction
    public let configAction: TransferImportProviderChange.ConfigAction
    public let accountIdentifierChanged: Bool

    public var hasConflict: Bool {
        TransferImportProviderChange(
            provider: provider,
            credentialAction: credentialAction,
            configAction: configAction,
            accountIdentifierChanged: accountIdentifierChanged
        ).hasConflict
    }
}

public struct TransferImportPreview: Sendable, Equatable, Identifiable {
    public var id: String { payload.id }

    public let payload: TransferPayload
    public let providerChanges: [TransferImportProviderChange]
    public let accountChanges: [TransferImportAccountChange]

    public init(
        payload: TransferPayload,
        providerChanges: [TransferImportProviderChange],
        accountChanges: [TransferImportAccountChange] = []
    ) {
        self.payload = payload
        self.providerChanges = providerChanges
        self.accountChanges = accountChanges
    }

    public var hasConflicts: Bool {
        providerChanges.contains(where: \.hasConflict) || accountChanges.contains(where: \.hasConflict)
    }
}

public enum TransferImportPlanner {
    public static func makePreview(
        payload: TransferPayload,
        localStates: [LocalProviderState],
        existingConfigs: [AccountConfig]
    ) -> TransferImportPreview {
        let accountChanges = makeAccountChanges(
            payload: payload,
            localStates: localStates,
            existingAccounts: []
        )
        if !accountChanges.isEmpty {
            return TransferImportPreview(payload: payload, providerChanges: [], accountChanges: accountChanges)
        }

        let statesByProvider = Dictionary(uniqueKeysWithValues: localStates.map { ($0.provider, $0) })
        let configsByProvider = Dictionary(uniqueKeysWithValues: existingConfigs.map { ($0.provider, $0) })

        let providerChanges = payload.providers.map { providerPayload in
            let localState = statesByProvider[providerPayload.provider]
            let localConfig = configsByProvider[providerPayload.provider]
            let importedConfig = payload.accountConfigs.first(where: { $0.provider == providerPayload.provider })

            return TransferImportProviderChange(
                provider: providerPayload.provider,
                credentialAction: credentialAction(for: providerPayload, localState: localState),
                configAction: configAction(importedConfig: importedConfig, localConfig: localConfig),
                accountIdentifierChanged: accountIdentifierChanged(for: providerPayload, localState: localState)
            )
        }

        return TransferImportPreview(payload: payload, providerChanges: providerChanges)
    }

    public static func makePreview(
        payload: TransferPayload,
        localStates: [LocalProviderState],
        existingAccounts: [ProviderAccount]
    ) -> TransferImportPreview {
        TransferImportPreview(
            payload: payload,
            providerChanges: [],
            accountChanges: makeAccountChanges(
                payload: payload,
                localStates: localStates,
                existingAccounts: existingAccounts
            )
        )
    }

    private static func makeAccountChanges(
        payload: TransferPayload,
        localStates: [LocalProviderState],
        existingAccounts: [ProviderAccount]
    ) -> [TransferImportAccountChange] {
        guard payload.schemaVersion >= 2, !payload.accounts.isEmpty else { return [] }

        let statesByAccountID = Dictionary(uniqueKeysWithValues: localStates.compactMap { state in
            state.accountID.map { ($0, state) }
        })
        let accountsByID = Dictionary(uniqueKeysWithValues: existingAccounts.map { ($0.id, $0) })

        return payload.accounts.map { accountPayload in
            let localState = statesByAccountID[accountPayload.id]
            let localAccount = accountsByID[accountPayload.id]
            let importedConfig = AccountConfig(
                provider: accountPayload.provider,
                isEnabled: accountPayload.isEnabled,
                order: accountPayload.order
            )
            let localConfig = localAccount.map {
                AccountConfig(provider: $0.provider, isEnabled: $0.isEnabled, order: $0.order)
            }
            return TransferImportAccountChange(
                accountID: accountPayload.id,
                provider: accountPayload.provider,
                credentialAction: credentialAction(for: accountPayload.providerPayload, localState: localState),
                configAction: configAction(importedConfig: importedConfig, localConfig: localConfig),
                accountIdentifierChanged: accountIdentifierChanged(for: accountPayload.providerPayload, localState: localState)
            )
        }
    }

    private static func credentialAction(
        for payload: ProviderTransferPayload,
        localState: LocalProviderState?
    ) -> TransferImportProviderChange.CredentialAction {
        let importedHasCredential = hasImportedCredential(payload)
        let localHasCredential = localState?.hasCredential == true

        switch (localHasCredential, importedHasCredential) {
        case (true, true):
            return .replaceExisting
        case (false, true):
            return .importNew
        case (true, false):
            return .clearExisting
        case (false, false):
            return .keepMissing
        }
    }

    private static func configAction(
        importedConfig: AccountConfig?,
        localConfig: AccountConfig?
    ) -> TransferImportProviderChange.ConfigAction {
        guard let importedConfig else { return .unchanged }
        guard let localConfig else { return .add }

        if localConfig.isEnabled != importedConfig.isEnabled {
            return importedConfig.isEnabled ? .enable : .disable
        }

        if localConfig.order != importedConfig.order {
            return .reorder(from: localConfig.order, to: importedConfig.order)
        }

        return .unchanged
    }

    private static func accountIdentifierChanged(
        for payload: ProviderTransferPayload,
        localState: LocalProviderState?
    ) -> Bool {
        let importedAccount = payload.accountId?.trimmingCharacters(in: .whitespacesAndNewlines)
        let localAccount = localState?.accountIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines)
        return importedAccount != localAccount && (importedAccount != nil || localAccount != nil)
    }

    private static func hasImportedCredential(_ payload: ProviderTransferPayload) -> Bool {
        let token = payload.credentials?.token?.trimmingCharacters(in: .whitespacesAndNewlines)
        let cookieString = payload.credentials?.cookieString?.trimmingCharacters(in: .whitespacesAndNewlines)
        return !(token?.isEmpty ?? true) || !(cookieString?.isEmpty ?? true)
    }
}
