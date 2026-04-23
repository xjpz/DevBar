// SettingsNotifications.swift
// DevBar

import SwiftUI
import UserNotifications
import DevBarCore

struct SettingsNotifications: View {
    @EnvironmentObject private var appViewModel: AppViewModel
    @EnvironmentObject private var notificationService: NotificationService

    @State private var isRequestingPermission = false

    var body: some View {
        Form {
            Section {
                HStack {
                    Text("notification_permission")
                    Spacer()

                    if notificationService.authorizationStatus == .denied {
                        Button("denied") {
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
                                Text("request_permission")
                            }
                        }
                        .disabled(isRequestingPermission)
                    } else {
                        Text("authorized")
                            .foregroundStyle(.green)
                    }
                }
            }

            Section {
                Toggle("enable_low_quota_alert", isOn: $appViewModel.notificationLowQuotaEnabled)
                    .onChange(of: appViewModel.notificationLowQuotaEnabled) { _, newValue in
                        if newValue && notificationService.authorizationStatus == .notDetermined {
                            Task {
                                _ = await notificationService.requestAuthorization()
                            }
                        }
                    }

                if appViewModel.notificationLowQuotaEnabled {
                    HStack {
                        Text("threshold")
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
                Toggle("enable_exhausted_alert", isOn: $appViewModel.notificationExhaustedEnabled)
                    .onChange(of: appViewModel.notificationExhaustedEnabled) { _, newValue in
                        if newValue && notificationService.authorizationStatus == .notDetermined {
                            Task {
                                _ = await notificationService.requestAuthorization()
                            }
                        }
                    }

                Toggle("enable_reset_alert", isOn: $appViewModel.notificationResetEnabled)
                    .onChange(of: appViewModel.notificationResetEnabled) { _, newValue in
                        if newValue && notificationService.authorizationStatus == .notDetermined {
                            Task {
                                _ = await notificationService.requestAuthorization()
                            }
                        }
                    }
            } footer: {
                Text("alerts_footer")
                    .font(.caption)
            }

            Section {
                HStack(spacing: 12) {
                    Image(systemName: "widget.small")
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("widget_guide_title")
                            .font(.subheadline)
                        Text("widget_guide_description")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }
}
