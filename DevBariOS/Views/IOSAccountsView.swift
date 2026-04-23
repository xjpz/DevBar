import DevBarCore
import SwiftUI
import UniformTypeIdentifiers

struct IOSAccountsView: View {
    @EnvironmentObject private var appViewModel: IOSAppViewModel
    @State private var glmTokenInput = ""
    @State private var openAITokenInput = ""
    @State private var openAIAccountIdInput = ""
    @State private var glmError: String?
    @State private var openAIError: String?
    @State private var isSavingGLM = false
    @State private var isSavingOpenAI = false
    @State private var isShowingScanner = false
    @State private var pendingImportPreview: TransferImportPreview?
    @State private var transferImportError: String?
    @State private var pageMode: AccountsPageMode = .normal
    @State private var listEditMode: EditMode = .inactive
    @State private var draggedProvider: QuotaProvider?

    private var sortedConfigs: [AccountConfig] {
        appViewModel.accountConfigs.sorted { $0.order < $1.order }
    }

    var body: some View {
        List {
            Section {
                migrationCard
                    .listRowInsets(EdgeInsets(top: 16, leading: 16, bottom: 0, trailing: 16))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }

            Section {
                providerListHeader
                    .listRowInsets(EdgeInsets(top: 24, leading: 16, bottom: 0, trailing: 16))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)

                ForEach(sortedConfigs) { config in
                    providerRow(for: config)
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color(.systemGroupedBackground))
                }
                .onMove(perform: moveProviders)
            }
        }
        .environment(\.editMode, $listEditMode)
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color(.systemGroupedBackground))
        .navigationTitle("ios_accounts_title")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(topBarActionTitle) {
                    handleTopBarAction()
                }
                .disabled(isSavingGLM || isSavingOpenAI)
            }
        }
        .accessibilityIdentifier("ios.accounts.screen")
        .onAppear(perform: loadStoredValues)
        .sheet(isPresented: $isShowingScanner) {
            NavigationStack {
                IOSQRScannerView { code in
                    isShowingScanner = false
                    handleScannedCode(code)
                }
                .ignoresSafeArea()
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("ios_common_cancel") {
                            isShowingScanner = false
                        }
                    }
                }
            }
        }
        .sheet(item: $pendingImportPreview) { preview in
            IOSTransferImportPreviewSheet(preview: preview) {
                await importPayload(preview.payload)
            }
        }
        .alert("ios_accounts_import_failed", isPresented: Binding(
            get: { transferImportError != nil },
            set: { if !$0 { transferImportError = nil } }
        )) {
            Button("ios_common_ok", role: .cancel) {}
        } message: {
            Text(transferImportError ?? "")
        }
    }

    private var isReordering: Bool {
        pageMode == .reordering
    }

    private var topBarActionTitle: LocalizedStringKey {
        switch pageMode {
        case .normal:
            return "accounts_order_label"
        case .editing:
            return "accounts_done_editing"
        case .reordering:
            return "accounts_done_editing"
        }
    }

    private var migrationCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "qrcode.viewfinder")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.tint)
                    .frame(width: 36, height: 36)
                    .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text("ios_accounts_migration_section")
                        .font(.headline)
                    Text("ios_accounts_migration_hint")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)
            }

            Button {
                isShowingScanner = true
            } label: {
                HStack {
                    Spacer(minLength: 0)
                    Image(systemName: "camera.viewfinder")
                    Text("ios_accounts_scan_from_mac")
                    Spacer(minLength: 0)
                }
            }
            .buttonStyle(.borderedProminent)
            .frame(maxWidth: .infinity, alignment: .center)
            .accessibilityIdentifier("ios.accounts.scan")
        }
        .padding(16)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var providerListHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("ios_accounts_provider_order_section")
                    .font(.headline)
                Spacer()
                Text(String(format: String(localized: "accounts_count_format"), sortedConfigs.count))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            Text("accounts_section_hint")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func providerRow(for config: AccountConfig) -> some View {
        editableProviderRow(for: config)
    }

    private func editableProviderRow(for config: AccountConfig) -> some View {
        let isExpanded = pageMode == .editing(config.provider)
        let isSaving = savingState(for: config.provider)
        let errorMessage = errorState(for: config.provider)

        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                providerArtwork(for: config.provider)

                Text(config.provider.localizedName)
                    .font(.system(size: 16, weight: .semibold))

                Spacer(minLength: 8)

                if isSaving {
                    ProgressView()
                        .controlSize(.small)
                } else if !isReordering {
                    Button {
                        handleEditAction(for: config.provider)
                    } label: {
                        Text(isExpanded ? String(localized: "accounts_done_editing") : String(localized: "accounts_edit_credentials"))
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(Color.primary.opacity(0.06), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }

                Toggle("", isOn: Binding(
                    get: { config.isEnabled },
                    set: { appViewModel.updateProvider(config.provider, enabled: $0) }
                ))
                .labelsHidden()
            }
            .contentShape(Rectangle())
            .onTapGesture {
                toggleExpansion(for: config.provider)
            }

            if isExpanded {
                Divider()
                    .overlay(Color.primary.opacity(0.06))

                credentialEditor(for: config.provider)

                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
        }
        .padding(16)
        .background(rowBackground(for: config))
        .overlay(rowBorder(for: config))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .opacity(draggedProvider == config.provider ? 0.84 : 1)
        .onDrag {
            guard pageMode == .normal else {
                return NSItemProvider()
            }
            draggedProvider = config.provider
            return NSItemProvider(object: config.provider.rawValue as NSString)
        }
        .onDrop(
            of: [UTType.plainText],
            delegate: ProviderDropDelegate(
                target: config.provider,
                draggedProvider: $draggedProvider,
                currentMode: pageMode,
                move: { source, target in
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                        appViewModel.moveProvider(source, to: target)
                    }
                }
            )
        )
        .animation(.spring(response: 0.28, dampingFraction: 0.86), value: sortedConfigs.map(\.id))
    }

    @ViewBuilder
    private func credentialEditor(for provider: QuotaProvider) -> some View {
        switch provider {
        case .glm:
            VStack(alignment: .leading, spacing: 12) {
                inputField(title: "GLM API Key") {
                    SecureField("ios_accounts_glm_api_key", text: $glmTokenInput)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.system(.body, design: .monospaced))
                }

                Text("ios_accounts_glm_footer")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 10) {
                    Button(role: .destructive) {
                        appViewModel.clearGLMCredentials()
                        glmTokenInput = ""
                        glmError = nil
                    } label: {
                        Text("ios_accounts_remove_glm")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    Button {
                        saveGLM()
                    } label: {
                        Text("accounts_done_editing")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isSavingGLM)
                }
            }

        case .openai:
            VStack(alignment: .leading, spacing: 12) {
                inputField(title: "Access Token") {
                    SecureField("ios_accounts_openai_access_token", text: $openAITokenInput)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.system(.body, design: .monospaced))
                }

                inputField(title: String(localized: "ios_accounts_openai_account_id_optional")) {
                    TextField("ios_accounts_openai_account_id_optional", text: $openAIAccountIdInput)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.system(.body, design: .monospaced))
                }

                HStack(spacing: 10) {
                    Button(role: .destructive) {
                        appViewModel.clearOpenAICredentials()
                        openAITokenInput = ""
                        openAIAccountIdInput = ""
                        openAIError = nil
                    } label: {
                        Text("ios_accounts_remove_openai")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    Button {
                        saveOpenAI()
                    } label: {
                        Text("accounts_done_editing")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isSavingOpenAI)
                }
            }
        }
    }

    private func inputField<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)

            content()
                .padding(.horizontal, 12)
                .padding(.vertical, 11)
                .background(Color(.tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private func providerArtwork(for provider: QuotaProvider) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(provider.accentColor.opacity(0.14))

            Image(provider.assetName)
                .resizable()
                .scaledToFit()
                .padding(8)
        }
        .frame(width: 40, height: 40)
    }

    private func savingState(for provider: QuotaProvider) -> Bool {
        switch provider {
        case .glm:
            return isSavingGLM
        case .openai:
            return isSavingOpenAI
        }
    }

    private func errorState(for provider: QuotaProvider) -> String? {
        switch provider {
        case .glm:
            return glmError
        case .openai:
            return openAIError
        }
    }

    private func rowBackground(for config: AccountConfig) -> some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(Color(.secondarySystemBackground))
            .overlay(
                LinearGradient(
                    colors: [
                        config.provider.accentColor.opacity(config.isEnabled ? 0.12 : 0.04),
                        Color.clear
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
    }

    private func rowBorder(for config: AccountConfig) -> some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .strokeBorder(
                config.provider.accentColor.opacity(config.isEnabled ? 0.18 : 0.08),
                lineWidth: 1
            )
    }

    private func toggleExpansion(for provider: QuotaProvider) {
        guard !isReordering else { return }
        if pageMode == .editing(provider) {
            _ = finishEditingIfNeeded(for: provider)
        } else {
            glmError = nil
            openAIError = nil
            pageMode = .editing(provider)
        }
    }

    private func handleEditAction(for provider: QuotaProvider) {
        if pageMode == .editing(provider) {
            _ = finishEditingIfNeeded(for: provider)
        } else {
            toggleExpansion(for: provider)
        }
    }

    private func handleTopBarAction() {
        switch pageMode {
        case .normal:
            glmError = nil
            openAIError = nil
            pageMode = .reordering
            listEditMode = .active
        case let .editing(provider):
            _ = finishEditingIfNeeded(for: provider)
        case .reordering:
            listEditMode = .inactive
            pageMode = .normal
        }
    }

    @discardableResult
    private func finishEditingIfNeeded(for provider: QuotaProvider) -> Bool {
        switch provider {
        case .glm:
            return saveGLM()
        case .openai:
            return saveOpenAI()
        }
    }

    private func loadStoredValues() {
        if glmTokenInput.isEmpty {
            glmTokenInput = appViewModel.glmCredentials?.token.replacingOccurrences(of: "Bearer ", with: "") ?? ""
        }
        if openAITokenInput.isEmpty {
            openAITokenInput = appViewModel.openAIAccessToken
        }
        if openAIAccountIdInput.isEmpty {
            openAIAccountIdInput = appViewModel.openAIAccountId
        }
    }

    @discardableResult
    private func saveGLM() -> Bool {
        glmError = nil
        let trimmedValue = glmTokenInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let originalValue = appViewModel.glmCredentials?.token
            .replacingOccurrences(of: "Bearer ", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if trimmedValue == originalValue {
            pageMode = .normal
            return true
        }

        if trimmedValue.isEmpty {
            appViewModel.clearGLMCredentials()
            pageMode = .normal
            return true
        }

        isSavingGLM = true
        Task {
            defer { isSavingGLM = false }
            do {
                try await appViewModel.saveGLMAPIKey(trimmedValue)
                glmTokenInput = appViewModel.glmCredentials?.token.replacingOccurrences(of: "Bearer ", with: "") ?? trimmedValue
                pageMode = .normal
            } catch {
                glmError = error.localizedDescription
            }
        }
        return false
    }

    @discardableResult
    private func saveOpenAI() -> Bool {
        openAIError = nil
        let trimmedToken = openAITokenInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedAccountId = openAIAccountIdInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let originalToken = appViewModel.openAIAccessToken
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let originalAccountId = appViewModel.openAIAccountId
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmedToken == originalToken, trimmedAccountId == originalAccountId {
            pageMode = .normal
            return true
        }

        if trimmedToken.isEmpty {
            appViewModel.clearOpenAICredentials()
            openAITokenInput = ""
            openAIAccountIdInput = ""
            pageMode = .normal
            return true
        }

        isSavingOpenAI = true
        Task {
            defer { isSavingOpenAI = false }
            do {
                try await appViewModel.saveOpenAICredentials(
                    accessToken: trimmedToken,
                    accountId: trimmedAccountId
                )
                openAITokenInput = appViewModel.openAIAccessToken
                openAIAccountIdInput = appViewModel.openAIAccountId
                pageMode = .normal
            } catch {
                openAIError = error.localizedDescription
            }
        }
        return false
    }

    private func moveProviders(from source: IndexSet, to destination: Int) {
        withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
            appViewModel.moveProviders(fromOffsets: source, toOffset: destination)
        }
    }

    private func handleScannedCode(_ code: String) {
        do {
            let payload = try appViewModel.prepareTransferImport(from: code)
            pendingImportPreview = appViewModel.makeTransferImportPreview(for: payload)
        } catch {
            transferImportError = error.localizedDescription
        }
    }

    private func importPayload(_ payload: TransferPayload) async {
        do {
            try await appViewModel.importTransferPayload(payload)
            glmTokenInput = appViewModel.glmCredentials?.token.replacingOccurrences(of: "Bearer ", with: "") ?? ""
            openAITokenInput = appViewModel.openAIAccessToken
            openAIAccountIdInput = appViewModel.openAIAccountId
            glmError = nil
            openAIError = nil
            pendingImportPreview = nil
        } catch {
            transferImportError = error.localizedDescription
        }
    }
}

private enum AccountsPageMode: Equatable {
    case normal
    case editing(QuotaProvider)
    case reordering
}

private struct ProviderDropDelegate: DropDelegate {
    let target: QuotaProvider
    @Binding var draggedProvider: QuotaProvider?
    let currentMode: AccountsPageMode
    let move: (QuotaProvider, QuotaProvider) -> Void

    func dropEntered(info _: DropInfo) {
        guard currentMode == .normal,
              let draggedProvider,
              draggedProvider != target else {
            return
        }

        move(draggedProvider, target)
    }

    func dropUpdated(info _: DropInfo) -> DropProposal? {
        guard currentMode == .normal else { return nil }
        return DropProposal(operation: .move)
    }

    func performDrop(info _: DropInfo) -> Bool {
        draggedProvider = nil
        return currentMode == .normal
    }

    func dropExited(info _: DropInfo) {}
}
