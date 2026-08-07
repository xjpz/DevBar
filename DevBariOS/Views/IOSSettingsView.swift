import DevBarCore
import Combine
import PhotosUI
import SwiftData
import SwiftUI
import UIKit

struct IOSSettingsView: View {
    @EnvironmentObject private var appViewModel: IOSAppViewModel
    @EnvironmentObject private var languageManager: IOSLanguageManager
    @EnvironmentObject private var themeManager: IOSThemeManager
    @Environment(\.themeTokens) private var theme
    @State private var versionTapCount = 0
    @State private var isShowingDebugInfo = false
    @State private var copiedDebugItemID: String?
    @State private var currentAppIconOption: IOSAppIconOption = .default
    @StateObject private var iCloudSyncCoordinator = ICloudSyncCoordinator.shared
    @AppStorage(
        QuotaResetTimeDisplayMode.defaultsKey,
        store: QuotaResetTimeDisplayMode.sharedDefaults
    )
    private var resetTimeDisplayMode = QuotaResetTimeDisplayMode.exact.rawValue

    private let intervals: [(LocalizedStringKey, TimeInterval)] = [
        ("ios_settings_interval_3m", 180),
        ("ios_settings_interval_5m", 300),
        ("ios_settings_interval_10m", 600),
        ("ios_settings_interval_15m", 900),
        ("ios_settings_interval_30m", 1800),
        ("ios_settings_interval_60m", 3600),
        ("ios_settings_interval_never", 0),
    ]

    var body: some View {
        Form {
            Section("ios_settings_appearance_section") {
                Picker(selection: $languageManager.selectedLanguage) {
                    Text("follow_system").tag(IOSAppLanguage.system)
                    Text("ios_settings_language_zh_hans").tag(IOSAppLanguage.zhHans)
                    Text("ios_settings_language_en").tag(IOSAppLanguage.en)
                } label: {
                    Label("language", systemImage: "globe")
                }
                .accessibilityIdentifier("ios.settings.language")

                Picker(selection: $themeManager.selectedMode) {
                    Text("ios_settings_theme_system").tag(IOSThemeMode.system)
                    Text("ios_settings_theme_light").tag(IOSThemeMode.light)
                    Text("ios_settings_theme_dark").tag(IOSThemeMode.geek)
                } label: {
                    Label("ios_settings_theme", systemImage: "paintpalette")
                }
                .accessibilityIdentifier("ios.settings.theme")

                Picker(selection: $themeManager.selectedFont) {
                    ForEach(IOSAppFont.allCases) { font in
                        Text(font.titleKey).tag(font)
                    }
                } label: {
                    Label("ios_settings_font", systemImage: "a.square")
                }
                .accessibilityIdentifier("ios.settings.font")

                Picker(selection: $themeManager.timeFormat) {
                    ForEach(IOSTimeFormat.allCases) { format in
                        Text(format.displayName).tag(format)
                    }
                } label: {
                    Label(String(localized: "ios_settings_time_format", defaultValue: "Time Format"), systemImage: "clock")
                }
                .accessibilityIdentifier("ios.settings.timeFormat")

                settingsLink(
                    title: localized("ios_settings_app_icon_title"),
                    systemImage: "app.dashed",
                    summary: currentAppIconOption.displayName
                ) {
                    IOSAppIconSettingsView(currentOption: $currentAppIconOption)
                }
            }

            Section("ios_settings_ai_quota_section") {
                Picker(selection: $resetTimeDisplayMode) {
                    Text("quota_reset_time_exact").tag(QuotaResetTimeDisplayMode.exact.rawValue)
                    Text("quota_reset_time_countdown").tag(QuotaResetTimeDisplayMode.countdown.rawValue)
                } label: {
                    Label("quota_reset_time_display", systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                }
                .accessibilityIdentifier("ios.settings.quotaResetTimeDisplay")
                .onChange(of: resetTimeDisplayMode) { _, _ in
                    WidgetDataManager.shared.reloadAllTimelines()
                }

                Picker(selection: $appViewModel.refreshInterval) {
                    ForEach(intervals, id: \.1) { label, value in
                        Text(label).tag(value)
                    }
                } label: {
                    Label("ios_settings_auto_refresh_interval", systemImage: "arrow.clockwise")
                }
                .accessibilityIdentifier("ios.settings.refreshInterval")
            }

            Section("ios_settings_ai_features_section") {
                settingsLink(
                    title: localized("ios_settings_hermes_title"),
                    systemImage: "bubble.left.and.bubble.right",
                    summary: hermesSummary
                ) {
                    IOSHermesSettingsView()
                }

                settingsLink(
                    title: "Home Assistant",
                    systemImage: "house.fill",
                    summary: homeAssistantSummary
                ) {
                    IOSHomeAssistantSettingsView()
                }
            }

            Section("ios_settings_device_system_section") {
                settingsLink(
                    title: "iCloud 同步",
                    systemImage: "icloud",
                    summary: iCloudSyncSummary
                ) {
                    IOSICloudSyncSettingsView(coordinator: iCloudSyncCoordinator)
                }

                settingsLink(
                    title: localized("ios_settings_device_widget_section"),
                    systemImage: "iphone.and.arrow.forward",
                    summary: deviceWidgetSummary
                ) {
                    IOSDeviceWidgetSettingsView()
                }

                settingsLink(
                    title: localized("ios_settings_live_activity_title"),
                    systemImage: "iphone.radiowaves.left.and.right",
                    summary: liveActivitySummary
                ) {
                    IOSLiveActivitySettingsView()
                }

                settingsLink(
                    title: localized("ios_settings_home_shortcuts_section"),
                    systemImage: "square.grid.2x2",
                    summary: homeScreenShortcutSummary
                ) {
                    IOSHomeScreenShortcutSettingsView()
                }
            }

            Section("ios_settings_notifications_section") {
                settingsLink(
                    title: localized("ios_settings_push_notifications_section"),
                    systemImage: "bell",
                    summary: pushNotificationSummary
                ) {
                    IOSPushSettingsView()
                }

                settingsLink(
                    title: localized("ios_settings_live_message_section"),
                    systemImage: "quote.bubble",
                    summary: appViewModel.devBarLiveMessageStatus.title
                ) {
                    IOSLiveMessageSettingsView()
                }

                settingsLink(
                    title: localized("ios_settings_greeting_section"),
                    systemImage: "quote.opening",
                    summary: greetingPreviewText
                ) {
                    IOSGreetingSettingsView()
                }
            }

            Section {
                LabeledContent {
                    Text(String(localized: "ios_settings_app_name"))
                } label: {
                    Label("ios_settings_app_label", systemImage: "app")
                }

                LabeledContent {
                    Text(appVersionText)
                } label: {
                    Label("ios_settings_version_label", systemImage: "number")
                }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        handleVersionTap()
                    }
            } header: {
                Text("ios_settings_about_section")
            } footer: {
                Text("ios_settings_icp_record")
                    .font(.footnote)
                    .foregroundStyle(theme.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 12)
            }
        }
        .scrollContentBackground(.hidden)
        .iosGeekScreenBackground(theme)
        .toolbarBackground(.hidden, for: .navigationBar)
        .navigationTitle("ios_settings_title")
        .navigationBarTitleDisplayMode(.large)
        .toolbar(.hidden, for: .tabBar)
        .accessibilityIdentifier("ios.settings.screen")
        .sheet(isPresented: $isShowingDebugInfo) {
            IOSSettingsDebugInfoSheet(
                items: debugInfoItems,
                copiedItemID: copiedDebugItemID,
                onCopy: copyDebugValue
            )
        }
        .onAppear {
            currentAppIconOption = IOSAppIconController.shared.preferredOption
        }
    }

    @ViewBuilder
    private func settingsLink<Destination: View>(
        title: String,
        systemImage: String,
        summary: String,
        @ViewBuilder destination: () -> Destination
    ) -> some View {
        NavigationLink {
            destination()
        } label: {
            IOSSettingsLinkLabel(title: title, systemImage: systemImage, summary: summary)
        }
    }

    private var deviceWidgetSummary: String {
        let avatarText = appViewModel.macThemeWidgetAvatarFileName == nil
            ? localized("ios_settings_avatar_not_set")
            : localized("ios_settings_avatar_set")
        return "\(appViewModel.relayDeviceName) / \(avatarText)"
    }

    private var pushNotificationSummary: String {
        let enabledCount = [
            appViewModel.pushNotificationPreferences.pushEnabled,
            DevBarCoreConstants.Features.agentWatcherEnabled && appViewModel.pushNotificationPreferences.agentWatcherEnabled,
            appViewModel.pushNotificationPreferences.summaryEnabled,
        ].filter { $0 }.count
        return enabledCount == 0
            ? localized("ios_settings_not_enabled")
            : String(format: localized("ios_settings_enabled_items_format"), enabledCount)
    }

    private var homeScreenShortcutSummary: String {
        let count = appViewModel.selectedHomeScreenShortcutActions.count
        return count == 0
            ? localized("ios_settings_not_enabled")
            : String(format: localized("ios_settings_enabled_count_format"), count)
    }

    private var hermesSummary: String {
        if !appViewModel.hermesSettings.apiBaseURL.isEmpty,
           HermesAPIClient.chatURL(from: appViewModel.hermesSettings.apiBaseURL) == nil {
            return localized("ios_settings_hermes_invalid_url")
        }
        if appViewModel.isHermesConfigured {
            let model = appViewModel.hermesSettings.hermesModel.trimmingCharacters(in: .whitespacesAndNewlines)
            return model.isEmpty ? "Hermes HTTP" : "Hermes HTTP · \(model)"
        }
        return "未配置"
    }

    private var homeAssistantSummary: String {
        let store = HomeAssistantSettingsStore()
        let settings = store.load()
        guard settings.isConfigured, !store.loadToken().isEmpty else { return "未配置" }
        if let host = URL(string: settings.externalURL)?.host {
            return settings.internalURL.isEmpty || settings.internalSSIDs.isEmpty
                ? host
                : "家庭 Wi-Fi 内网优先 · \(host)"
        }
        return "已配置"
    }

    private var liveActivitySummary: String {
        guard appViewModel.liveActivitySettings.isEnabled else {
            return localized("ios_settings_not_enabled")
        }
        guard appViewModel.liveActivitySettings.isValidTimeRange else {
            return localized("ios_settings_time_range_needs_adjustment")
        }
        return String(
            format: "%02d:%02d-%02d:%02d",
            appViewModel.liveActivitySettings.startHour,
            appViewModel.liveActivitySettings.startMinute,
            appViewModel.liveActivitySettings.endHour,
            appViewModel.liveActivitySettings.endMinute
        )
    }

    private var iCloudSyncSummary: String {
        guard iCloudSyncCoordinator.settings.isEnabled else {
            return "未开启"
        }
        switch iCloudSyncCoordinator.availability {
        case .available:
            return "已开启 · iCloud 可用"
        case .checking:
            return "正在检查"
        case .notChecked:
            return "已开启"
        case .unavailable(let message):
            return message
        }
    }

    private var greetingPreviewText: String {
        let firstLine = themeManager.developerGreeting
            .split(whereSeparator: \.isNewline)
            .first
            .map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let firstLine, !firstLine.isEmpty {
            return firstLine
        }
        return IOSThemeManager.defaultGreeting
            .split(whereSeparator: \.isNewline)
            .first
            .map(String.init) ?? IOSThemeManager.defaultGreeting
    }

    private var appVersionText: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String
        guard let build, !build.isEmpty else { return version }
        return "\(version) (\(build))"
    }

    private var debugInfoItems: [IOSSettingsDebugInfoItem] {
        let relayManager = appViewModel.deviceRelayManager
        let pushDebug = IOSPushNotificationCoordinator.shared.debugSnapshot()
        let peers = relayManager.peers
            .map { peer in
                let name = peer.deviceName?.isEmpty == false ? peer.deviceName! : peer.deviceId
                return "\(name) / \(peer.deviceType.rawValue) / \(peer.deviceId)"
            }
            .joined(separator: "\n")

        return [
            IOSSettingsDebugInfoItem(title: "App Version", value: appVersionText),
            IOSSettingsDebugInfoItem(title: "Bundle ID", value: Bundle.main.bundleIdentifier ?? localized("ios_settings_debug_not_available")),
            IOSSettingsDebugInfoItem(title: "Relay API", value: DevBarCoreConstants.DeviceRelay.baseURL),
            IOSSettingsDebugInfoItem(title: "Relay Device ID", value: relayManager.localDeviceID ?? localized("ios_settings_debug_not_registered")),
            IOSSettingsDebugInfoItem(title: "Relay Device Token", value: relayManager.deviceToken ?? localized("ios_settings_debug_not_registered")),
            IOSSettingsDebugInfoItem(title: "Relay State", value: relayConnectionStateText(relayManager.connectionState)),
            IOSSettingsDebugInfoItem(title: "Relay Transport", value: relayManager.activeTransport.rawValue),
            IOSSettingsDebugInfoItem(title: "Push Environment", value: IOSPushNotificationCoordinator.pushEnvironment.rawValue),
            IOSSettingsDebugInfoItem(
                title: "APNs Token",
                value: pushDebug.apnsTokenFingerprint.map { "current-process / \($0)" }
                    ?? localized("ios_settings_debug_not_registered")
            ),
            IOSSettingsDebugInfoItem(title: "Live Activity Push-to-Start Token", value: pushDebug.liveActivityPushToStartToken ?? localized("ios_settings_debug_not_available")),
            IOSSettingsDebugInfoItem(title: "Last Push Registration", value: pushDebug.lastPushRegistration ?? localized("ios_settings_debug_not_synced")),
            IOSSettingsDebugInfoItem(title: "Last Live Activity Push-to-Start Registration", value: pushDebug.lastLiveActivityPushToStartRegistration ?? localized("ios_settings_debug_not_synced")),
            IOSSettingsDebugInfoItem(title: "Paired Devices", value: peers.isEmpty ? localized("ios_settings_debug_none") : peers),
            IOSSettingsDebugInfoItem(title: "Last Relay Error", value: relayManager.lastErrorMessage ?? localized("ios_settings_debug_none")),
        ]
    }

    private func handleVersionTap() {
        versionTapCount += 1
        if versionTapCount >= 5 {
            versionTapCount = 0
            isShowingDebugInfo = true
        }
    }

    private func copyDebugValue(_ item: IOSSettingsDebugInfoItem) {
        UIPasteboard.general.string = item.value
        copiedDebugItemID = item.id
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            if copiedDebugItemID == item.id {
                copiedDebugItemID = nil
            }
        }
    }

    private func relayConnectionStateText(_ state: DeviceRelayConnectionState) -> String {
        switch state {
        case .disconnected:
            return "disconnected"
        case .connecting:
            return "connecting"
        case .connected:
            return "connected"
        case .failed(let message):
            return "failed: \(message)"
        }
    }

    private func localized(_ key: String.LocalizationValue) -> String {
        String(localized: key, locale: languageManager.currentLocale)
    }
}

@MainActor
private struct IOSICloudSyncSettingsView: View {
    @ObservedObject var coordinator: ICloudSyncCoordinator
    @Environment(\.modelContext) private var modelContext
    @Environment(\.themeTokens) private var theme

    var body: some View {
        Form {
            Section {
                Toggle(isOn: enabledBinding) {
                    Label("iCloud 同步", systemImage: "icloud")
                }
                .accessibilityIdentifier("ios.settings.icloud.enabled")

                HStack {
                    Label("状态", systemImage: "checkmark.icloud")
                    Spacer()
                    Text(coordinator.availability.title)
                        .foregroundStyle(statusColor)
                        .multilineTextAlignment(.trailing)
                }

                if let lastCheckedAt = coordinator.lastCheckedAt {
                    LabeledContent("上次检查") {
                        Text(lastCheckedAt.formatted(date: .abbreviated, time: .shortened))
                            .foregroundStyle(theme.textSecondary)
                    }
                }

                Button {
                    Task { await coordinator.refreshAvailability() }
                } label: {
                    Label("检查 iCloud 状态", systemImage: "arrow.clockwise")
                }
                .disabled(coordinator.availability == .checking)

                Button {
                    Task { await coordinator.syncNow(modelContext: modelContext) }
                } label: {
                    Label("立即同步", systemImage: "arrow.triangle.2.circlepath.icloud")
                }
                .disabled(!canRunSync)

                HStack {
                    Label("同步结果", systemImage: "waveform.path.ecg")
                    Spacer()
                    Text(coordinator.runState.title)
                        .foregroundStyle(runStateColor)
                        .multilineTextAlignment(.trailing)
                }
            } footer: {
                Text("开启后，DevBar 会使用用户自己的 iCloud 私有数据库同步支持的数据。同步失败不会影响本地数据继续使用。")
            }

            Section {
                entityToggle("备忘录", systemImage: "note.text", entity: .memo)
                entityToggle("Markdown 文档", systemImage: "doc.plaintext", entity: .markdownDocument)
                entityToggle("SSH 服务器列表", systemImage: "terminal", entity: .terminalServer)
                chatRecordsToggle()
                entityToggle("Hermes 设置", systemImage: "bubble.left.and.text.bubble.right", entity: .hermesSettings)
                entityToggle("Home Assistant 设置", systemImage: "house", entity: .homeAssistantSettings)
                entityToggle("API Record 元数据（即将支持）", systemImage: "network", entity: .apiRecord, isAvailable: false)
                entityToggle("Web 历史（即将支持）", systemImage: "clock.arrow.circlepath", entity: .webHistoryRecord, isAvailable: false)
            } header: {
                Text("同步数据")
            } footer: {
                Text("当前同步备忘录、Markdown 文档、SSH 服务器列表、聊天记录，以及 Hermes 和 Home Assistant 的非敏感设置。API Key、Token 等凭据只保存在本机 Keychain。")
            }

            Section {
                Toggle(isOn: apiSensitiveBinding) {
                    Label("同步 API headers/body", systemImage: "lock.doc")
                }
                .disabled(true)
                Toggle(isOn: terminalSecretsBinding) {
                    Label("通过 iCloud Keychain 同步 SSH 密码/私钥", systemImage: "key")
                }
                .disabled(true)
                Toggle(isOn: providerCredentialsBinding) {
                    Label("通过 iCloud Keychain 同步 Provider 凭证", systemImage: "person.badge.key")
                }
                .disabled(true)
            } header: {
                Text("敏感数据")
            }
        }
        .scrollContentBackground(.hidden)
        .iosGeekScreenBackground(theme)
        .toolbarBackground(.hidden, for: .navigationBar)
        .navigationTitle("iCloud 同步")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard coordinator.settings.isEnabled,
                  coordinator.availability == .notChecked else { return }
            await coordinator.refreshAvailability()
        }
    }

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { coordinator.settings.isEnabled },
            set: { coordinator.setEnabled($0) }
        )
    }

    private var apiSensitiveBinding: Binding<Bool> {
        Binding(
            get: { coordinator.settings.syncAPISensitiveFields },
            set: { coordinator.setSyncAPISensitiveFields($0) }
        )
    }

    private var terminalSecretsBinding: Binding<Bool> {
        Binding(
            get: { coordinator.settings.syncTerminalSecrets },
            set: { coordinator.setSyncTerminalSecrets($0) }
        )
    }

    private var providerCredentialsBinding: Binding<Bool> {
        Binding(
            get: { coordinator.settings.syncProviderCredentials },
            set: { coordinator.setSyncProviderCredentials($0) }
        )
    }

    private var statusColor: Color {
        switch coordinator.availability {
        case .available:
            return .green
        case .checking, .notChecked:
            return theme.textSecondary
        case .unavailable:
            return .orange
        }
    }

    private var runStateColor: Color {
        switch coordinator.runState {
        case .completed:
            return .green
        case .failed:
            return .orange
        case .idle, .syncing:
            return theme.textSecondary
        }
    }

    private var canRunSync: Bool {
        guard coordinator.settings.isEnabled else { return false }
        if coordinator.runState == .syncing { return false }
        if coordinator.availability == .checking { return false }
        return true
    }

    private func entityToggle(
        _ title: String,
        systemImage: String,
        entity: ICloudSyncEntity,
        isAvailable: Bool = true
    ) -> some View {
        Toggle(isOn: Binding(
            get: { isAvailable && coordinator.settings.isSyncEnabled(for: entity) },
            set: { if isAvailable { coordinator.setEntity(entity, enabled: $0) } }
        )) {
            Label(title, systemImage: systemImage)
        }
        .disabled(!coordinator.settings.isEnabled || !isAvailable)
    }

    private func chatRecordsToggle() -> some View {
        Toggle(isOn: Binding(
            get: {
                coordinator.settings.isSyncEnabled(for: .chatConversation) &&
                    coordinator.settings.isSyncEnabled(for: .chatMessage)
            },
            set: { isEnabled in
                coordinator.setEntity(.chatConversation, enabled: isEnabled)
                coordinator.setEntity(.chatMessage, enabled: isEnabled)
            }
        )) {
            Label("聊天记录", systemImage: "bubble.left.and.bubble.right")
        }
        .disabled(!coordinator.settings.isEnabled)
    }
}

private struct IOSSettingsLinkLabel: View {
    let title: String
    let systemImage: String
    let summary: String

    @Environment(\.themeTokens) private var theme

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(theme.brandPrimary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .foregroundStyle(theme.textPrimary)

                Text(summary)
                    .font(.caption)
                    .foregroundStyle(theme.textSecondary)
                    .lineLimit(1)
            }
        }
    }
}

@MainActor
private struct IOSAppIconSettingsView: View {
    @Binding var currentOption: IOSAppIconOption

    @EnvironmentObject private var languageManager: IOSLanguageManager
    @EnvironmentObject private var themeManager: IOSThemeManager
    @Environment(\.themeTokens) private var theme
    @State private var selectedOption: IOSAppIconOption = .default
    @State private var applyingOption: IOSAppIconOption?
    @State private var errorMessage: String?

    private var supportsAlternateIcons: Bool {
        UIApplication.shared.supportsAlternateIcons
    }

    var body: some View {
        Form {
            Section {
                ForEach(IOSAppIconOption.allCases) { option in
                    Button {
                        setAppIcon(option)
                    } label: {
                        HStack(spacing: 14) {
                            Image(option.previewAssetName)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 58, height: 58)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .shadow(color: .black.opacity(theme.isGeek ? 0.28 : 0.12), radius: 8, y: 4)

                            Text(option.displayName)
                                .foregroundStyle(theme.textPrimary)

                            Spacer()

                            if applyingOption == option {
                                ProgressView()
                                    .controlSize(.small)
                            } else if selectedOption == option {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.title3.weight(.semibold))
                                    .foregroundStyle(theme.brandPrimary)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(!supportsAlternateIcons || selectedOption == option || applyingOption != nil)
                    .accessibilityIdentifier("ios.settings.appIcon.\(option.id)")
                }
            } footer: {
                if supportsAlternateIcons {
                    Text("ios_settings_app_icon_footer")
                } else {
                    Text("ios_settings_app_icon_unsupported")
                }
            }

            if let errorMessage {
                Section {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                        .font(.subheadline)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .iosGeekScreenBackground(theme)
        .toolbarBackground(.hidden, for: .navigationBar)
        .navigationTitle("ios_settings_app_icon_title")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("ios.settings.appIcon.screen")
        .onAppear(perform: refreshCurrentIcon)
    }

    private func refreshCurrentIcon() {
        let option = IOSAppIconController.shared.preferredOption
        selectedOption = option
        currentOption = option
    }

    private func setAppIcon(_ option: IOSAppIconOption) {
        let traceId = UUID().uuidString
        DiagnosticLogger.shared.record(
            level: .info,
            category: "ios.appIcon",
            name: "ios_app_icon_selection_tapped",
            message: "iOS app icon option tapped",
            traceId: traceId,
            tags: ["app-icon"],
            details: [
                "optionId": option.id,
                "optionDisplayName": option.displayName,
                "selectedOptionId": selectedOption.id,
                "currentOptionId": currentOption.id,
                "requestedAlternateIconName": option.alternateIconName ?? "<default>",
                "systemCurrentAlternateIconName": UIApplication.shared.alternateIconName ?? "<default>",
                "supportsAlternateIcons": String(supportsAlternateIcons),
            ]
        )

        guard supportsAlternateIcons else {
            DiagnosticLogger.shared.record(
                level: .warning,
                category: "ios.appIcon",
                name: "ios_app_icon_selection_ignored",
                message: "iOS app icon option ignored because alternate icons are unsupported",
                traceId: traceId,
                tags: ["app-icon"],
                details: [
                    "optionId": option.id,
                    "reason": "unsupported",
                ]
            )
            return
        }

        guard applyingOption == nil else {
            DiagnosticLogger.shared.record(
                level: .info,
                category: "ios.appIcon",
                name: "ios_app_icon_selection_ignored",
                message: "iOS app icon option ignored because another icon change is in progress",
                traceId: traceId,
                tags: ["app-icon"],
                details: [
                    "optionId": option.id,
                    "reason": "already_applying",
                    "applyingOptionId": applyingOption?.id ?? "<none>",
                    "systemCurrentAlternateIconName": UIApplication.shared.alternateIconName ?? "<default>",
                ]
            )
            return
        }

        guard selectedOption != option else {
            DiagnosticLogger.shared.record(
                level: .info,
                category: "ios.appIcon",
                name: "ios_app_icon_selection_ignored",
                message: "iOS app icon option ignored because it is already selected",
                traceId: traceId,
                tags: ["app-icon"],
                details: [
                    "optionId": option.id,
                    "reason": "already_selected",
                    "systemCurrentAlternateIconName": UIApplication.shared.alternateIconName ?? "<default>",
                ]
            )
            return
        }

        applyingOption = option
        IOSAppIconController.shared.apply(option, traceId: traceId) { error in
            applyingOption = nil
            if let error {
                errorMessage = error.localizedDescription
                refreshCurrentIcon()
                return
            }

            errorMessage = nil
            selectedOption = option
            currentOption = option
        }
    }

    private func localized(_ key: String.LocalizationValue) -> String {
        String(localized: key, locale: languageManager.currentLocale)
    }
}

@MainActor
private struct IOSDeviceWidgetSettingsView: View {
    @EnvironmentObject private var appViewModel: IOSAppViewModel
    @EnvironmentObject private var languageManager: IOSLanguageManager
    @Environment(\.themeTokens) private var theme
    @State private var selectedMacThemeAvatarItem: PhotosPickerItem?
    @State private var macThemeAvatarErrorMessage: String?

    var body: some View {
        Form {
            Section {
                IOSIconTextFieldRow(
                    title: localized("ios_settings_relay_device_name"),
                    systemImage: "iphone",
                    text: $appViewModel.relayDeviceName,
                    accessibilityIdentifier: "ios.settings.relayDeviceName"
                )

                IOSIconTextFieldRow(
                    title: localized("ios_settings_user_name"),
                    systemImage: "person.text.rectangle",
                    text: $appViewModel.macThemeWidgetUserName,
                    accessibilityIdentifier: "ios.settings.macThemeWidgetUserName"
                )
            } footer: {
                Text("ios_settings_device_widget_footer")
            }

            Section {
                PhotosPicker(selection: $selectedMacThemeAvatarItem, matching: .images) {
                    Label("ios_settings_select_avatar", systemImage: "photo.on.rectangle")
                }
                .accessibilityIdentifier("ios.settings.macThemeWidgetAvatar")

                if appViewModel.macThemeWidgetAvatarFileName != nil {
                    Button(role: .destructive) {
                        appViewModel.clearMacThemeWidgetAvatar()
                    } label: {
                        Label("ios_settings_remove_avatar", systemImage: "trash")
                    }
                }

                if let macThemeAvatarErrorMessage {
                    Text(macThemeAvatarErrorMessage)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            Section("ios_settings_widget_section") {
                Label("ios_settings_widget_intro", systemImage: "square.grid.2x2")
                    .font(.subheadline)
                    .foregroundStyle(theme.textSecondary)
            }
        }
        .scrollContentBackground(.hidden)
        .iosGeekScreenBackground(theme)
        .toolbarBackground(.hidden, for: .navigationBar)
        .navigationTitle("ios_settings_device_widget_section")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("ios.settings.deviceWidget.screen")
        .onChange(of: selectedMacThemeAvatarItem) { _, item in
            guard let item else { return }
            Task {
                defer { selectedMacThemeAvatarItem = nil }
                guard let data = try? await item.loadTransferable(type: Data.self),
                      let image = UIImage(data: data),
                      let avatarData = Self.macThemeWidgetAvatarData(from: image) else {
                    macThemeAvatarErrorMessage = localized("ios_settings_avatar_processing_failed")
                    return
                }
                do {
                    try appViewModel.saveMacThemeWidgetAvatarData(avatarData)
                    macThemeAvatarErrorMessage = nil
                } catch {
                    macThemeAvatarErrorMessage = localized("ios_settings_avatar_save_failed")
                }
            }
        }
    }

    private func localized(_ key: String.LocalizationValue) -> String {
        String(localized: key, locale: languageManager.currentLocale)
    }

    private static func macThemeWidgetAvatarData(from image: UIImage) -> Data? {
        let sideLength = min(image.size.width, image.size.height)
        guard sideLength > 0 else { return nil }

        let cropRect = CGRect(
            x: (image.size.width - sideLength) / 2,
            y: (image.size.height - sideLength) / 2,
            width: sideLength,
            height: sideLength
        )
        let outputSize = CGSize(width: 256, height: 256)
        let renderer = UIGraphicsImageRenderer(size: outputSize)
        let resizedImage = renderer.image { _ in
            image.draw(
                in: CGRect(
                    x: -cropRect.minX * outputSize.width / sideLength,
                    y: -cropRect.minY * outputSize.height / sideLength,
                    width: image.size.width * outputSize.width / sideLength,
                    height: image.size.height * outputSize.height / sideLength
                )
            )
        }
        return resizedImage.jpegData(compressionQuality: 0.82)
    }
}

private struct IOSPushSettingsView: View {
    @EnvironmentObject private var appViewModel: IOSAppViewModel
    @EnvironmentObject private var languageManager: IOSLanguageManager
    @Environment(\.themeTokens) private var theme
    @StateObject private var openKeyViewModel = IOSPushOpenKeyViewModel()
    @State private var pushKeySheet: IOSPushKeySheetDestination?
    @State private var pendingRevokeKey: PushOpenKeySummary?
    @State private var hasAPNsToken = false

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $appViewModel.pushNotificationPreferences.pushEnabled) {
                    Label("ios_settings_push_allow_offline", systemImage: "bell.badge")
                }

                if DevBarCoreConstants.Features.agentWatcherEnabled {
                    Toggle(isOn: $appViewModel.pushNotificationPreferences.agentWatcherEnabled) {
                        Label("ios_settings_agent_watcher_notifications", systemImage: "terminal")
                    }
                }

                Toggle(isOn: $appViewModel.pushNotificationPreferences.summaryEnabled) {
                    Label("ios_settings_high_frequency_summary", systemImage: "list.bullet.rectangle")
                }

                IOSIconTextFieldRow(
                    title: localized("ios_settings_https_icon_url"),
                    systemImage: "link",
                    text: pushIconURLBinding,
                    keyboardType: .URL,
                    textInputAutocapitalization: .never,
                    accessibilityIdentifier: nil
                )
                .disabled(!appViewModel.pushNotificationPreferences.pushEnabled)
                .opacity(appViewModel.pushNotificationPreferences.pushEnabled ? 1 : 0.55)
            } footer: {
                Text("ios_settings_push_footer")
            }

            Section {
                Button {
                    pushKeySheet = .create
                } label: {
                    Label("ios_settings_push_key_create", systemImage: "key.badge.plus")
                }
                .disabled(!canCreatePushKey || openKeyViewModel.isCreating)

                if openKeyViewModel.isLoading && openKeyViewModel.keys.isEmpty {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                } else if openKeyViewModel.keys.isEmpty {
                    Text("ios_settings_push_key_empty")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(openKeyViewModel.keys) { key in
                        IOSPushOpenKeyRow(
                            key: key,
                            isRevoking: openKeyViewModel.revokingIDs.contains(key.id)
                        ) {
                            pendingRevokeKey = key
                        }
                    }
                }

                if !canCreatePushKey {
                    Label("ios_settings_push_key_device_not_ready", systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("ios_settings_push_key_section")
            } footer: {
                Text("ios_settings_push_key_footer")
            }
        }
        .scrollContentBackground(.hidden)
        .iosGeekScreenBackground(theme)
        .toolbarBackground(.hidden, for: .navigationBar)
        .navigationTitle("ios_settings_push_notifications_section")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("ios.settings.push.screen")
        .task(id: relayDeviceToken) {
            hasAPNsToken = IOSPushNotificationCoordinator.shared.debugSnapshot().hasCurrentProcessAPNsToken
            await openKeyViewModel.load(deviceToken: relayDeviceToken)
        }
        .onReceive(NotificationCenter.default.publisher(for: .iosAPNsTokenChanged)) { _ in
            hasAPNsToken = IOSPushNotificationCoordinator.shared.debugSnapshot().hasCurrentProcessAPNsToken
        }
        .sheet(item: $pushKeySheet, onDismiss: openKeyViewModel.clearCreatedKey) { destination in
            switch destination {
            case .create:
                IOSPushOpenKeyCreateSheet(
                    viewModel: openKeyViewModel,
                    deviceToken: relayDeviceToken,
                    destination: $pushKeySheet
                )
            case .created(let key):
                IOSPushOpenKeyCreatedSheet(createdKey: key)
            }
        }
        .confirmationDialog(
            localized("ios_settings_push_key_revoke_title"),
            isPresented: Binding(
                get: { pendingRevokeKey != nil },
                set: { if !$0 { pendingRevokeKey = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingRevokeKey
        ) { key in
            Button(localized("ios_settings_push_key_revoke"), role: .destructive) {
                pendingRevokeKey = nil
                Task {
                    await openKeyViewModel.revoke(key, deviceToken: relayDeviceToken)
                }
            }
            Button(localized("cancel"), role: .cancel) {
                pendingRevokeKey = nil
            }
        } message: { key in
            Text("\(key.name) · \(key.keyPrefix)")
        }
        .alert(
            localized("ios_settings_push_key_error_title"),
            isPresented: Binding(
                get: { pushKeySheet == nil && openKeyViewModel.errorMessage != nil },
                set: { if !$0 { openKeyViewModel.errorMessage = nil } }
            )
        ) {
            Button(localized("ios_settings_push_key_acknowledge"), role: .cancel) {
                openKeyViewModel.errorMessage = nil
            }
        } message: {
            Text(openKeyViewModel.errorMessage ?? "")
        }
    }

    private var relayDeviceToken: String? {
        appViewModel.deviceRelayManager.deviceToken
    }

    private var canCreatePushKey: Bool {
        relayDeviceToken?.isEmpty == false && hasAPNsToken
    }

    private var pushIconURLBinding: Binding<String> {
        Binding {
            appViewModel.pushNotificationPreferences.iconUrl ?? ""
        } set: { value in
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            appViewModel.pushNotificationPreferences.iconUrl = trimmed.isEmpty ? nil : trimmed
        }
    }

    private func localized(_ key: String.LocalizationValue) -> String {
        String(localized: key, locale: languageManager.currentLocale)
    }
}

private enum IOSPushKeySheetDestination: Identifiable {
    case create
    case created(PushOpenKeyCreated)

    var id: String {
        switch self {
        case .create: "create"
        case .created(let key): "created-\(key.id)"
        }
    }
}

private struct IOSPushOpenKeyRow: View {
    let key: PushOpenKeySummary
    let isRevoking: Bool
    let revoke: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "key.fill")
                .foregroundStyle(.tint)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 5) {
                Text(key.name)
                    .font(.body.weight(.medium))
                Text(key.keyPrefix)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                Text(timestampSummary)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 8)

            if isRevoking {
                ProgressView()
            } else {
                Button(role: .destructive, action: revoke) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("ios_settings_push_key_revoke")
            }
        }
        .padding(.vertical, 3)
    }

    private var timestampSummary: String {
        let created = Self.displayTimestamp(key.createdAt)
        guard let lastUsedAt = key.lastUsedAt else {
            return String(format: String(localized: "ios_settings_push_key_created_format"), created)
        }
        return String(
            format: String(localized: "ios_settings_push_key_used_format"),
            Self.displayTimestamp(lastUsedAt)
        )
    }

    private static func displayTimestamp(_ value: String) -> String {
        String(value.replacingOccurrences(of: "T", with: " ").prefix(16))
    }
}

private struct IOSPushOpenKeyCreateSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: IOSPushOpenKeyViewModel
    let deviceToken: String?
    @Binding var destination: IOSPushKeySheetDestination?
    @State private var name = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("ios_settings_push_key_name_placeholder", text: $name)
                        .textInputAutocapitalization(.sentences)
                        .autocorrectionDisabled()
                } footer: {
                    Text("ios_settings_push_key_name_footer")
                }
            }
            .navigationTitle("ios_settings_push_key_create")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task {
                            await viewModel.create(name: name, deviceToken: deviceToken)
                            if let createdKey = viewModel.createdKey {
                                destination = .created(createdKey)
                            }
                        }
                    } label: {
                        if viewModel.isCreating {
                            ProgressView()
                        } else {
                            Text("ios_settings_push_key_create_action")
                        }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isCreating)
                }
            }
            .interactiveDismissDisabled(viewModel.isCreating)
            .alert(
                "ios_settings_push_key_error_title",
                isPresented: Binding(
                    get: { viewModel.errorMessage != nil },
                    set: { if !$0 { viewModel.errorMessage = nil } }
                )
            ) {
                Button("ios_settings_push_key_acknowledge", role: .cancel) {
                    viewModel.errorMessage = nil
                }
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
        }
    }
}

private struct IOSPushOpenKeyCreatedSheet: View {
    @Environment(\.dismiss) private var dismiss
    let createdKey: PushOpenKeyCreated
    @State private var didCopy = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(createdKey.key)
                        .font(.footnote.monospaced())
                        .textSelection(.enabled)
                } header: {
                    Text(createdKey.name)
                } footer: {
                    Label("ios_settings_push_key_once_warning", systemImage: "exclamationmark.shield")
                }

                Section {
                    Button {
                        UIPasteboard.general.string = createdKey.key
                        didCopy = true
                    } label: {
                        Label(
                            didCopy ? "ios_settings_push_key_copied" : "ios_settings_push_key_copy",
                            systemImage: didCopy ? "checkmark" : "doc.on.doc"
                        )
                    }

                    ShareLink(item: createdKey.key) {
                        Label("ios_settings_push_key_share", systemImage: "square.and.arrow.up")
                    }
                }
            }
            .navigationTitle("ios_settings_push_key_created")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("ios_settings_push_key_done") { dismiss() }
                }
            }
        }
    }
}

private struct IOSHermesSettingsView: View {
    @EnvironmentObject private var appViewModel: IOSAppViewModel
    @Environment(\.themeTokens) private var theme
    @State private var hermesModel = ""
    @State private var apiBaseURL = ""
    @State private var apiKey = ""
    @State private var isStreamingEnabled = true
    @State private var discoveredModels: [HermesModel] = []
    @State private var discoveredCapabilities: HermesAPIServerCapabilities?
    @State private var isRefreshingHermesMetadata = false
    @State private var toast: IOSStatusToastKind?

    private let hermesClient = HermesAPIClient()

    var body: some View {
        Form {
            Section {
                IOSIconTextFieldRow(
                    title: localized("ios_settings_hermes_base_url"),
                    systemImage: "link",
                    text: $apiBaseURL,
                    keyboardType: .URL,
                    textInputAutocapitalization: .never,
                    accessibilityIdentifier: "ios.settings.hermes.baseURL"
                )

                HStack(spacing: 12) {
                    Image(systemName: "key")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(theme.brandPrimary)
                        .frame(width: 24)

                    SecureField(localized("ios_settings_hermes_api_key"), text: $apiKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.system(.body, design: .monospaced))
                        .accessibilityIdentifier("ios.settings.hermes.apiKey")
                }

                Button {
                    Task { await refreshHermesMetadata() }
                } label: {
                    Label(isRefreshingHermesMetadata ? "Checking..." : "Check", systemImage: "arrow.clockwise")
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .disabled(isRefreshingHermesMetadata || apiBaseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                if let discoveredCapabilities {
                    capabilityStatus(discoveredCapabilities)
                }

                if !discoveredModels.isEmpty {
                    Picker(selection: $hermesModel) {
                        ForEach(discoveredModels) { model in
                            Text(model.id).tag(model.id)
                        }
                    } label: {
                        Label("Model", systemImage: "cpu")
                    }
                    .accessibilityIdentifier("ios.settings.hermes.modelPicker")
                }

                Toggle(isOn: $isStreamingEnabled) {
                    Label("ios_settings_hermes_streaming", systemImage: "dot.radiowaves.left.and.right")
                }
                .accessibilityIdentifier("ios.settings.hermes.streaming")
            } header: {
                Text("Hermes")
            } footer: {
                Text("ios_settings_hermes_footer")
            }

            Section {
                HStack(spacing: 10) {
                    Button {
                        save()
                    } label: {
                        HStack(spacing: 7) {
                            Image(systemName: "checkmark")
                                .font(.body.weight(.bold))
                            Text("Save")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)

                    Button(role: .destructive) {
                        appViewModel.clearHermesSettings()
                        loadCurrentSettings()
                        toast = nil
                    } label: {
                        Label("Clear", systemImage: "trash")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .iosGeekScreenBackground(theme)
        .toolbarBackground(.hidden, for: .navigationBar)
        .navigationTitle("ios_settings_hermes_title")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("ios.settings.hermes.screen")
        .overlay {
            if let toast {
                IOSStatusToast(toastTitle(for: toast), kind: toast, theme: theme)
                    .transition(.scale(scale: 0.94).combined(with: .opacity))
                    .allowsHitTesting(false)
            }
        }
        .animation(.easeOut(duration: 0.22), value: toast)
        .onAppear {
            loadCurrentSettings()
        }
    }

    private func loadCurrentSettings() {
        hermesModel = appViewModel.hermesSettings.hermesModel
        apiBaseURL = appViewModel.hermesSettings.apiBaseURL
        apiKey = appViewModel.hermesAPIKey
        isStreamingEnabled = appViewModel.hermesSettings.isStreamingEnabled
    }

    private func refreshHermesMetadata() async {
        let trimmedBaseURL = apiBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedAPIKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedBaseURL.isEmpty, !trimmedAPIKey.isEmpty else { return }

        isRefreshingHermesMetadata = true
        defer { isRefreshingHermesMetadata = false }

        do {
            async let capabilities = hermesClient.fetchCapabilities(baseURL: trimmedBaseURL, apiKey: trimmedAPIKey)
            async let models = hermesClient.fetchModels(baseURL: trimmedBaseURL, apiKey: trimmedAPIKey)
            let resolvedCapabilities = try await capabilities
            let resolvedModels = try await models
            discoveredCapabilities = resolvedCapabilities
            discoveredModels = resolvedModels
            let selectedModel = hermesModel.trimmingCharacters(in: .whitespacesAndNewlines)
            if !resolvedModels.contains(where: { $0.id == selectedModel }) {
                hermesModel = resolvedModels.first?.id ?? ""
            }
        } catch {
            showToast(.failure)
        }
    }

    private func save() {
        do {
            try appViewModel.saveHermesSettings(
                apiBaseURL: apiBaseURL,
                apiKey: apiKey,
                hermesModel: hermesModel,
                hermesProvider: "",
                isStreamingEnabled: isStreamingEnabled
            )
            loadCurrentSettings()
            showToast(.success)
        } catch {
            showToast(.failure)
        }
    }

    private func showToast(_ toast: IOSStatusToastKind) {
        withAnimation {
            self.toast = toast
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.25) {
            withAnimation {
                if self.toast == toast {
                    self.toast = nil
                }
            }
        }
    }

    private func toastTitle(for toast: IOSStatusToastKind) -> String {
        switch toast {
        case .success:
            return "Saved"
        case .failure:
            return "Failed"
        }
    }

    private func capabilityStatus(_ capabilities: HermesAPIServerCapabilities) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundStyle(theme.success)
                Text("Connected")
                    .font(.subheadline.weight(.semibold))
                Spacer(minLength: 0)
                if let model = capabilities.model?.trimmingCharacters(in: .whitespacesAndNewlines), !model.isEmpty {
                    Text(model)
                        .font(.caption.monospaced())
                        .foregroundStyle(theme.textTertiary)
                        .lineLimit(1)
                }
            }

            HStack(spacing: 6) {
                capabilityChip("Responses", isEnabled: capabilities.features.responsesAPI)
                capabilityChip("Chat", isEnabled: capabilities.features.chatCompletions)
                if capabilities.features.runEventsSSE {
                    capabilityChip("SSE", isEnabled: true)
                }
                if capabilities.features.runStop {
                    capabilityChip("Stop", isEnabled: true)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func capabilityChip(_ title: String, isEnabled: Bool) -> some View {
        Text(title)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(isEnabled ? theme.success : theme.textTertiary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                (isEnabled ? theme.success.opacity(0.14) : theme.surfaceSecondary.opacity(0.7)),
                in: Capsule()
            )
    }

    private func localized(_ key: String.LocalizationValue) -> String {
        String(localized: key)
    }
}

private struct IOSLiveMessageSettingsView: View {
    @EnvironmentObject private var appViewModel: IOSAppViewModel
    @EnvironmentObject private var languageManager: IOSLanguageManager
    @Environment(\.themeTokens) private var theme

    var body: some View {
        Form {
            Section {
                LabeledContent {
                    Text(appViewModel.devBarLiveMessageStatus.title)
                        .foregroundStyle(devBarLiveMessageStatusColor)
                } label: {
                    Label("ios_settings_live_message_section", systemImage: "quote.bubble")
                }

                Text(appViewModel.devBarLiveMessageStatus.detail)
                    .font(.caption)
                    .foregroundStyle(theme.textSecondary)
            }

            Section {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "text.bubble")
                        .foregroundStyle(theme.brandPrimary)
                        .frame(width: 24)

                    TextField(localized("ios_settings_live_message_placeholder"), text: $appViewModel.devBarLiveMessageDraft, axis: .vertical)
                        .lineLimit(1...3)
                        .textInputAutocapitalization(.sentences)
                        .autocorrectionDisabled(false)
                        .accessibilityIdentifier("ios.settings.liveMessage.text")
                }

                HStack(spacing: 12) {
                    Button {
                        Task { await appViewModel.enableDevBarLiveMessageIsland(message: appViewModel.devBarLiveMessageDraft) }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "sparkles")
                                .font(.body.weight(.semibold))
                            Text("ios_settings_live_message_start")
                        }
                        .frame(minWidth: 72)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canEnableDevBarLiveMessage)

                    Button(role: .destructive) {
                        Task { await appViewModel.disableDevBarLiveMessageIsland() }
                    } label: {
                        Label("ios_settings_live_message_end", systemImage: "xmark.circle")
                    }
                    .buttonStyle(.bordered)
                    .disabled(!canDisableDevBarLiveMessage)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .iosGeekScreenBackground(theme)
        .toolbarBackground(.hidden, for: .navigationBar)
        .navigationTitle("ios_settings_live_message_section")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("ios.settings.liveMessage.screen")
    }

    private var canEnableDevBarLiveMessage: Bool {
        let hasMessage = !appViewModel.devBarLiveMessageDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        switch appViewModel.devBarLiveMessageStatus {
        case .notReady, .ready, .active, .failed:
            return hasMessage
        case .enabling:
            return false
        }
    }

    private var canDisableDevBarLiveMessage: Bool {
        if case .active = appViewModel.devBarLiveMessageStatus {
            return true
        }
        return false
    }

    private var devBarLiveMessageStatusColor: Color {
        switch appViewModel.devBarLiveMessageStatus {
        case .active:
            .green
        case .failed:
            .orange
        case .enabling:
            theme.textSecondary
        case .ready:
            theme.textPrimary
        case .notReady:
            theme.textTertiary
        }
    }

    private func localized(_ key: String.LocalizationValue) -> String {
        String(localized: key, locale: languageManager.currentLocale)
    }
}

private struct IOSHomeScreenShortcutSettingsView: View {
    @EnvironmentObject private var appViewModel: IOSAppViewModel
    @Environment(\.themeTokens) private var theme

    var body: some View {
        Form {
            Section {
                ForEach(appViewModel.availableHomeScreenShortcutActions, id: \.self) { action in
                    Toggle(isOn: homeScreenShortcutBinding(for: action)) {
                        Label {
                            Text(LocalizedStringKey(IOSHomeScreenShortcutController.titleKey(for: action)))
                        } icon: {
                            Image(systemName: homeScreenShortcutIcon(for: action))
                        }
                    }
                    .disabled(!appViewModel.canEnableHomeScreenShortcutAction(action))
                }
            } footer: {
                Text("ios_settings_home_shortcuts_footer")
            }
        }
        .scrollContentBackground(.hidden)
        .iosGeekScreenBackground(theme)
        .toolbarBackground(.hidden, for: .navigationBar)
        .navigationTitle("ios_settings_home_shortcuts_section")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("ios.settings.homeShortcuts.screen")
    }

    private func homeScreenShortcutBinding(for action: DeviceRelayHomeScreenShortcutAction) -> Binding<Bool> {
        Binding {
            appViewModel.selectedHomeScreenShortcutActions.contains(action)
        } set: { enabled in
            appViewModel.setHomeScreenShortcutAction(action, enabled: enabled)
        }
    }

    private func homeScreenShortcutIcon(for action: DeviceRelayHomeScreenShortcutAction) -> String {
        switch action {
        case .memo: return "note.text"
        case .qrScan: return "qrcode.viewfinder"
        case .ocr: return "text.viewfinder"
        case .apiClient: return "globe"
        case .lockMac: return "lock.fill"
        case .wakeMacDisplay: return "sun.max.fill"
        case .sleepMacDisplay: return "display"
        }
    }
}

private struct IOSLiveActivitySettingsView: View {
    @EnvironmentObject private var appViewModel: IOSAppViewModel
    @Environment(\.themeTokens) private var theme

    private static let liveActivityTimeLocale = Locale(identifier: "en_GB")

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $appViewModel.liveActivitySettings.isEnabled) {
                    Label("ios_settings_live_activity_enabled", systemImage: "livephoto")
                }
                    .accessibilityIdentifier("ios.settings.liveActivity.enabled")

                DatePicker(
                    selection: liveActivityStartBinding,
                    displayedComponents: .hourAndMinute
                ) {
                    Label("ios_settings_live_activity_start", systemImage: "sunrise")
                }
                .environment(\.locale, Self.liveActivityTimeLocale)
                .accessibilityIdentifier("ios.settings.liveActivity.start")

                DatePicker(
                    selection: liveActivityEndBinding,
                    displayedComponents: .hourAndMinute
                ) {
                    Label("ios_settings_live_activity_end", systemImage: "sunset")
                }
                .environment(\.locale, Self.liveActivityTimeLocale)
                .accessibilityIdentifier("ios.settings.liveActivity.end")

                if !appViewModel.liveActivitySettings.isValidTimeRange {
                    Text("ios_settings_live_activity_invalid_range")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .accessibilityIdentifier("ios.settings.liveActivity.hint")
                }
            }
        }
        .scrollContentBackground(.hidden)
        .iosGeekScreenBackground(theme)
        .toolbarBackground(.hidden, for: .navigationBar)
        .navigationTitle("ios_settings_live_activity_title")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("ios.settings.liveActivity.screen")
    }

    private var liveActivityStartBinding: Binding<Date> {
        Binding {
            date(hour: appViewModel.liveActivitySettings.startHour, minute: appViewModel.liveActivitySettings.startMinute)
        } set: { newValue in
            let components = Calendar.current.dateComponents([.hour, .minute], from: newValue)
            appViewModel.liveActivitySettings.startHour = components.hour ?? 9
            appViewModel.liveActivitySettings.startMinute = components.minute ?? 0
        }
    }

    private var liveActivityEndBinding: Binding<Date> {
        Binding {
            date(hour: appViewModel.liveActivitySettings.endHour, minute: appViewModel.liveActivitySettings.endMinute)
        } set: { newValue in
            let components = Calendar.current.dateComponents([.hour, .minute], from: newValue)
            appViewModel.liveActivitySettings.endHour = components.hour ?? 18
            appViewModel.liveActivitySettings.endMinute = components.minute ?? 0
        }
    }

    private func date(hour: Int, minute: Int) -> Date {
        var components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        components.hour = hour
        components.minute = minute
        components.second = 0
        return Calendar.current.date(from: components) ?? Date()
    }
}

private struct IOSGreetingSettingsView: View {
    @EnvironmentObject private var themeManager: IOSThemeManager
    @Environment(\.themeTokens) private var theme

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Label("ios_settings_greeting_section", systemImage: "quote.opening")
                        .foregroundStyle(theme.textPrimary)

                    TextEditor(text: $themeManager.developerGreeting)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 140)
                        .scrollContentBackground(.hidden)
                        .padding(8)
                        .background(theme.surfaceSecondary.opacity(theme.isGeek ? 0.42 : 1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(theme.borderSubtle, lineWidth: 1)
                        )
                }

                Button {
                    themeManager.developerGreeting = IOSThemeManager.defaultGreeting
                } label: {
                    Label("ios_settings_greeting_reset", systemImage: "arrow.counterclockwise")
                }
                .foregroundStyle(theme.textTertiary)
            }
        }
        .scrollContentBackground(.hidden)
        .iosGeekScreenBackground(theme)
        .toolbarBackground(.hidden, for: .navigationBar)
        .navigationTitle("ios_settings_greeting_section")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("ios.settings.greeting.screen")
    }
}

private struct IOSIconTextFieldRow: View {
    let title: String
    let systemImage: String
    @Binding var text: String
    var keyboardType: UIKeyboardType = .default
    var textInputAutocapitalization: TextInputAutocapitalization? = .words
    var accessibilityIdentifier: String?

    @Environment(\.themeTokens) private var theme

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(theme.brandPrimary)
                .frame(width: 24)

            TextField(title, text: $text)
                .keyboardType(keyboardType)
                .textInputAutocapitalization(textInputAutocapitalization)
                .autocorrectionDisabled()
                .accessibilityIdentifier(accessibilityIdentifier ?? "")
        }
    }
}

private struct IOSSettingsDebugInfoItem: Identifiable {
    let title: String
    let value: String

    var id: String { title }
}

private struct IOSSettingsDebugInfoSheet: View {
    let items: [IOSSettingsDebugInfoItem]
    let copiedItemID: String?
    let onCopy: (IOSSettingsDebugInfoItem) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.themeTokens) private var theme

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(items) { item in
                        Button {
                            onCopy(item)
                        } label: {
                            HStack(alignment: .center, spacing: 12) {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(item.title)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(theme.textSecondary)

                                    Text(item.value)
                                        .font(.caption2.monospaced())
                                        .foregroundStyle(theme.textPrimary)
                                        .lineLimit(4)
                                        .textSelection(.enabled)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)

                                Image(systemName: copiedItemID == item.id ? "checkmark.circle.fill" : "doc.on.doc")
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(copiedItemID == item.id ? .green : theme.textTertiary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                } footer: {
                    Text("ios_settings_debug_copy_hint")
                }
            }
            .navigationTitle("ios_settings_debug_title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("ios_common_done") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
