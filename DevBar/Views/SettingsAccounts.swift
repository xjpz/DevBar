// SettingsAccounts.swift
// DevBar

import SwiftUI
import UniformTypeIdentifiers

struct SettingsAccounts: View {
    @EnvironmentObject private var appViewModel: AppViewModel
    @State private var glmAPIKeyInput: String = ""
    @State private var originalGLMAPIKeyInput: String = ""
    @State private var showGLMAPIKey = false
    @State private var openAITokenInput: String = ""
    @State private var originalOpenAITokenInput: String = ""
    @State private var showOpenAIToken = false
    @State private var editingProviders: Set<QuotaProvider> = []
    @State private var draggedProvider: QuotaProvider?
    @State private var isValidatingGLM = false
    @State private var isValidatingOpenAI = false
    @State private var glmLoginError: String?
    @State private var openAIImportError: String?

    private var sortedConfigs: [AccountConfig] {
        appViewModel.accountConfigs.sorted { $0.order < $1.order }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                introCard

                ForEach(sortedConfigs) { config in
                    accountCard(for: config)
                        .onDrag {
                            draggedProvider = config.provider
                            return NSItemProvider(object: config.provider.rawValue as NSString)
                        }
                        .onDrop(
                            of: [UTType.plainText],
                            delegate: AccountDropDelegate(
                                target: config.provider,
                                draggedProvider: $draggedProvider,
                                moveAction: moveDraggedProvider(_:to:)
                            )
                        )
                }
            }
            .padding(16)
        }
        .scrollIndicators(.hidden)
        .task {
            loadStoredOpenAIToken()
            loadStoredGLMCredentials()
        }
    }

    private var introCard: some View {
        HStack(spacing: 8) {
            Label {
                Text("accounts_section_hint")
            } icon: {
                Image(systemName: "arrow.up.arrow.down")
                    .font(.caption2)
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            Spacer()

            Text(String(format: String(localized: "accounts_count_format"), sortedConfigs.count))
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func accountCard(for config: AccountConfig) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                providerArtwork(for: config.provider)

                Text(config.provider.localizedName)
                    .font(.system(size: 15, weight: .semibold))

                Spacer(minLength: 8)

                if config.provider == .glm || config.provider == .openai {
                    Button {
                        handleEditAction(for: config.provider)
                    } label: {
                        Text(editingProviders.contains(config.provider) ? String(localized: "accounts_done_editing") : String(localized: "accounts_edit_credentials"))
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.primary.opacity(0.06))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .layoutPriority(1)
                }

                Toggle("", isOn: Binding(
                    get: { config.isEnabled },
                    set: { appViewModel.updateAccountConfig(provider: config.provider, isEnabled: $0) }
                ))
                .toggleStyle(.switch)
                .labelsHidden()
                .help(String(localized: config.isEnabled ? "accounts_disable" : "accounts_enable"))
            }

            if config.isEnabled && editingProviders.contains(config.provider) {
                Divider()
                    .overlay(Color.primary.opacity(0.06))

                switch config.provider {
                case .glm:
                    glmCredentialsEditor
                case .openai:
                    openAICredentialsEditor
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground(for: config))
        .overlay(cardBorder(for: config))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .opacity(draggedProvider == config.provider ? 0.82 : 1)
        .animation(.easeInOut(duration: 0.18), value: draggedProvider)
    }

    private func providerArtwork(for provider: QuotaProvider) -> some View {
        Image(provider.assetName)
            .resizable()
            .scaledToFit()
            .frame(width: 24, height: 24)
            .frame(width: 32, height: 32)
    }

    private var openAICredentialsEditor: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                loadOpenAITokenFromCodexConfig()
            } label: {
                Text("accounts_read_from_config")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .disabled(isValidatingOpenAI)

            sensitiveTokenField

            if let openAIImportError {
                Label(openAIImportError, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.red.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
    }

    private var glmCredentialsEditor: some View {
        VStack(spacing: 12) {
            Button(action: openGLMLoginWindow) {
                Text("browser_login")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .disabled(isValidatingGLM)

            VStack(spacing: 10) {
                HStack {
                    Text("API Key")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }

                HStack(spacing: 10) {
                    Group {
                        if showGLMAPIKey {
                            TextField("enter_api_key", text: $glmAPIKeyInput)
                        } else {
                            SecureField("enter_api_key", text: $glmAPIKeyInput)
                        }
                    }
                    .textFieldStyle(.plain)
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color(nsColor: .textBackgroundColor))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                    )
                    .font(.system(size: 12, design: .monospaced))

                    Button {
                        showGLMAPIKey.toggle()
                    } label: {
                        Image(systemName: showGLMAPIKey ? "eye.slash" : "eye")
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.borderless)
                }

                Text("accounts_glm_api_key_hint")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let glmLoginError {
                Label(glmLoginError, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.red.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
    }

    private var sensitiveTokenField: some View {
        fieldBlock(title: "Access Token") {
            HStack(spacing: 10) {
                Group {
                    if showOpenAIToken {
                        TextField(String(localized: "openai_token_placeholder"), text: $openAITokenInput)
                    } else {
                        SecureField(String(localized: "openai_token_placeholder"), text: $openAITokenInput)
                    }
                }
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))

                Button {
                    showOpenAIToken.toggle()
                } label: {
                    Image(systemName: showOpenAIToken ? "eye.slash" : "eye")
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.borderless)
                .help(String(localized: showOpenAIToken ? "accounts_hide_token" : "accounts_show_token"))
            }
        } footer: {
            Text("accounts_openai_token_hint")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.primary.opacity(0.035))
        )
    }

    private func fieldBlock<Content: View, Footer: View>(
        title: String,
        @ViewBuilder content: () -> Content,
        @ViewBuilder footer: () -> Footer
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)

            content()
            footer()
        }
    }

    private func cardBackground(for config: AccountConfig) -> some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(Color(nsColor: .controlBackgroundColor))
            .overlay(
                LinearGradient(
                    colors: [
                        config.provider.accentColor.opacity(config.isEnabled ? 0.10 : 0.04),
                        Color.clear
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
    }

    private func cardBorder(for config: AccountConfig) -> some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .strokeBorder(
                config.provider.accentColor.opacity(config.isEnabled ? 0.2 : 0.08),
                lineWidth: 1
            )
    }

    private func loadStoredOpenAIToken() {
        guard openAITokenInput.isEmpty else { return }
        if let token = KeychainService.shared.load(key: Constants.Keychain.openAIAccessTokenKey) {
            openAITokenInput = token
            originalOpenAITokenInput = token
        }
    }

    private func loadStoredGLMCredentials() {
        guard glmAPIKeyInput.isEmpty else { return }
        guard let credentials = appViewModel.credentials, credentials.cookieString.isEmpty else { return }
        glmAPIKeyInput = credentials.token
        originalGLMAPIKeyInput = credentials.token
    }

    private func handleEditAction(for provider: QuotaProvider) {
        if editingProviders.contains(provider) {
            switch provider {
            case .glm:
                finishGLMEditing()
            case .openai:
                finishOpenAIEditing()
            }
            return
        }

        switch provider {
        case .glm:
            glmLoginError = nil
            if let credentials = appViewModel.credentials, credentials.cookieString.isEmpty {
                glmAPIKeyInput = credentials.token
                originalGLMAPIKeyInput = credentials.token
            } else {
                originalGLMAPIKeyInput = glmAPIKeyInput
            }
        case .openai:
            openAIImportError = nil
            originalOpenAITokenInput = openAITokenInput
        }

        editingProviders.insert(provider)
    }

    private func finishGLMEditing() {
        let trimmed = glmAPIKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let originalTrimmed = originalGLMAPIKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)

        guard trimmed != originalTrimmed else {
            editingProviders.remove(.glm)
            return
        }

        guard !trimmed.isEmpty else {
            glmLoginError = String(localized: "accounts_glm_api_key_required")
            return
        }

        loginGLMWithAPIKey()
    }

    private func finishOpenAIEditing() {
        let trimmed = openAITokenInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let originalTrimmed = originalOpenAITokenInput.trimmingCharacters(in: .whitespacesAndNewlines)

        guard trimmed != originalTrimmed else {
            editingProviders.remove(.openai)
            return
        }

        guard !trimmed.isEmpty else {
            appViewModel.logout(provider: .openai)
            editingProviders.remove(.openai)
            originalOpenAITokenInput = ""
            openAIImportError = nil
            return
        }

        validateAndStoreOpenAIToken(trimmed)
    }

    private func openGLMLoginWindow() {
        glmLoginError = nil

        let controller = LoginWindowController(
            loginURL: Constants.API.loginURL,
            onCookiesExtracted: { credentials in
                Task { @MainActor in
                    let isValid = await validateGLMCookie(credentials.cookieString)
                    if isValid {
                        appViewModel.handleLoginSuccess(credentials)
                        editingProviders.remove(.glm)
                    } else {
                        glmLoginError = String(localized: "token_invalid")
                    }
                }
            }
        )

        controller.show()
    }

    private func loginGLMWithAPIKey() {
        let key = glmAPIKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }

        glmLoginError = nil
        isValidatingGLM = true

        Task { @MainActor in
            let isValid = await validateGLMAPIKey(key)
            isValidatingGLM = false

            if isValid {
                appViewModel.handleLoginSuccess(AuthCredentials(token: key, cookieString: ""))
                editingProviders.remove(.glm)
                originalGLMAPIKeyInput = key
            } else {
                glmLoginError = String(localized: "api_key_invalid")
            }
        }
    }

    private func validateGLMAPIKey(_ key: String) async -> Bool {
        var request = URLRequest(url: URL(string: Constants.API.quotaLimitURL)!)
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 10

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return false
            }

            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let success = json["success"] as? Bool ?? false
                let code = json["code"] as? Int ?? -1
                return success || code == 0
            }

            return false
        } catch {
            return false
        }
    }

    private func loadOpenAITokenFromCodexConfig() {
        openAIImportError = nil

        do {
            let token = try CodexAuthFileLoader.loadOpenAIAccessToken()

            guard !token.isEmpty else {
                openAIImportError = String(localized: "accounts_openai_config_missing_token")
                return
            }

            openAITokenInput = token
        } catch {
            openAIImportError = String(localized: "accounts_openai_config_read_failed")
        }
    }

    private func validateAndStoreOpenAIToken(_ token: String) {
        isValidatingOpenAI = true
        openAIImportError = nil

        let accountId = UserDefaults.standard.string(forKey: Constants.OpenAI.accountIdKey)

        Task { @MainActor in
            defer { isValidatingOpenAI = false }

            do {
                _ = try await appViewModel.openAIQuotaViewModel.fetchUsage(
                    accessToken: token,
                    accountId: accountId,
                    silent: true
                )
                KeychainService.shared.save(key: Constants.Keychain.openAIAccessTokenKey, value: token)
                originalOpenAITokenInput = token
                editingProviders.remove(.openai)
                appViewModel.refreshAuthenticationState()
            } catch let error as APIError {
                openAIImportError = error.errorDescription
            } catch {
                openAIImportError = error.localizedDescription
            }
        }
    }

    private func validateGLMCookie(_ cookieString: String) async -> Bool {
        var request = URLRequest(url: URL(string: Constants.API.subscriptionListURL)!)
        request.setValue(cookieString, forHTTPHeaderField: "Cookie")
        request.timeoutInterval = 10

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                return true
            }
            return false
        } catch {
            return false
        }
    }

    private func moveDraggedProvider(_ dragged: QuotaProvider, to target: QuotaProvider) {
        guard dragged != target else { return }

        var configs = appViewModel.accountConfigs.sorted { $0.order < $1.order }
        guard let fromIndex = configs.firstIndex(where: { $0.provider == dragged }),
              let toIndex = configs.firstIndex(where: { $0.provider == target }) else {
            return
        }

        let moving = configs.remove(at: fromIndex)
        configs.insert(moving, at: toIndex)
        for index in configs.indices {
            configs[index].order = index
        }
        appViewModel.accountConfigs = configs
    }
}

private struct AccountDropDelegate: DropDelegate {
    let target: QuotaProvider
    @Binding var draggedProvider: QuotaProvider?
    let moveAction: (QuotaProvider, QuotaProvider) -> Void

    func dropEntered(info: DropInfo) {
        guard let draggedProvider, draggedProvider != target else { return }
        moveAction(draggedProvider, target)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggedProvider = nil
        return true
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func validateDrop(info: DropInfo) -> Bool {
        true
    }

    func dropExited(info: DropInfo) {
        guard info.location.x.isFinite else { return }
    }
}
