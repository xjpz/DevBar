import DevBarCore
import PhotosUI
import SwiftUI
import UIKit

struct IOSSettingsView: View {
    @EnvironmentObject private var appViewModel: IOSAppViewModel
    @EnvironmentObject private var languageManager: IOSLanguageManager
    @EnvironmentObject private var themeManager: IOSThemeManager
    @Environment(\.themeTokens) private var theme
    @State private var isGreetingEditorExpanded = false
    @State private var selectedMacThemeAvatarItem: PhotosPickerItem?
    @State private var macThemeAvatarErrorMessage: String?

    private let intervals: [(LocalizedStringKey, TimeInterval)] = [
        ("ios_settings_interval_3m", 180),
        ("ios_settings_interval_5m", 300),
        ("ios_settings_interval_10m", 600),
        ("ios_settings_interval_15m", 900),
        ("ios_settings_interval_30m", 1800),
        ("ios_settings_interval_60m", 3600),
        ("ios_settings_interval_never", 0),
    ]
    private static let liveActivityTimeLocale = Locale(identifier: "en_GB")

    var body: some View {
        Form {
            Section("ios_settings_appearance_section") {
                Picker("language", selection: $languageManager.selectedLanguage) {
                    Text("follow_system").tag(IOSAppLanguage.system)
                    Text("ios_settings_language_zh_hans").tag(IOSAppLanguage.zhHans)
                    Text("ios_settings_language_en").tag(IOSAppLanguage.en)
                }
                .accessibilityIdentifier("ios.settings.language")

                Picker("ios_settings_theme", selection: $themeManager.selectedMode) {
                    Text("ios_settings_theme_system").tag(IOSThemeMode.system)
                    Text("ios_settings_theme_light").tag(IOSThemeMode.light)
                    Text("ios_settings_theme_dark").tag(IOSThemeMode.dark)
                    Text("ios_settings_theme_geek").tag(IOSThemeMode.geek)
                }
                .accessibilityIdentifier("ios.settings.theme")

                Picker("ios_settings_font", selection: $themeManager.selectedFont) {
                    ForEach(IOSAppFont.allCases) { font in
                        Text(font.titleKey).tag(font)
                    }
                }
                .accessibilityIdentifier("ios.settings.font")

                Picker(String(localized: "ios_settings_time_format", defaultValue: "Time Format"), selection: $themeManager.timeFormat) {
                    ForEach(IOSTimeFormat.allCases) { format in
                        Text(format.displayName).tag(format)
                    }
                }
                .accessibilityIdentifier("ios.settings.timeFormat")
            }

            Section("ios_settings_greeting_section") {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isGreetingEditorExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(greetingPreviewText)
                                .font(.subheadline)
                                .foregroundStyle(theme.textPrimary)
                                .lineLimit(isGreetingEditorExpanded ? 2 : 1)

                            Text(LocalizedStringKey(isGreetingEditorExpanded ? "ios_settings_greeting_tap_to_collapse" : "ios_settings_greeting_tap_to_edit"))
                                .font(.caption)
                                .foregroundStyle(theme.textSecondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        Image(systemName: isGreetingEditorExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(theme.textSecondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if isGreetingEditorExpanded {
                    TextEditor(text: $themeManager.developerGreeting)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 76)
                        .scrollContentBackground(.hidden)
                        .padding(8)
                        .background(theme.surfaceSecondary.opacity(theme.isGeek ? 0.42 : 1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(theme.borderSubtle, lineWidth: 1)
                        )

                    Button("ios_settings_greeting_reset") {
                        themeManager.developerGreeting = IOSThemeManager.defaultGreeting
                    }
                    .font(.caption)
                    .foregroundStyle(theme.textTertiary)
                }
            }

            Section("ios_settings_refresh_section") {
                Picker("ios_settings_auto_refresh_interval", selection: $appViewModel.refreshInterval) {
                    ForEach(intervals, id: \.1) { label, value in
                        Text(label).tag(value)
                    }
                }
                .accessibilityIdentifier("ios.settings.refreshInterval")
            }

            Section {
                TextField("iPhone 名称", text: $appViewModel.relayDeviceName)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("ios.settings.relayDeviceName")

                Text("用于 Mac 上显示连接的 iPhone 名称。")
                    .font(.caption)
                    .foregroundStyle(theme.textSecondary)

                TextField("用户名称", text: $appViewModel.macThemeWidgetUserName)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("ios.settings.macThemeWidgetUserName")

                Text("用于 Mac 主题小组件顶部问候语；留空时使用 iPhone 名称。")
                    .font(.caption)
                    .foregroundStyle(theme.textSecondary)

                PhotosPicker(selection: $selectedMacThemeAvatarItem, matching: .images) {
                    HStack(spacing: 12) {
                        macThemeAvatarPreview

                        VStack(alignment: .leading, spacing: 3) {
                            Text("头像")
                                .foregroundStyle(theme.textPrimary)
                            Text("从照片中选择")
                                .font(.caption)
                                .foregroundStyle(theme.textSecondary)
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(theme.textTertiary)
                    }
                    .contentShape(Rectangle())
                }
                .accessibilityIdentifier("ios.settings.macThemeWidgetAvatar")

                if appViewModel.macThemeWidgetAvatarFileName != nil {
                    Button("移除头像", role: .destructive) {
                        appViewModel.clearMacThemeWidgetAvatar()
                    }
                }

                if let macThemeAvatarErrorMessage {
                    Text(macThemeAvatarErrorMessage)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            } header: {
                Label("设备与小组件", systemImage: "iphone.and.arrow.forward")
            }

            Section {
                Toggle(isOn: $appViewModel.pushNotificationPreferences.pushEnabled) {
                    Label("允许离线推送", systemImage: "bell.badge")
                }
                Toggle(isOn: $appViewModel.pushNotificationPreferences.agentWatcherEnabled) {
                    Label("Agent Watcher 通知", systemImage: "terminal")
                }
                Toggle(isOn: $appViewModel.pushNotificationPreferences.summaryEnabled) {
                    Label("高频事件摘要", systemImage: "list.bullet.rectangle")
                }
                TextField("HTTPS 图标 URL", text: pushIconURLBinding)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            } header: {
                Label("推送通知", systemImage: "bell")
            } footer: {
                Text("离线通知使用已绑定 Relay iPhone。自定义图标仅接受 HTTPS URL。")
            }

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
            } header: {
                Text("ios_settings_home_shortcuts_section")
            } footer: {
                Text("ios_settings_home_shortcuts_footer")
            }

            Section("ios_settings_live_activity_section") {
                Toggle("ios_settings_live_activity_enabled", isOn: $appViewModel.liveActivitySettings.isEnabled)
                    .accessibilityIdentifier("ios.settings.liveActivity.enabled")

                DatePicker(
                    "ios_settings_live_activity_start",
                    selection: liveActivityStartBinding,
                    displayedComponents: .hourAndMinute
                )
                .environment(\.locale, Self.liveActivityTimeLocale)
                .accessibilityIdentifier("ios.settings.liveActivity.start")

                DatePicker(
                    "ios_settings_live_activity_end",
                    selection: liveActivityEndBinding,
                    displayedComponents: .hourAndMinute
                )
                .environment(\.locale, Self.liveActivityTimeLocale)
                .accessibilityIdentifier("ios.settings.liveActivity.end")

                if !appViewModel.liveActivitySettings.isValidTimeRange {
                    Text("ios_settings_live_activity_invalid_range")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .accessibilityIdentifier("ios.settings.liveActivity.hint")
                }
            }

            Section("ios_settings_widget_section") {
                Label("ios_settings_widget_intro", systemImage: "square.grid.2x2")
                    .font(.subheadline)
                    .foregroundStyle(theme.textSecondary)
            }

            Section {
                LabeledContent("ios_settings_app_label", value: String(localized: "ios_settings_app_name"))
                LabeledContent("ios_settings_version_label", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
            } header: {
                Text("ios_settings_about_section")
            } footer: {
                Text("鄂ICP备2021013794号-4A")
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
        .onChange(of: selectedMacThemeAvatarItem) { _, item in
            guard let item else { return }
            Task {
                defer { selectedMacThemeAvatarItem = nil }
                guard let data = try? await item.loadTransferable(type: Data.self),
                      let image = UIImage(data: data),
                      let avatarData = Self.macThemeWidgetAvatarData(from: image) else {
                    macThemeAvatarErrorMessage = "头像处理失败，请重试。"
                    return
                }
                do {
                    try appViewModel.saveMacThemeWidgetAvatarData(avatarData)
                    macThemeAvatarErrorMessage = nil
                } catch {
                    macThemeAvatarErrorMessage = "头像保存失败，请重试。"
                }
            }
        }
    }

    @ViewBuilder
    private var macThemeAvatarPreview: some View {
        ZStack {
            Circle()
                .fill(theme.surfaceSecondary)

            if let data = appViewModel.macThemeWidgetAvatarData,
               let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(theme.textSecondary)
            }
        }
        .frame(width: 44, height: 44)
        .clipShape(Circle())
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

    private func homeScreenShortcutBinding(for action: DeviceRelayHomeScreenShortcutAction) -> Binding<Bool> {
        Binding {
            appViewModel.selectedHomeScreenShortcutActions.contains(action)
        } set: { enabled in
            appViewModel.setHomeScreenShortcutAction(action, enabled: enabled)
        }
    }

    private var pushIconURLBinding: Binding<String> {
        Binding {
            appViewModel.pushNotificationPreferences.iconUrl ?? ""
        } set: { value in
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            appViewModel.pushNotificationPreferences.iconUrl = trimmed.isEmpty ? nil : trimmed
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
