import DevBarCore
import PhotosUI
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
                    Text("ios_settings_theme_dark").tag(IOSThemeMode.dark)
                    Text("ios_settings_theme_geek").tag(IOSThemeMode.geek)
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
            }

            Section("ios_settings_ai_quota_section") {
                Picker(selection: $appViewModel.refreshInterval) {
                    ForEach(intervals, id: \.1) { label, value in
                        Text(label).tag(value)
                    }
                } label: {
                    Label("ios_settings_auto_refresh_interval", systemImage: "arrow.clockwise")
                }
                .accessibilityIdentifier("ios.settings.refreshInterval")
            }

            Section("ios_settings_device_system_section") {
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
            IOSSettingsDebugInfoItem(title: "APNs Token", value: pushDebug.apnsToken ?? localized("ios_settings_debug_not_registered")),
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
        }
        .scrollContentBackground(.hidden)
        .iosGeekScreenBackground(theme)
        .toolbarBackground(.hidden, for: .navigationBar)
        .navigationTitle("ios_settings_push_notifications_section")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("ios.settings.push.screen")
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
