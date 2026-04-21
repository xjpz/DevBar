// DevBarApp.swift
// DevBar

import SwiftUI

@main
struct DevBarApp: App {
    @StateObject private var appViewModel = AppViewModel()
    @StateObject private var languageManager = LanguageManager()

    init() {
        applyDockVisibility()
    }

    private func applyDockVisibility() {
        let hide = UserDefaults.standard.bool(forKey: Constants.Defaults.hideFromDockKey)
        NSApplication.shared.setActivationPolicy(hide ? .accessory : .regular)
    }

    private static func findStatusBarButton() -> NSStatusBarButton? {
        guard let items = NSStatusBar.system.value(forKey: "items") as? [AnyObject] else {
            return nil
        }
        for item in items {
            if let button = item.value(forKey: "button") as? NSStatusBarButton {
                return button
            }
        }
        return nil
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(appViewModel)
                .environmentObject(appViewModel.quotaViewModel)
                .environmentObject(appViewModel.openAIQuotaViewModel)
                .environmentObject(appViewModel.updateViewModel)
                .environmentObject(languageManager)
                .environment(\.locale, languageManager.currentLocale)
                .onAppear {
                    appViewModel.languageManager = languageManager
                    // 延迟获取 status bar button 引用
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        if let button = Self.findStatusBarButton() {
                            appViewModel.statusBarButton = button
                        }
                    }
                }
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
