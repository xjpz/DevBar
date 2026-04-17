// SettingsGeneral.swift
// DevBar

import SwiftUI

struct SettingsGeneral: View {
    @EnvironmentObject private var appViewModel: AppViewModel
    @EnvironmentObject private var quotaViewModel: QuotaViewModel

    @State private var selectedInterval: TimeInterval
    @State private var selectedIcon: String

    private let intervals: [(String, TimeInterval)] = [
        ("3 分钟", 180),
        ("5 分钟", 300),
        ("10 分钟", 600),
        ("30 分钟", 1800),
        ("60 分钟", 3600),
        ("从不", 0),
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
            Section("菜单栏图标") {
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
                    Text("自动刷新间隔")
                    Spacer()
                    Picker("", selection: $selectedInterval) {
                        ForEach(intervals, id: \.1) { label, value in
                            Text(label).tag(value)
                        }
                    }
                    .pickerStyle(.menu)
                }
            }

            Section("通用") {
                Toggle("登录时启动", isOn: $appViewModel.launchAtLogin)
                Toggle("不在 Dock 栏显示", isOn: $appViewModel.isHiddenFromDock)
            }

            if let lastUpdated = quotaViewModel.lastUpdated {
                Section("状态") {
                    Text("上次更新: \(lastUpdated.formatted(.dateTime.hour().minute().second()))")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
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
