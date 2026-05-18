import DevBarCore
import SwiftUI

struct IOSSettingsView: View {
    @EnvironmentObject private var appViewModel: IOSAppViewModel
    @EnvironmentObject private var languageManager: IOSLanguageManager
    @EnvironmentObject private var themeManager: IOSThemeManager
    @Environment(\.themeTokens) private var theme
    @State private var isGreetingEditorExpanded = false

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

            Section("ios_settings_widget_section") {
                Label("ios_settings_widget_intro", systemImage: "square.grid.2x2")
                    .font(.subheadline)
                    .foregroundStyle(theme.textSecondary)
            }

            Section("ios_settings_about_section") {
                LabeledContent("ios_settings_app_label", value: String(localized: "ios_settings_app_name"))
                LabeledContent("ios_settings_version_label", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
            }
        }
        .scrollContentBackground(.hidden)
        .iosGeekScreenBackground(theme)
        .toolbarBackground(.hidden, for: .navigationBar)
        .navigationTitle("ios_settings_title")
        .navigationBarTitleDisplayMode(.large)
        .toolbar(.hidden, for: .tabBar)
        .accessibilityIdentifier("ios.settings.screen")
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
}
