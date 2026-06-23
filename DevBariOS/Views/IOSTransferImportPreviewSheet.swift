import DevBarCore
import SwiftUI

struct IOSTransferImportPreviewSheet: View {
    let preview: TransferImportPreview
    let onImport: () async -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.themeTokens) private var theme
    @EnvironmentObject private var themeManager: IOSThemeManager
    @State private var isImporting = false

    var body: some View {
        NavigationStack {
            List {
                Section("ios_transfer_source_section") {
                    LabeledContent("ios_transfer_device_label", value: preview.payload.deviceName ?? String(localized: "ios_transfer_unknown_mac"))
                    LabeledContent("ios_transfer_expires_label", value: themeManager.formatTime(date: preview.payload.expiresAt))
                }
                .listRowBackground(rowBackground)

                if preview.hasConflicts {
                    Section("ios_transfer_attention_section") {
                        Text("ios_transfer_attention_text")
                            .font(.subheadline)
                            .foregroundStyle(theme.textSecondary)
                    }
                    .listRowBackground(rowBackground)
                }

                Section("ios_transfer_providers_section") {
                    ForEach(displayChanges) { change in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(change.provider.localizedName)
                                    .foregroundStyle(theme.textPrimary)
                                Spacer()
                                if change.hasConflict {
                                    Text("ios_transfer_will_replace")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(theme.warning)
                                }
                            }

                            Text(providerDescription(for: change))
                                .font(.caption)
                                .foregroundStyle(theme.textSecondary)

                            if let accountID = change.accountID {
                                Text(accountID)
                                    .font(.caption2)
                                    .foregroundStyle(theme.textTertiary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                        }
                    }
                }
                .listRowBackground(rowBackground)
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Color.clear)
            .navigationTitle("ios_transfer_title")
            .toolbarBackground(theme.backgroundPrimary, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("ios_common_cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task {
                            isImporting = true
                            await onImport()
                            isImporting = false
                        }
                    } label: {
                        if isImporting {
                            ProgressView()
                        } else {
                            Text("ios_transfer_import")
                        }
                    }
                    .disabled(isImporting)
                }
            }
        }
        .tint(theme.brandPrimary)
        .preferredColorScheme(theme.isGeek ? .dark : nil)
        .iosGeekScreenBackground(theme)
    }

    private var displayChanges: [TransferImportDisplayChange] {
        let providerChanges = preview.providerChanges.map(TransferImportDisplayChange.init(providerChange:))
        let accountChanges = preview.accountChanges.map(TransferImportDisplayChange.init(accountChange:))
        return providerChanges + accountChanges
    }

    private var rowBackground: Color {
        theme.isGeek ? theme.surfacePrimary.opacity(0.72) : theme.surfacePrimary
    }

    private func providerDescription(for change: TransferImportDisplayChange) -> String {
        let credentialDescription: String
        switch change.provider {
        case .glm:
            switch change.credentialAction {
            case .keepMissing:
                credentialDescription = String(localized: "ios_transfer_glm_keep_missing")
            case .importNew:
                credentialDescription = String(localized: "ios_transfer_glm_import_new")
            case .replaceExisting:
                credentialDescription = String(localized: "ios_transfer_glm_replace")
            case .clearExisting:
                credentialDescription = String(localized: "ios_transfer_glm_clear")
            }
        case .openai:
            switch change.credentialAction {
            case .keepMissing:
                credentialDescription = String(localized: "ios_transfer_openai_keep_missing")
            case .importNew:
                credentialDescription = String(localized: "ios_transfer_openai_import_new")
            case .replaceExisting:
                credentialDescription = String(localized: "ios_transfer_openai_replace")
            case .clearExisting:
                credentialDescription = String(localized: "ios_transfer_openai_clear")
            }
        case .mimo:
            switch change.credentialAction {
            case .keepMissing:
                credentialDescription = String(localized: "ios_transfer_mimo_keep_missing")
            case .importNew:
                credentialDescription = String(localized: "ios_transfer_mimo_import_new")
            case .replaceExisting:
                credentialDescription = String(localized: "ios_transfer_mimo_replace")
            case .clearExisting:
                credentialDescription = String(localized: "ios_transfer_mimo_clear")
            }
        case .deepseek:
            credentialDescription = "DeepSeek 账号配置"
        }

        let configDescription: String
        switch change.configAction {
        case .unchanged:
            configDescription = String(localized: "ios_transfer_config_unchanged")
        case .enable:
            configDescription = String(localized: "ios_transfer_config_enable")
        case .disable:
            configDescription = String(localized: "ios_transfer_config_disable")
        case let .reorder(from, to):
            configDescription = String(format: String(localized: "ios_transfer_config_reorder"), from + 1, to + 1)
        case .add:
            configDescription = String(localized: "ios_transfer_config_add")
        }

        if change.accountIdentifierChanged {
            return String(format: String(localized: "ios_transfer_description_with_account_id"), credentialDescription, configDescription)
        }

        return String(format: String(localized: "ios_transfer_description"), credentialDescription, configDescription)
    }
}

private struct TransferImportDisplayChange: Identifiable {
    let id: String
    let provider: QuotaProvider
    let credentialAction: TransferImportProviderChange.CredentialAction
    let configAction: TransferImportProviderChange.ConfigAction
    let accountIdentifierChanged: Bool
    let hasConflict: Bool
    let accountID: String?

    init(providerChange: TransferImportProviderChange) {
        self.id = providerChange.provider.rawValue
        self.provider = providerChange.provider
        self.credentialAction = providerChange.credentialAction
        self.configAction = providerChange.configAction
        self.accountIdentifierChanged = providerChange.accountIdentifierChanged
        self.hasConflict = providerChange.hasConflict
        self.accountID = nil
    }

    init(accountChange: TransferImportAccountChange) {
        self.id = accountChange.accountID
        self.provider = accountChange.provider
        self.credentialAction = accountChange.credentialAction
        self.configAction = accountChange.configAction
        self.accountIdentifierChanged = accountChange.accountIdentifierChanged
        self.hasConflict = accountChange.hasConflict
        self.accountID = accountChange.accountID
    }
}
