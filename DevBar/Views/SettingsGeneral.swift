// SettingsGeneral.swift
// DevBar

import AppKit
import DevBarCore
import SwiftUI

struct SettingsGeneral: View {
    @EnvironmentObject private var appViewModel: AppViewModel
    @EnvironmentObject private var updateViewModel: UpdateViewModel
    @EnvironmentObject private var languageManager: LanguageManager

    @State private var selectedIcon: String
    @State private var showRestartAlert = false

    init() {
        let savedIcon = UserDefaults.standard.string(forKey: Constants.Defaults.menuBarIconKey)
        _selectedIcon = State(
            initialValue: savedIcon ?? Constants.Defaults.defaultMenuBarIcon
        )
    }

    var body: some View {
        Form {
            Section {
                HStack {
                    Text("language")
                    Spacer()
                    Picker("", selection: $languageManager.selectedLanguage) {
                        ForEach(AppLanguage.allCases, id: \.rawValue) { lang in
                            Text(lang.displayName).tag(lang)
                        }
                    }
                    .pickerStyle(.menu)
                }
            }

            Section("menu_bar_icon") {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(32), spacing: 8), count: 5), spacing: 8) {
                    ForEach(Constants.Icons.availableIcons, id: \.0) { iconName, _ in
                        iconView(for: iconName)
                            .frame(width: 32, height: 32)
                            .background(selectedIcon == iconName ? Color.accentColor.opacity(0.2) : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(selectedIcon == iconName ? Color.accentColor : Color.clear, lineWidth: 1.5)
                            )
                            .onTapGesture {
                                selectedIcon = iconName
                                appViewModel.menuBarIcon = iconName
                            }
                    }
                }
            }

            Section("general") {
                Toggle("launch_at_login", isOn: $appViewModel.launchAtLogin)
                Toggle("hide_from_dock", isOn: $appViewModel.isHiddenFromDock)
                Toggle("prevent_sleep", isOn: $appViewModel.antiSleepEnabled)
                Text(appViewModel.antiSleepStatusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("about") {
                HStack {
                    Text("version")
                    Spacer()
                    Text(appVersion)
                        .foregroundStyle(.secondary)
                }

                Button {
                    if let url = URL(string: "https://github.com/xjpz/DevBar") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    HStack {
                        Text("GitHub")
                        Spacer()
                        Image("Github")
                            .resizable()
                            .frame(width: 16, height: 16)
                    }
                }
                .buttonStyle(.plain)

                Button {
                    updateViewModel.checkForUpdates(silent: false)
                } label: {
                    HStack {
                        Text("check_for_updates")
                        Spacer()
                        Image(systemName: updateViewModel.hasUpdateAvailable
                              ? "arrow.up.circle.fill" : "arrow.up.circle")
                        .tint(updateViewModel.hasUpdateAvailable ? .blue : .secondary)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .onChange(of: languageManager.selectedLanguage) { _, _ in
            showRestartAlert = true
        }
        .alert("restart_required", isPresented: $showRestartAlert) {
            Button("restart_now") {
                languageManager.restartToApplyLanguage()
            }
            Button("later") {
                showRestartAlert = false
            }
        } message: {
            Text("restart_to_apply_language")
        }
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }

    private func iconView(for iconName: String) -> some View {
        Image(systemName: iconName)
            .font(.system(size: 20))
    }
}

private extension Double {
    var nonZero: Double? {
        self > 0 ? self : nil
    }
}
