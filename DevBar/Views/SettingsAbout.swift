// SettingsAbout.swift
// DevBar

import SwiftUI
import AppKit

struct SettingsAbout: View {
    @EnvironmentObject private var updateViewModel: UpdateViewModel

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 4) {
                appIcon
                Text("DevBar \(appVersion)")
                    .font(.headline)
            }
            .padding(.top, 16)
            .padding(.bottom, 8)

            Form {
                Section {
                    Button {
                        if let url = URL(string: "https://github.com/xjpz/DevBar") {
                            NSWorkspace.shared.open(url)
                        }
                    } label: {
                        VStack(alignment: .center, spacing: 6) {
                            Image("Github")
                                .resizable()
                                .frame(width: 24, height: 24)
                            Text("https://github.com/xjpz/DevBar")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .buttonStyle(.plain)

            Spacer()

            Button {
                updateViewModel.checkForUpdates(silent: false)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: updateViewModel.hasUpdateAvailable
                          ? "arrow.up.circle.fill" : "arrow.up.circle")
                    Text("check_for_updates")
                }
                .font(.body)
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .tint(updateViewModel.hasUpdateAvailable ? .blue : .secondary)
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
    }

    private var appIcon: some View {
        Group {
            if let appIcon = NSApp.applicationIconImage {
                Image(nsImage: appIcon)
                    .resizable()
            } else {
                Image(systemName: "app.badge")
                    .font(.system(size: 48))
            }
        }
        .frame(width: 64, height: 64)
    }

    private func row(_ title: String, value: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
        }
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }
}
