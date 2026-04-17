// SettingsView.swift
// DevBar

import SwiftUI
import AppKit

struct SettingsView: View {
    @EnvironmentObject private var appViewModel: AppViewModel
    @EnvironmentObject private var quotaViewModel: QuotaViewModel
    @EnvironmentObject private var updateViewModel: UpdateViewModel

    @State private var selectedInterval: TimeInterval
    @State private var selectedIcon: String

    private let intervals: [(String, TimeInterval)] = [
        ("5 分钟", 300),
        ("10 分钟", 600),
        ("30 分钟", 1800),
        ("每小时", 3600),
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
        ScrollView {
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

                // General
                VStack(alignment: .leading, spacing: 8) {
                    Text("通用")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Toggle("登录时启动", isOn: $appViewModel.launchAtLogin)
                        .toggleStyle(.switch)
                        .controlSize(.small)

                    Toggle("不在 Dock 栏显示", isOn: $appViewModel.isHiddenFromDock)
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }

                // Last updated
                if let lastUpdated = quotaViewModel.lastUpdated {
                    Text("上次更新: \(lastUpdated.formatted(.dateTime.hour().minute().second()))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Divider()

                // About
                VStack(alignment: .leading, spacing: 8) {
                    Text("关于")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 8) {
                        Text("DevBar")
                            .fontWeight(.medium)
                        Text(appVersion)
                            .foregroundStyle(.secondary)
                    }

                    Button(action: {
                        if let url = URL(string: Constants.Update.releasesPageURL) {
                            NSWorkspace.shared.open(url)
                        }
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "link")
                            Text("Github: https://github.com/xjpz/DevBar")
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                        .font(.caption)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .safeAreaInset(edge: .bottom) {
            Button(action: {
                updateViewModel.checkForUpdates(silent: false)
            }) {
                HStack(spacing: 4) {
                    Image(systemName: updateViewModel.hasUpdateAvailable
                          ? "arrow.up.circle.fill" : "arrow.up.circle")
                    Text("检查更新")
                }
                .font(.caption)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .tint(updateViewModel.hasUpdateAvailable ? .blue : .secondary)
            .frame(maxWidth: .infinity)
            .padding(.horizontal)
            .padding(.bottom, 12)
        }
        .onChange(of: selectedInterval) { _, newValue in
            appViewModel.refreshInterval = newValue
            appViewModel.stopAutoRefresh()
            appViewModel.startRefreshIfNeeded()
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
