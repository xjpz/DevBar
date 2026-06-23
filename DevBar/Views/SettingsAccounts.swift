// SettingsAccounts.swift
// DevBar

import SwiftUI
import UniformTypeIdentifiers
import WebKit
import DevBarCore

struct SettingsAccounts: View {
    @EnvironmentObject private var appViewModel: AppViewModel
    @State private var glmAPIKeyInput: String = ""
    @State private var originalGLMAPIKeyInput: String = ""
    @State private var showGLMAPIKey = false
    @State private var openAITokenInput: String = ""
    @State private var originalOpenAITokenInput: String = ""
    @State private var showOpenAIToken = false
    @State private var mimoCookieInput: String = ""
    @State private var originalMimoCookieInput: String = ""
    @State private var showMimoCookie = false
    @State private var deepseekTokenInput: String = ""
    @State private var originalDeepseekTokenInput: String = ""
    @State private var showDeepseekToken = false
    @State private var deepseekCookieInput: String = ""
    @State private var originalDeepseekCookieInput: String = ""
    @State private var showDeepseekCookie = false
    @State private var editingProviders: Set<QuotaProvider> = []
    @State private var editingAccountIDs: Set<String> = []
    @State private var draggedAccountID: String?
    @State private var accountDisplayNameInputs: [String: String] = [:]
    @State private var deepseekTokenInputs: [String: String] = [:]
    @State private var originalDeepseekTokenInputs: [String: String] = [:]
    @State private var deepseekCookieInputs: [String: String] = [:]
    @State private var originalDeepseekCookieInputs: [String: String] = [:]
    @State private var isValidatingGLM = false
    @State private var isValidatingOpenAI = false
    @State private var isValidatingMimo = false
    @State private var isValidatingDeepseek = false
    @State private var isTestingGLMPing = false
    @State private var glmLoginError: String?
    @State private var glmPingTestMessage: String?
    @State private var openAIImportError: String?
    @State private var mimoImportError: String?
    @State private var deepseekImportError: String?
    @State private var transferSheetState: TransferSheetState?
    @State private var transferExportError: String?
    @State private var isGeneratingTransferQRCode = false
    @State private var selectedInterval: TimeInterval

    private let intervals: [(String, TimeInterval)] = [
        (String(localized: "minutes_3"), 180),
        (String(localized: "minutes_5"), 300),
        (String(localized: "minutes_10"), 600),
        (String(localized: "minutes_15"), 900),
        (String(localized: "minutes_30"), 1800),
        (String(localized: "minutes_60"), 3600),
        (String(localized: "never"), 0),
    ]

    init() {
        let savedInterval = UserDefaults.standard.double(forKey: Constants.Defaults.refreshIntervalKey)
        _selectedInterval = State(
            initialValue: savedInterval.nonZero ?? Constants.Defaults.defaultRefreshInterval
        )
    }

    private var sortedConfigs: [AccountConfig] {
        appViewModel.accountConfigs.sorted { $0.order < $1.order }
    }

    private var sortedProviderAccounts: [ProviderAccount] {
        appViewModel.providerAccounts.sorted { $0.order < $1.order }
    }

    private var savedMimoCookieValue: String {
        [originalMimoCookieInput, appViewModel.credentials?.token ?? ""]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? ""
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                refreshIntervalCard

                introCard

                ForEach(sortedProviderAccounts) { account in
                    providerAccountCard(for: account)
                }
            }
            .padding(16)
        }
        .scrollIndicators(.hidden)
            .task {
                loadStoredOpenAIToken()
                loadStoredGLMCredentials()
                loadStoredMimoCookie()
                loadStoredDeepSeekCredentials()
                loadAccountDisplayNames()
            }
        .sheet(item: $transferSheetState) { state in
            TransferQRCodeSheet(payload: state.payload, url: state.url, mode: state.mode)
        }
        .onChange(of: selectedInterval) { _, newValue in
            appViewModel.refreshInterval = newValue
            appViewModel.stopAutoRefresh()
            appViewModel.startRefreshIfNeeded()
        }
    }

    private var refreshIntervalCard: some View {
        HStack {
            Text("auto_refresh_interval")
                .font(.subheadline)
            Spacer()
            Picker("", selection: $selectedInterval) {
                ForEach(intervals, id: \.1) { label, value in
                    Text(label).tag(value)
                }
            }
            .pickerStyle(.menu)
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

    private var introCard: some View {
        VStack(alignment: .leading, spacing: 12) {
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

                Text(String(format: String(localized: "accounts_count_format"), sortedProviderAccounts.count))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("迁移到 iPhone")
                        .font(.subheadline.weight(.semibold))
                    Text("生成一个 5 分钟内有效的二维码，在 iPhone 上扫码导入当前配置。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Menu {
                    Button("GLM") {
                        addProviderAccount(.glm)
                    }
                    Button("OpenAI") {
                        addProviderAccount(.openai)
                    }
                    Button("MiMo") {
                        addProviderAccount(.mimo)
                    }
                    Button("DeepSeek") {
                        addProviderAccount(.deepseek)
                    }
                } label: {
                    Image(systemName: "plus")
                        .frame(width: 28, height: 28)
                }
                .menuStyle(.borderlessButton)
                .help("添加 Provider 账号")

                Button {
                    Task {
                        await openTransferSheet()
                    }
                } label: {
                    if isGeneratingTransferQRCode {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Label("显示二维码", systemImage: "qrcode")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isGeneratingTransferQRCode)
            }

            if let transferExportError {
                Text(transferExportError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
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

    private func addProviderAccount(_ provider: QuotaProvider) {
        let account = appViewModel.addProviderAccount(provider: provider)
        accountDisplayNameInputs[account.id] = account.displayName

        if provider == .deepseek {
            deepseekTokenInputs[account.id] = ""
            originalDeepseekTokenInputs[account.id] = ""
            deepseekCookieInputs[account.id] = ""
            originalDeepseekCookieInputs[account.id] = ""
            editingAccountIDs.insert(account.id)
        }
    }

    private func clearLocalAccountState(_ account: ProviderAccount) {
        editingAccountIDs.remove(account.id)
        accountDisplayNameInputs.removeValue(forKey: account.id)
        deepseekTokenInputs.removeValue(forKey: account.id)
        originalDeepseekTokenInputs.removeValue(forKey: account.id)
        deepseekCookieInputs.removeValue(forKey: account.id)
        originalDeepseekCookieInputs.removeValue(forKey: account.id)
    }

    @ViewBuilder
    private func providerAccountCard(for account: ProviderAccount) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            accountCard(for: account)

            if !account.id.hasPrefix("legacy-") {
                HStack(spacing: 8) {
                    Spacer()
                    Button(role: .destructive) {
                        clearLocalAccountState(account)
                        appViewModel.removeProviderAccount(id: account.id)
                    } label: {
                        Image(systemName: "trash")
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.borderless)
                    .help("删除账号")
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 8)
            }
        }
        .onDrag {
            draggedAccountID = account.id
            return NSItemProvider(object: account.id as NSString)
        }
        .onDrop(of: [.text], delegate: AccountDropDelegate(
            targetAccountID: account.id,
            draggedAccountID: $draggedAccountID,
            moveAction: appViewModel.moveProviderAccount
        ))
    }

    @ViewBuilder
    private func accountCard(for account: ProviderAccount) -> some View {
        let config = account.legacyConfig
        let isEditing = account.provider == .deepseek
            ? editingAccountIDs.contains(account.id)
            : editingProviders.contains(account.provider)

        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                providerArtwork(for: config.provider)

                VStack(alignment: .leading, spacing: 2) {
                    Text(config.provider.localizedName)
                        .font(.system(size: 15, weight: .semibold))

                    if account.displayName != config.provider.localizedName {
                        Text(account.displayName)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 8)

                if QuotaProvider.allCases.contains(config.provider) {
                    Button {
                        handleEditAction(for: account)
                    } label: {
                        Text(isEditing ? String(localized: "accounts_done_editing") : String(localized: "accounts_edit_credentials"))
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
                    set: { appViewModel.updateProviderAccountEnabled(id: account.id, isEnabled: $0) }
                ))
                .toggleStyle(.switch)
                .labelsHidden()
                .help(String(localized: config.isEnabled ? "accounts_disable" : "accounts_enable"))
            }

            if isEditing {
                Divider()
                    .overlay(Color.primary.opacity(0.06))

                accountMetadataEditor(for: account)

                switch config.provider {
                case .glm:
                    glmCredentialsEditor
                case .openai:
                    openAICredentialsEditor
                case .mimo:
                    mimoCredentialsEditor
                case .deepseek:
                    deepseekCredentialsEditor(for: account)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground(for: config))
        .overlay(cardBorder(for: config))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .opacity(draggedAccountID == account.id ? 0.82 : 1)
        .animation(.easeInOut(duration: 0.18), value: draggedAccountID)
    }

    private func providerArtwork(for provider: QuotaProvider) -> some View {
        Image(provider.assetName)
            .resizable()
            .scaledToFit()
            .frame(width: 24, height: 24)
            .frame(width: 32, height: 32)
    }

    private func accountMetadataEditor(for account: ProviderAccount) -> some View {
        fieldBlock(title: "备注小标签") {
            TextField(account.provider.localizedName, text: accountDisplayNameBinding(for: account))
                .textFieldStyle(.roundedBorder)
        } footer: {
            Text("用于区分同一个 Provider 下的多个账号")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.primary.opacity(0.035))
        )
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

            glmPingSettingsBlock
        }
    }

    private var glmPingSettingsBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()
                .overlay(Color.primary.opacity(0.06))

            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("provider_ping_title")
                        .font(.caption.weight(.semibold))
                    Text(glmPingCredentialHint)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Toggle("", isOn: Binding(
                    get: { appViewModel.providerPingConfig(for: .glm).isEnabled },
                    set: { isEnabled in
                        var config = appViewModel.providerPingConfig(for: .glm)
                        config.isEnabled = isEnabled
                        appViewModel.updateProviderPingConfig(config)
                    }
                ))
                .toggleStyle(.switch)
                .labelsHidden()
                .disabled(appViewModel.glmAPIKeyForModelCall == nil)
            }

            DatePicker(
                "provider_ping_time",
                selection: glmPingTimeBinding,
                displayedComponents: .hourAndMinute
            )
            .datePickerStyle(.compact)
            .disabled(!appViewModel.providerPingConfig(for: .glm).isEnabled)

            HStack(spacing: 10) {
                Button {
                    testGLMPing()
                } label: {
                    if isTestingGLMPing {
                        ProgressView()
                            .controlSize(.small)
                            .frame(maxWidth: .infinity)
                    } else {
                        Text("provider_ping_test")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.bordered)
                .disabled(isTestingGLMPing || appViewModel.glmAPIKeyForModelCall == nil)

                Text(glmPingStatusText)
                    .font(.caption2)
                    .foregroundStyle(glmPingStatusColor)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let glmPingTestMessage {
                Text(glmPingTestMessage)
                    .font(.caption2)
                    .foregroundStyle(glmPingTestMessage == String(localized: "provider_ping_success") ? Color.secondary : Color.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.primary.opacity(0.035))
        )
    }

    private var mimoCredentialsEditor: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(action: openMiMoLoginWindow) {
                Text("browser_login")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
            }
            .buttonStyle(.bordered)
            .disabled(isValidatingMimo)

            fieldBlock(title: "serviceToken") {
                HStack(spacing: 10) {
                    Group {
                        if showMimoCookie {
                            TextField(String(localized: "mimo_cookie_placeholder"), text: $mimoCookieInput)
                        } else {
                            SecureField(String(localized: "mimo_cookie_placeholder"), text: $mimoCookieInput)
                        }
                    }
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))

                    Button {
                        showMimoCookie.toggle()
                    } label: {
                        Image(systemName: showMimoCookie ? "eye.slash" : "eye")
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.borderless)
                    .help(String(localized: showMimoCookie ? "accounts_hide_token" : "accounts_show_token"))
                }
            } footer: {
                Text("mimo_cookie_hint")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.primary.opacity(0.035))
            )

            if let mimoImportError {
                Label(mimoImportError, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.red.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }

            if let message = appViewModel.mimoCookieRenewalState.message {
                Label(
                    message,
                    systemImage: appViewModel.mimoCookieRenewalState.isFailure ? "exclamationmark.triangle.fill" : "arrow.triangle.2.circlepath"
                )
                .font(.caption2)
                .foregroundStyle(appViewModel.mimoCookieRenewalState.isFailure ? .red : .secondary)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background((appViewModel.mimoCookieRenewalState.isFailure ? Color.red : Color.primary).opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
    }

    private func deepseekCredentialsEditor(for account: ProviderAccount) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                openDeepSeekLoginWindow(account: account)
            } label: {
                Text("browser_login")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
            }
            .buttonStyle(.bordered)
            .disabled(isValidatingDeepseek)

            fieldBlock(title: "Authorization") {
                HStack(spacing: 10) {
                    Group {
                        if showDeepseekToken {
                            TextField("Bearer xxx", text: deepseekTokenBinding(for: account))
                        } else {
                            SecureField("Bearer xxx", text: deepseekTokenBinding(for: account))
                        }
                    }
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))

                    Button {
                        showDeepseekToken.toggle()
                    } label: {
                        Image(systemName: showDeepseekToken ? "eye.slash" : "eye")
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.borderless)
                    .help(String(localized: showDeepseekToken ? "accounts_hide_token" : "accounts_show_token"))
                }
            } footer: {
                Text("deepseek_authorization_hint")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.primary.opacity(0.035))
            )

            fieldBlock(title: "Cookie") {
                HStack(spacing: 10) {
                    Group {
                        if showDeepseekCookie {
                            TextField(String(localized: "mimo_cookie_placeholder"), text: deepseekCookieBinding(for: account))
                        } else {
                            SecureField(String(localized: "mimo_cookie_placeholder"), text: deepseekCookieBinding(for: account))
                        }
                    }
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))

                    Button {
                        showDeepseekCookie.toggle()
                    } label: {
                        Image(systemName: showDeepseekCookie ? "eye.slash" : "eye")
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.borderless)
                    .help(String(localized: showDeepseekCookie ? "accounts_hide_token" : "accounts_show_token"))
                }
            } footer: {
                Text("deepseek_cookie_hint")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.primary.opacity(0.035))
            )

            if let deepseekImportError {
                Label(deepseekImportError, systemImage: "exclamationmark.triangle.fill")
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

    private func accountDisplayNameBinding(for account: ProviderAccount) -> Binding<String> {
        Binding(
            get: { accountDisplayNameInputs[account.id] ?? account.displayName },
            set: { accountDisplayNameInputs[account.id] = $0 }
        )
    }

    private func deepseekTokenBinding(for account: ProviderAccount) -> Binding<String> {
        Binding(
            get: { deepseekTokenInputs[account.id] ?? "" },
            set: { deepseekTokenInputs[account.id] = $0 }
        )
    }

    private func deepseekCookieBinding(for account: ProviderAccount) -> Binding<String> {
        Binding(
            get: { deepseekCookieInputs[account.id] ?? "" },
            set: { deepseekCookieInputs[account.id] = $0 }
        )
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
        guard let key = KeychainService.shared.load(key: DevBarCoreConstants.Keychain.glmAPIKeyKey)
            ?? appViewModel.glmAPIKeyForModelCall else { return }
        glmAPIKeyInput = key
        originalGLMAPIKeyInput = key
    }

    private func loadStoredMimoCookie() {
        guard mimoCookieInput.isEmpty else { return }
        if let token = KeychainService.shared.load(key: DevBarCoreConstants.Keychain.mimoServiceTokenKey) {
            mimoCookieInput = token
            originalMimoCookieInput = token
        }
    }

    private func loadStoredDeepSeekCredentials() {
        for account in appViewModel.providerAccounts where account.provider == .deepseek {
            loadDeepSeekCredentials(for: account)
        }
    }

    private func loadAccountDisplayNames() {
        for account in appViewModel.providerAccounts {
            accountDisplayNameInputs[account.id] = account.displayName
        }
    }

    private func loadDeepSeekCredentials(for account: ProviderAccount) {
        guard deepseekTokenInputs[account.id] == nil,
              let credential = KeychainService.shared.loadProviderCredential(for: account) else { return }
        let token = credential.token ?? ""
        let cookie = credential.cookieString ?? ""
        if !token.isEmpty {
            deepseekTokenInputs[account.id] = token
            originalDeepseekTokenInputs[account.id] = token
        }
        if !cookie.isEmpty {
            deepseekCookieInputs[account.id] = cookie
            originalDeepseekCookieInputs[account.id] = cookie
        }
    }

    private func handleEditAction(for account: ProviderAccount) {
        guard account.provider == .deepseek else {
            if editingProviders.contains(account.provider) {
                saveAccountDisplayName(for: account)
            } else {
                accountDisplayNameInputs[account.id] = account.displayName
            }
            handleProviderEditAction(for: account.provider)
            return
        }

        if editingAccountIDs.contains(account.id) {
            finishDeepSeekEditing(for: account)
            return
        }

        accountDisplayNameInputs[account.id] = account.displayName

        loadDeepSeekCredentials(for: account)
        deepseekImportError = nil
        originalDeepseekTokenInputs[account.id] = deepseekTokenInputs[account.id] ?? ""
        originalDeepseekCookieInputs[account.id] = deepseekCookieInputs[account.id] ?? ""
        editingAccountIDs.insert(account.id)
    }

    private func handleProviderEditAction(for provider: QuotaProvider) {
        if editingProviders.contains(provider) {
            switch provider {
            case .glm:
                finishGLMEditing()
            case .openai:
                finishOpenAIEditing()
            case .mimo:
                finishMimoEditing()
            case .deepseek:
                return
            }
            return
        }

        switch provider {
        case .glm:
            glmLoginError = nil
            glmPingTestMessage = nil
            if let key = KeychainService.shared.load(key: DevBarCoreConstants.Keychain.glmAPIKeyKey)
                ?? appViewModel.glmAPIKeyForModelCall {
                glmAPIKeyInput = key
                originalGLMAPIKeyInput = key
            } else {
                originalGLMAPIKeyInput = glmAPIKeyInput
            }
        case .openai:
            openAIImportError = nil
            originalOpenAITokenInput = openAITokenInput
        case .mimo:
            mimoImportError = nil
            originalMimoCookieInput = mimoCookieInput
        case .deepseek:
            return
        }

        editingProviders.insert(provider)
    }

    private func finishGLMEditing() {
        let trimmed = BigModelAPIClient.normalizedBearerToken(glmAPIKeyInput)
        let originalTrimmed = BigModelAPIClient.normalizedBearerToken(originalGLMAPIKeyInput)

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

    private func finishMimoEditing() {
        let trimmed = mimoCookieInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let originalTrimmed = originalMimoCookieInput.trimmingCharacters(in: .whitespacesAndNewlines)

        guard trimmed != originalTrimmed else {
            editingProviders.remove(.mimo)
            return
        }

        guard !trimmed.isEmpty else {
            appViewModel.logout(provider: .mimo)
            editingProviders.remove(.mimo)
            originalMimoCookieInput = ""
            mimoImportError = nil
            return
        }

        validateAndStoreMimoCookie(trimmed)
    }

    private func finishDeepSeekEditing(for account: ProviderAccount) {
        saveAccountDisplayName(for: account)

        let trimmedToken = (deepseekTokenInputs[account.id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let originalTrimmedToken = (originalDeepseekTokenInputs[account.id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCookie = (deepseekCookieInputs[account.id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let originalTrimmedCookie = (originalDeepseekCookieInputs[account.id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        guard trimmedToken != originalTrimmedToken || trimmedCookie != originalTrimmedCookie else {
            editingAccountIDs.remove(account.id)
            return
        }

        guard !trimmedToken.isEmpty, !trimmedCookie.isEmpty else {
            if trimmedToken.isEmpty && trimmedCookie.isEmpty {
                KeychainService.shared.deleteProviderCredential(for: account)
                originalDeepseekTokenInputs[account.id] = ""
                originalDeepseekCookieInputs[account.id] = ""
                deepseekImportError = nil
                editingAccountIDs.remove(account.id)
            } else {
                deepseekImportError = String(localized: "deepseek_credential_required")
            }
            return
        }

        validateAndStoreDeepSeekCredentials(account: account, token: trimmedToken, cookie: trimmedCookie)
    }

    private func saveAccountDisplayName(for account: ProviderAccount) {
        let value = accountDisplayNameInputs[account.id] ?? account.displayName
        appViewModel.updateProviderAccountDisplayName(id: account.id, displayName: value)
    }

    private func openGLMLoginWindow() {
        glmLoginError = nil

        let controller = LoginWindowController(
            loginURL: Constants.API.loginURL,
            windowTitle: String(localized: "login_bigmodel"),
            targetCookieName: "bigmodel_token_production",
            onTokenExtracted: { token, cookies in
                Task { @MainActor in
                    let cookieString = cookies
                        .filter { ["bigmodel.cn", ".bigmodel.cn"].contains($0.domain) }
                        .map { "\($0.name)=\($0.value)" }
                        .joined(separator: "; ")
                    let credentials = AuthCredentials(token: token, cookieString: cookieString)

                    let isValid = await validateGLMCookie(credentials.cookieString)
                    if isValid {
                        appViewModel.handleLoginSuccess(credentials)
                        editingProviders.remove(.glm)
                    } else {
                        glmLoginError = String(localized: "token_invalid")
                    }
                }
                return true
            }
        )

        controller.show()
    }

    private func loginGLMWithAPIKey() {
        let key = BigModelAPIClient.normalizedBearerToken(glmAPIKeyInput)
        guard !key.isEmpty else { return }

        glmLoginError = nil
        isValidatingGLM = true

        Task { @MainActor in
            let isValid = await validateGLMAPIKey(key)
            isValidatingGLM = false

            if isValid {
                appViewModel.saveGLMAPIKey(key)
                await appViewModel.refreshQuota(silent: true)
                editingProviders.remove(.glm)
                originalGLMAPIKeyInput = BigModelAPIClient.normalizedBearerToken(key)
            } else {
                glmLoginError = String(localized: "api_key_invalid")
            }
        }
    }

    private func validateGLMAPIKey(_ key: String) async -> Bool {
        var request = URLRequest(url: URL(string: Constants.API.quotaLimitURL)!)
        request.setValue(BigModelAPIClient.normalizedBearerToken(key), forHTTPHeaderField: "Authorization")
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

    private var glmPingTimeBinding: Binding<Date> {
        Binding(
            get: {
                let config = appViewModel.providerPingConfig(for: .glm)
                var components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
                components.hour = config.hour
                components.minute = config.minute
                components.second = 0
                return Calendar.current.date(from: components) ?? Date()
            },
            set: { date in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                var config = appViewModel.providerPingConfig(for: .glm)
                config.hour = parts.hour ?? config.hour
                config.minute = parts.minute ?? config.minute
                appViewModel.updateProviderPingConfig(config)
            }
        )
    }

    private var glmPingCredentialHint: String {
        if appViewModel.glmAPIKeyForModelCall != nil {
            return String(localized: "provider_ping_api_key_ready")
        }
        if appViewModel.credentials?.cookieString.isEmpty == false {
            return String(localized: "provider_ping_cookie_only_hint")
        }
        return String(localized: "provider_ping_requires_api_key")
    }

    private var glmPingStatusText: String {
        let config = appViewModel.providerPingConfig(for: .glm)
        if let error = config.lastErrorMessage, !error.isEmpty {
            return "\(String(localized: "provider_ping_failed")): \(error)"
        }
        if let lastSuccessAt = config.lastSuccessAt {
            return "\(String(localized: "provider_ping_last_run")) \(lastSuccessAt.formatted(date: .omitted, time: .shortened))"
        }
        return String(localized: "provider_ping_never_run")
    }

    private var glmPingStatusColor: Color {
        let config = appViewModel.providerPingConfig(for: .glm)
        return config.lastErrorMessage == nil ? .secondary : .red
    }

    private func testGLMPing() {
        glmPingTestMessage = nil
        isTestingGLMPing = true

        Task { @MainActor in
            defer { isTestingGLMPing = false }
            do {
                try await appViewModel.testProviderPing(.glm)
                glmPingTestMessage = String(localized: "provider_ping_success")
            } catch let error as APIError {
                glmPingTestMessage = error.errorDescription
            } catch {
                glmPingTestMessage = error.localizedDescription
            }
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
                appViewModel.upsertCredentialForPrimaryAccount(
                    provider: .openai,
                    token: token,
                    cookieString: nil,
                    accountIdentifier: accountId
                )
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

    private func validateAndStoreMimoCookie(_ rawValue: String) {
        isValidatingMimo = true
        mimoImportError = nil

        let credential = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)

        Task { @MainActor in
            defer { isValidatingMimo = false }

            do {
                _ = try await appViewModel.mimoQuotaViewModel.fetchUsage(
                    serviceToken: credential,
                    silent: true
                )
                await appViewModel.mimoQuotaViewModel.fetchPlanDetailIfNeeded(
                    serviceToken: credential,
                    force: true
                )
                KeychainService.shared.save(
                    key: DevBarCoreConstants.Keychain.mimoServiceTokenKey,
                    value: credential
                )
                appViewModel.upsertCredentialForPrimaryAccount(
                    provider: .mimo,
                    token: nil,
                    cookieString: credential,
                    accountIdentifier: nil
                )
                mimoCookieInput = credential
                originalMimoCookieInput = credential
                editingProviders.remove(.mimo)
                appViewModel.updateAccountConfig(provider: .mimo, isEnabled: true)
                appViewModel.markMimoCookieUpdated()
                appViewModel.refreshAuthenticationState()
            } catch let error as APIError {
                mimoImportError = error.errorDescription
            } catch {
                mimoImportError = error.localizedDescription
            }
        }
    }

    private func openMiMoLoginWindow() {
        mimoImportError = nil

        let controller = LoginWindowController(
            loginURL: DevBarCoreConstants.MiMO.dashboardURL,
            windowTitle: String(localized: "login_mimo_platform"),
            targetCookieName: "api-platform_serviceToken",
            onTokenExtracted: { token, cookies in
                let cookieString = MimoAPIClient.platformCookieString(from: cookies)
                let storedValue = cookieString.isEmpty ? token : cookieString
                let savedValue = savedMimoCookieValue

                if MimoAPIClient.isSameRequiredCookie(storedValue, savedValue) {
                    Task { @MainActor in
                        mimoImportError = String(localized: "mimo_cookie_unchanged_from_browser")
                    }
                    return false
                }

                Task { @MainActor in
                    do {
                        print("[MiMo:WebViewLogin:Settings] cookie string prefix: \(storedValue.prefix(60))...")
                        _ = try await appViewModel.mimoQuotaViewModel.fetchUsage(
                            serviceToken: storedValue,
                            silent: true
                        )
                        print("[MiMo:WebViewLogin:Settings] fetchUsage succeeded")
                        await appViewModel.mimoQuotaViewModel.fetchPlanDetailIfNeeded(
                            serviceToken: storedValue,
                            force: true
                        )
                        print("[MiMo:WebViewLogin:Settings] fetchPlanDetail succeeded")
                        KeychainService.shared.save(
                            key: DevBarCoreConstants.Keychain.mimoServiceTokenKey,
                            value: storedValue
                        )
                        appViewModel.upsertCredentialForPrimaryAccount(
                            provider: .mimo,
                            token: nil,
                            cookieString: storedValue,
                            accountIdentifier: nil
                        )
                        mimoCookieInput = storedValue
                        originalMimoCookieInput = storedValue
                        editingProviders.remove(.mimo)
                        appViewModel.updateAccountConfig(provider: .mimo, isEnabled: true)
                        appViewModel.markMimoCookieUpdated()
                        appViewModel.refreshAuthenticationState()
                        print("[MiMo:WebViewLogin:Settings] auth state refreshed")
                    } catch let error as APIError {
                        print("[MiMo:WebViewLogin:Settings] APIError: \(error)")
                        mimoImportError = error.errorDescription
                    } catch {
                        print("[MiMo:WebViewLogin:Settings] error: \(error)")
                        mimoImportError = error.localizedDescription
                    }
                }
                return true
            }
        )

        controller.show()
    }

    private func openDeepSeekLoginWindow(account: ProviderAccount) {
        deepseekImportError = nil

        // Create a WKWebView to capture the Authorization token from network requests
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()

        let contentController = WKUserContentController()
        // Inject JS that intercepts fetch/XHR to capture the Authorization header
        let captureScript = WKUserScript(
            source: """
            (function() {
                var origFetch = window.fetch;
                window.fetch = function() {
                    var req = arguments[0];
                    var opts = arguments[1] || {};
                    var auth = (typeof req === 'object' && req.headers) ? req.headers.get('Authorization') : (opts.headers && (opts.headers['Authorization'] || opts.headers['authorization']));
                    if (auth && auth.indexOf('Bearer ') === 0) {
                        window.webkit.messageHandlers.deepSeekTokenCapture.postMessage(auth.substring(7));
                    }
                    return origFetch.apply(this, arguments);
                };
                var origOpen = XMLHttpRequest.prototype.open;
                var origSetHeader = XMLHttpRequest.prototype.setRequestHeader;
                XMLHttpRequest.prototype.open = function() {
                    this._authHeader = null;
                    return origOpen.apply(this, arguments);
                };
                XMLHttpRequest.prototype.setRequestHeader = function(name, value) {
                    if (name.toLowerCase() === 'authorization' && value.indexOf('Bearer ') === 0) {
                        this._authHeader = value.substring(7);
                    }
                    return origSetHeader.apply(this, arguments);
                };
                var origSend = XMLHttpRequest.prototype.send;
                XMLHttpRequest.prototype.send = function() {
                    if (this._authHeader) {
                        window.webkit.messageHandlers.deepSeekTokenCapture.postMessage(this._authHeader);
                    }
                    return origSend.apply(this, arguments);
                };
            })();
            """,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        )
        contentController.addUserScript(captureScript)
        contentController.add(DeepSeekSettingsTokenCapture(store: deepSeekTokenStore), name: "deepSeekTokenCapture")
        config.userContentController = contentController

        let webView = WKWebView(frame: .zero, configuration: config)
        let hostingView = NSHostingView(rootView: LoginWebViewWrapper(webView: webView))

        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 700),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        win.contentView = hostingView
        win.title = "DeepSeek Platform"
        win.center()
        win.level = .floating
        win.isReleasedWhenClosed = false
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        deepSeekLoginWebView = webView
        deepSeekLoginWindow = win
        deepSeekLoginAccountID = account.id
        deepSeekTokenStore.capturedToken = nil

        if let url = URL(string: DevBarCoreConstants.DeepSeek.dashboardURL) {
            webView.load(URLRequest(url: url))
        }

        // Poll for the token and cookies
        deepSeekPollTimer?.invalidate()
        deepSeekPollTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
            Task { @MainActor in
                await tryDeepSeekExtract(webView: webView)
            }
        }
    }

    // DeepSeek webview login state
    @State private var deepSeekLoginWebView: WKWebView?
    @State private var deepSeekLoginWindow: NSWindow?
    @State private var deepSeekLoginAccountID: String?
    @StateObject private var deepSeekTokenStore = DeepSeekTokenStore()
    @State private var deepSeekPollTimer: Timer?

    @MainActor
    private func tryDeepSeekExtract(webView: WKWebView) async {
        // Check if we captured a Bearer token from network interception
        guard let bearerToken = deepSeekTokenStore.capturedToken, !bearerToken.isEmpty else { return }

        let cookies = await webView.configuration.websiteDataStore.httpCookieStore.allCookies()
        let cookieString = cookies
            .filter { $0.domain.contains("deepseek.com") }
            .map { "\($0.name)=\($0.value)" }
            .joined(separator: "; ")

        guard !cookieString.isEmpty else { return }

        // Stop polling
        deepSeekPollTimer?.invalidate()
        deepSeekPollTimer = nil

        // Close the window
        deepSeekLoginWindow?.close()
        deepSeekLoginWindow = nil
        deepSeekLoginWebView = nil

        guard let accountID = deepSeekLoginAccountID else { return }
        deepSeekLoginAccountID = nil
        await validateAndStoreDeepSeekFromWebView(accountID: accountID, token: bearerToken, cookie: cookieString)
    }

    private func validateAndStoreDeepSeekFromWebView(accountID: String, token: String, cookie: String) async {
        isValidatingDeepseek = true
        deepseekImportError = nil
        defer { isValidatingDeepseek = false }

        let bearerToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCookie = cookie.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !bearerToken.isEmpty, !trimmedCookie.isEmpty else {
            deepseekImportError = String(localized: "deepseek_credential_required")
            return
        }

        do {
            guard let account = appViewModel.providerAccounts.first(where: { $0.id == accountID }) else { return }
            let apiClient = DeepSeekAPIClient()
            _ = try await apiClient.fetchUsage(token: bearerToken, cookieString: trimmedCookie)

            _ = appViewModel.saveCredential(
                for: account.id,
                token: bearerToken,
                cookieString: trimmedCookie,
                accountIdentifier: nil
            )

            deepseekTokenInputs[account.id] = bearerToken
            originalDeepseekTokenInputs[account.id] = bearerToken
            deepseekCookieInputs[account.id] = trimmedCookie
            originalDeepseekCookieInputs[account.id] = trimmedCookie
            editingAccountIDs.remove(account.id)
            appViewModel.updateProviderAccountEnabled(id: account.id, isEnabled: true)
            appViewModel.refreshAuthenticationState()

            await appViewModel.deepSeekQuotaViewModel.fetchUsage(
                token: bearerToken,
                cookieString: trimmedCookie,
                silent: true
            )
        } catch let error as APIError {
            deepseekImportError = error.errorDescription
        } catch {
            deepseekImportError = error.localizedDescription
        }
    }

    private func validateAndStoreDeepSeekCredentials(account: ProviderAccount, token: String, cookie: String) {
        isValidatingDeepseek = true
        deepseekImportError = nil

        Task { @MainActor in
            defer { isValidatingDeepseek = false }

            do {
                let apiClient = DeepSeekAPIClient()
                _ = try await apiClient.fetchUsage(token: token, cookieString: cookie)

                _ = appViewModel.saveCredential(
                    for: account.id,
                    token: token,
                    cookieString: cookie,
                    accountIdentifier: nil
                )

                deepseekTokenInputs[account.id] = token
                originalDeepseekTokenInputs[account.id] = token
                deepseekCookieInputs[account.id] = cookie
                originalDeepseekCookieInputs[account.id] = cookie
                editingAccountIDs.remove(account.id)
                appViewModel.updateProviderAccountEnabled(id: account.id, isEnabled: true)
                appViewModel.refreshAuthenticationState()

                await appViewModel.deepSeekQuotaViewModel.fetchUsage(
                    token: token,
                    cookieString: cookie,
                    silent: true
                )
            } catch let error as APIError {
                deepseekImportError = error.errorDescription
            } catch {
                deepseekImportError = error.localizedDescription
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

    @MainActor
    private func openTransferSheet() async {
        transferExportError = nil
        isGeneratingTransferQRCode = true
        defer { isGeneratingTransferQRCode = false }

        do {
            let payload = appViewModel.makeTransferPayload()
            let result = try await TransferRelayService.shared.makeTransferQRCode(
                for: payload,
                client: TransferRelayClientInfo(
                    platform: "macos",
                    appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
                    buildNumber: Bundle.main.infoDictionary?["CFBundleVersion"] as? String,
                    deviceName: Host.current().localizedName,
                    locale: Locale.current.identifier,
                    timezone: TimeZone.current.identifier
                )
            )
            transferSheetState = TransferSheetState(payload: result.payload, url: result.url, mode: result.mode)
        } catch {
            transferExportError = error.localizedDescription
        }
    }
}

private struct TransferSheetState: Identifiable {
    let payload: TransferPayload
    let url: URL
    let mode: TransferQRCodeMode

    var id: String { url.absoluteString }
}

private struct AccountDropDelegate: DropDelegate {
    let targetAccountID: String
    @Binding var draggedAccountID: String?
    let moveAction: (String, String) -> Void

    func dropEntered(info: DropInfo) {
        guard let draggedAccountID, draggedAccountID != targetAccountID else { return }
        moveAction(draggedAccountID, targetAccountID)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggedAccountID = nil
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

private extension Double {
    var nonZero: Double? {
        self > 0 ? self : nil
    }
}

/// Message handler that forwards captured DeepSeek Bearer token.
private final class DeepSeekSettingsTokenCapture: NSObject, WKScriptMessageHandler {
    let store: DeepSeekTokenStore
    init(store: DeepSeekTokenStore) { self.store = store }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "deepSeekTokenCapture",
              let token = message.body as? String, !token.isEmpty else { return }
        Task { @MainActor in
            store.capturedToken = token
        }
    }
}
