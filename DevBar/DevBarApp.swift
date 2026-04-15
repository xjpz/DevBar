// DevBarApp.swift
// DevBar

import SwiftUI

@main
struct DevBarApp: App {
    @StateObject private var appViewModel = AppViewModel()

    init() {
        applyDockVisibility()
    }

    private func applyDockVisibility() {
        let hide = UserDefaults.standard.bool(forKey: Constants.Defaults.hideFromDockKey)
        NSApplication.shared.setActivationPolicy(hide ? .accessory : .regular)
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(appViewModel)
                .environmentObject(appViewModel.quotaViewModel)
        } label: {
            MenuBarIconView(text: appViewModel.statusText, iconName: appViewModel.menuBarIcon)
        }
        .menuBarExtraStyle(.window)
    }
}

private struct MenuBarIconView: View {
    let text: String
    let iconName: String

    var body: some View {
        if Constants.Icons.isCustomIcon(iconName) {
            Label(text, image: iconName)
        } else {
            Label(text, systemImage: iconName)
        }
    }
}
