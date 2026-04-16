// SettingsView.swift
// DevBar

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appViewModel: AppViewModel
    @EnvironmentObject private var quotaViewModel: QuotaViewModel

    @State private var selectedInterval: TimeInterval
    @State private var selectedIcon: String

    private let intervals: [(String, TimeInterval)] = [
        ("1 分钟", 60),
        ("5 分钟", 300),
        ("10 分钟", 600),
        ("30 分钟", 1800),
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
        VStack(alignment: .leading, spacing: 16) {
            Text("设置")
                .font(.headline)

            // Menu bar icon
            VStack(alignment: .leading, spacing: 6) {
                Text("菜单栏图标")
                    .font(.subheadline)
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

            // Refresh interval
            VStack(alignment: .leading, spacing: 4) {
                Text("自动刷新间隔")
                    .font(.subheadline)
                Picker("刷新间隔", selection: $selectedInterval) {
                    ForEach(intervals, id: \.1) { label, value in
                        Text(label).tag(value)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            // Hide from Dock
            Toggle("不在 Dock 栏显示", isOn: Binding(
                get: { appViewModel.isHiddenFromDock },
                set: { appViewModel.setHiddenFromDock($0) }
            ))
            .toggleStyle(.switch)
            .controlSize(.small)

            // Last updated
            if let lastUpdated = quotaViewModel.lastUpdated {
                Text("上次更新: \(lastUpdated.formatted(.dateTime.hour().minute().second()))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
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
