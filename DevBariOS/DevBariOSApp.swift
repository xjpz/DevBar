import SwiftUI
import SwiftData

@main
struct DevBariOSApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var appViewModel = IOSAppViewModel()
    @StateObject private var languageManager = IOSLanguageManager()
    @StateObject private var themeManager = IOSThemeManager()

    var body: some Scene {
        WindowGroup {
            ThemeRootView()
                .environmentObject(appViewModel)
                .environmentObject(languageManager)
                .environmentObject(themeManager)
                .environment(\.locale, languageManager.currentLocale)
                .environment(\.themeTokens, themeManager.resolvedTokens)
                .font(themeManager.resolvedTokens.bodyFont)
                .preferredColorScheme(themeManager.preferredColorScheme)
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
        .modelContainer(for: [IOSAPIRecord.self, IOSWebHistoryRecord.self, IOSMemoItem.self, IOSMarkdownDocument.self], isAutosaveEnabled: true, isUndoEnabled: false)
    }
}

private struct ThemeRootView: View {
    @Environment(\.colorScheme) private var systemColorScheme
    @EnvironmentObject private var themeManager: IOSThemeManager

    var body: some View {
        IOSRootView()
            .onAppear { themeManager.updateBarAppearance() }
            .onChange(of: systemColorScheme) { _, newScheme in
                themeManager.systemColorScheme = newScheme
                themeManager.updateBarAppearance()
            }
            .onChange(of: themeManager.selectedMode) { _, _ in
                themeManager.updateBarAppearance()
            }
            .onChange(of: themeManager.selectedFont) { _, _ in
                themeManager.updateBarAppearance()
            }
    }
}
