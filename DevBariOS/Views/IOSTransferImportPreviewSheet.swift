import DevBarCore
import SwiftUI

struct IOSTransferImportPreviewSheet: View {
    let preview: TransferImportPreview
    let onImport: () async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var isImporting = false

    var body: some View {
        NavigationStack {
            List {
                Section("ios_transfer_source_section") {
                    LabeledContent("ios_transfer_device_label", value: preview.payload.deviceName ?? String(localized: "ios_transfer_unknown_mac"))
                    LabeledContent("ios_transfer_expires_label", value: preview.payload.expiresAt.formatted(date: .omitted, time: .shortened))
                }

                if preview.hasConflicts {
                    Section("ios_transfer_attention_section") {
                        Text("ios_transfer_attention_text")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("ios_transfer_providers_section") {
                    ForEach(preview.providerChanges) { change in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(change.provider.localizedName)
                                Spacer()
                                if change.hasConflict {
                                    Text("ios_transfer_will_replace")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.orange)
                                }
                            }

                            Text(providerDescription(for: change))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("ios_transfer_title")
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
    }

    private func providerDescription(for change: TransferImportProviderChange) -> String {
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
