import SwiftUI

@main
struct DevBariOSApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var appViewModel = IOSAppViewModel()
    @StateObject private var languageManager = IOSLanguageManager()

    var body: some Scene {
        WindowGroup {
            IOSRootView()
                .environmentObject(appViewModel)
                .environmentObject(languageManager)
                .environment(\.locale, languageManager.currentLocale)
                .id("app.root.\(languageManager.selectedLanguage.rawValue)")
                .task {
                    await appViewModel.refreshOnLaunch()
                }
                .onChange(of: scenePhase) { _, newPhase in
                    guard newPhase == .active else { return }
                    Task {
                        await appViewModel.refreshOnForeground()
                    }
                }
        }
    }
}
