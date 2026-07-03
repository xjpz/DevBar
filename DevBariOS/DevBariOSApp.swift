import DevBarCore
import Foundation
import SwiftUI
import SwiftData

@main
struct DevBariOSApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var appViewModel = IOSAppViewModel()
    @StateObject private var languageManager = IOSLanguageManager()
    @StateObject private var themeManager = IOSThemeManager()
    @StateObject private var shortcutStore = ShortcutStore.shared

    init() {
        Self.ensureSharedModelStoreDirectoryExists()
    }

    var body: some Scene {
        WindowGroup {
            ThemeRootView()
                .environmentObject(appViewModel)
                .environmentObject(languageManager)
                .environmentObject(themeManager)
                .environmentObject(shortcutStore)
                .environment(\.locale, languageManager.currentLocale)
                .environment(\.themeTokens, themeManager.resolvedTokens)
                .font(themeManager.resolvedTokens.bodyFont)
                .preferredColorScheme(themeManager.preferredColorScheme)
                .id("app.root.\(languageManager.selectedLanguage.rawValue)")
                .task {
                    await appViewModel.startDeferredLaunchWork()
                }
                .onChange(of: scenePhase) { _, newPhase in
                    switch newPhase {
                    case .active:
                        IOSTerminalSessionRegistry.shared.updateBackgroundState(isBackgrounded: false)
                        Task {
                            await appViewModel.refreshOnForeground()
                        }
                    case .background:
                        IOSTerminalSessionRegistry.shared.updateBackgroundState(isBackgrounded: true)
                    default:
                        break
                    }
                }
                .onChange(of: languageManager.selectedLanguage) { _, _ in
                    Task {
                        await appViewModel.refreshHomeScreenShortcutsForCurrentState()
                    }
                }
                .onOpenURL { url in
                    guard let action = ShortcutStore.action(for: url) else { return }
                    shortcutStore.handle(action)
                }
        }
        .modelContainer(
            for: [
                IOSAPIRecord.self,
                IOSWebHistoryRecord.self,
                IOSMemoItem.self,
                IOSMarkdownDocument.self,
                IOSHermesConversation.self,
                IOSHermesMessage.self,
                IOSTerminalServer.self,
            ],
            isAutosaveEnabled: true,
            isUndoEnabled: false
        )
    }

    /// SwiftData's default `ModelConfiguration` uses `groupContainer: .automatic`. Because this app
    /// declares a single App Group, `.automatic` places `default.store` inside the App Group container
    /// instead of the app sandbox. App Group containers do not auto-create `Library/Application Support`,
    /// so SwiftData fails to create the store (NSCocoaErrorDomain 512 / "No such file or directory") and
    /// the process aborts on launch — reproducible on device, masked on the Simulator by CoreData's
    /// directory-recovery path. Pre-create the directory before the scene builds the container.
    private static func ensureSharedModelStoreDirectoryExists() {
        guard let groupURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: DevBarCoreConstants.AppGroup.groupID
        ) else { return }
        let appSupport = groupURL.appending(path: "Library/Application Support", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
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
