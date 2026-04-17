// SettingsNotifications.swift
// DevBar

import SwiftUI
import UserNotifications

struct SettingsNotifications: View {
    @EnvironmentObject private var appViewModel: AppViewModel
    @EnvironmentObject private var notificationService: NotificationService

    @State private var isRequestingPermission = false

    var body: some View {
        Form {
            Section {
                HStack {
                    Text("通知权限")
                    Spacer()

                    if notificationService.authorizationStatus == .denied {
                        Button("已拒绝") {
                            notificationService.openSystemNotificationSettings()
                        }
                        .foregroundStyle(.red)
                    } else if notificationService.authorizationStatus == .notDetermined {
                        Button {
                            Task {
                                isRequestingPermission = true
                                _ = await notificationService.requestAuthorization()
                                isRequestingPermission = false
                            }
                        } label: {
                            if isRequestingPermission {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Text("请求权限")
                            }
                        }
                        .disabled(isRequestingPermission)
                    } else {
                        Text("已授权")
                            .foregroundStyle(.green)
                    }
                }
            }

            Section("低额度提醒") {
                Toggle("启用低额度提醒", isOn: $appViewModel.notificationLowQuotaEnabled)
                    .onChange(of: appViewModel.notificationLowQuotaEnabled) { _, newValue in
                        if newValue && notificationService.authorizationStatus == .notDetermined {
                            Task {
                                _ = await notificationService.requestAuthorization()
                            }
                        }
                    }

                if appViewModel.notificationLowQuotaEnabled {
                    HStack {
                        Text("阈值")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Picker("", selection: $appViewModel.notificationLowQuotaThreshold) {
                            ForEach(NotificationSettings.thresholdOptions, id: \.0) { threshold, label in
                                Text(label).tag(threshold)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                }
            }

            Section {
                Toggle("启用用尽提醒", isOn: $appViewModel.notificationExhaustedEnabled)
                    .onChange(of: appViewModel.notificationExhaustedEnabled) { _, newValue in
                        if newValue && notificationService.authorizationStatus == .notDetermined {
                            Task {
                                _ = await notificationService.requestAuthorization()
                            }
                        }
                    }

                Toggle("启用额度重置提醒", isOn: $appViewModel.notificationResetEnabled)
                    .onChange(of: appViewModel.notificationResetEnabled) { _, newValue in
                        if newValue && notificationService.authorizationStatus == .notDetermined {
                            Task {
                                _ = await notificationService.requestAuthorization()
                            }
                        }
                    }
            } header: {
                Text("其他提醒")
            } footer: {
                Text("用尽提醒在额度耗尽时通知，重置提醒在额度恢复时通知")
                    .font(.caption)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }
}
