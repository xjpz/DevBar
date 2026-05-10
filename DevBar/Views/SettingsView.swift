// SettingsView.swift
// DevBar

import DevBarCore
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appViewModel: AppViewModel
    @EnvironmentObject private var quotaViewModel: QuotaViewModel
    @EnvironmentObject private var openAIQuotaViewModel: OpenAIQuotaViewModel
    @EnvironmentObject private var updateViewModel: UpdateViewModel
    @EnvironmentObject private var notificationService: NotificationService

    @AppStorage("selectedSettingsTab") private var selectedTab: SettingsTab = .general

    var body: some View {
        VStack(spacing: 0) {
            // Tab 图标栏
            HStack(spacing: 0) {
                ForEach(SettingsTab.allCases, id: \.self) { tab in
                    Button {
                        selectedTab = tab
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: tab.icon)
                                .font(.system(size: 15))
                                .foregroundStyle(selectedTab == tab ? Color.accentColor : .secondary)
                                .frame(maxWidth: .infinity)
                                .frame(height: 28)
                            Rectangle()
                                .fill(Color.accentColor)
                                .frame(width: 20, height: 2)
                                .opacity(selectedTab == tab ? 1 : 0)
                        }
                        .contentShape(Rectangle())
                        .help(tab.localizedName)
                    }
                    .buttonStyle(.plain)
                    .contentShape(Rectangle())
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)

            switch selectedTab {
            case .general:
                SettingsGeneral()
            case .notifications:
                SettingsNotifications()
            case .finder:
                SettingsFinder()
            case .accounts:
                SettingsAccounts()
            case .weChat:
                SettingsWeChat(viewModel: appViewModel.weChatViewModel)
            case .about:
                SettingsAbout()
            }
        }
        .frame(width: 340, height: 480)
    }
}
