import Foundation

public struct LocalProviderState: Sendable, Equatable {
    public let provider: QuotaProvider
    public let isEnabled: Bool
    public let hasCredential: Bool
    public let accountIdentifier: String?

    public init(
        provider: QuotaProvider,
        isEnabled: Bool,
        hasCredential: Bool,
        accountIdentifier: String? = nil
    ) {
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

public struct TransferImportPreview: Sendable, Equatable, Identifiable {
    public var id: String { payload.id }

    public let payload: TransferPayload
    public let providerChanges: [TransferImportProviderChange]

    public init(payload: TransferPayload, providerChanges: [TransferImportProviderChange]) {
        self.payload = payload
        self.providerChanges = providerChanges
    }

    public var hasConflicts: Bool {
        providerChanges.contains(where: \.hasConflict)
    }
}

public enum TransferImportPlanner {
    public static func makePreview(
        payload: TransferPayload,
        localStates: [LocalProviderState],
        existingConfigs: [AccountConfig]
    ) -> TransferImportPreview {
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
