// SettingsView.swift
// DevBar

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appViewModel: AppViewModel
    @EnvironmentObject private var quotaViewModel: QuotaViewModel
    @EnvironmentObject private var updateViewModel: UpdateViewModel
    @EnvironmentObject private var notificationService: NotificationService

    @AppStorage("selectedSettingsTab") private var selectedTab: SettingsTab = .general

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $selectedTab) {
                ForEach(SettingsTab.allCases, id: \.self) { tab in
                    Label(tab.localizedName, systemImage: tab.icon).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)

            switch selectedTab {
            case .general:
                SettingsGeneral()
            case .notifications:
                SettingsNotifications()
            case .about:
                SettingsAbout()
            }
        }
        .frame(width: 340, height: 420)
    }
}
