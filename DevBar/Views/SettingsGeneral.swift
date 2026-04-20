// SettingsGeneral.swift
// DevBar

import SwiftUI

struct SettingsGeneral: View {
    @EnvironmentObject private var appViewModel: AppViewModel
    @EnvironmentObject private var quotaViewModel: QuotaViewModel
    @EnvironmentObject private var languageManager: LanguageManager

    @State private var selectedInterval: TimeInterval
    @State private var selectedIcon: String
    @State private var showRestartAlert = false

    private let intervals: [(String, TimeInterval)] = [
        (String(localized: "minutes_3"), 180),
        (String(localized: "minutes_5"), 300),
        (String(localized: "minutes_10"), 600),
        (String(localized: "minutes_30"), 1800),
        (String(localized: "minutes_60"), 3600),
        (String(localized: "never"), 0),
    ]

    init() {
        let savedInterval = UserDefaults.standard.double(forKey: Constants.Defaults.refreshIntervalKey)
        _selectedInterval = State(
            initialValue: savedInterval.nonZero ?? Constants.Defaults.defaultRefreshInterval
        )
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

            Section {
                HStack {
                    Text("auto_refresh_interval")
                    Spacer()
                    Picker("", selection: $selectedInterval) {
                        ForEach(intervals, id: \.1) { label, value in
                            Text(label).tag(value)
                        }
                    }
                    .pickerStyle(.menu)
                }
            }

            Section("general") {
                Toggle("launch_at_login", isOn: $appViewModel.launchAtLogin)
                Toggle("hide_from_dock", isOn: $appViewModel.isHiddenFromDock)
            }

            if let lastUpdated = quotaViewModel.lastUpdated {
                Section("status") {
                    Text("last_updated \(lastUpdated.formatted(.dateTime.hour().minute().second()))")
                        .foregroundStyle(.secondary)
                }
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
        .onChange(of: selectedInterval) { _, newValue in
            appViewModel.refreshInterval = newValue
            appViewModel.stopAutoRefresh()
            appViewModel.startRefreshIfNeeded()
        }
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
