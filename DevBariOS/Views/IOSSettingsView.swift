import DevBarCore
import SwiftUI

struct IOSSettingsView: View {
    @EnvironmentObject private var appViewModel: IOSAppViewModel
    @EnvironmentObject private var languageManager: IOSLanguageManager

    private let intervals: [(LocalizedStringKey, TimeInterval)] = [
        ("ios_settings_interval_3m", 180),
        ("ios_settings_interval_5m", 300),
        ("ios_settings_interval_10m", 600),
        ("ios_settings_interval_30m", 1800),
        ("ios_settings_interval_60m", 3600),
        ("ios_settings_interval_never", 0),
    ]

    var body: some View {
        Form {
            Section("ios_settings_language_section") {
                Picker("language", selection: $languageManager.selectedLanguage) {
                    Text("follow_system").tag(IOSAppLanguage.system)
                    Text("ios_settings_language_zh_hans").tag(IOSAppLanguage.zhHans)
                    Text("ios_settings_language_en").tag(IOSAppLanguage.en)
                }
                .accessibilityIdentifier("ios.settings.language")
            }

            Section("ios_settings_refresh_section") {
                Picker("ios_settings_auto_refresh_interval", selection: $appViewModel.refreshInterval) {
                    ForEach(intervals, id: \.1) { label, value in
                        Text(label).tag(value)
                    }
                }
                .accessibilityIdentifier("ios.settings.refreshInterval")

                Text("ios_settings_refresh_hint")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("ios.settings.refreshHint")
            }

            Section("ios_settings_widget_section") {
                Text("ios_settings_widget_intro")
                    .foregroundStyle(.secondary)
                Text("ios_settings_widget_hint")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("ios_settings_about_section") {
                LabeledContent("ios_settings_app_label", value: String(localized: "ios_settings_app_name"))
                LabeledContent("ios_settings_version_label", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
            }
        }
        .navigationTitle("ios_settings_title")
        .accessibilityIdentifier("ios.settings.screen")
    }
}
