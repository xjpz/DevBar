import DevBarCore
import Foundation
import SwiftUI
import SwiftData

@main
struct DevBariOSApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    private let modelContainer: ModelContainer
    @StateObject private var appViewModel = IOSAppViewModel()
    @StateObject private var languageManager = IOSLanguageManager()
    @StateObject private var themeManager = IOSThemeManager()
    @StateObject private var shortcutStore = ShortcutStore.shared
    @StateObject private var accountViewModel = IOSAccountViewModel()

    init() {
        Self.ensureSharedModelStoreDirectoryExists()
        self.modelContainer = Self.makeModelContainer()
    }

    var body: some Scene {
        WindowGroup {
            ThemeRootView()
                .environmentObject(appViewModel)
                .environmentObject(languageManager)
                .environmentObject(themeManager)
                .environmentObject(shortcutStore)
                .environmentObject(accountViewModel)
                .environment(\.locale, languageManager.currentLocale)
                .environment(\.themeTokens, themeManager.resolvedTokens)
                .font(themeManager.resolvedTokens.bodyFont)
                .preferredColorScheme(themeManager.preferredColorScheme)
                .id("app.root.\(languageManager.selectedLanguage.rawValue)")
                .task {
                    if scenePhase == .active {
                        appViewModel.startAutoRefreshIfNeeded()
                    }
                    await appViewModel.startDeferredLaunchWork()
                    await accountViewModel.restoreSession()
                }
                .onChange(of: scenePhase) { _, newPhase in
                    switch newPhase {
                    case .active:
                        IOSTerminalSessionRegistry.shared.updateBackgroundState(isBackgrounded: false)
                        IOSAppIconController.shared.synchronizePreferredIcon()
                        appViewModel.startAutoRefreshIfNeeded()
                        Task {
                            appViewModel.flushDiagnosticsInBackground()
                            await appViewModel.refreshOnForeground()
                        }
                    case .background:
                        IOSTerminalSessionRegistry.shared.updateBackgroundState(isBackgrounded: true)
                        appViewModel.stopAutoRefresh()
                        DiagnosticLogger.shared.record(
                            level: .info,
                            category: "app.lifecycle",
                            name: "ios_scene_background",
                            message: "iOS scene entered background"
                        )
                    default:
                        break
                    }
                }
                .onChange(of: languageManager.selectedLanguage) { _, _ in
                    Task {
                        await appViewModel.refreshHomeScreenShortcutsForCurrentState()
                    }
                }
                .onChange(of: accountViewModel.profile?.profileVersion) { _, _ in
                    guard let displayName = accountViewModel.profile?.displayName else { return }
                    appViewModel.macThemeWidgetUserName = displayName
                }
                .onOpenURL { url in
                    guard let action = ShortcutStore.action(for: url) else { return }
                    shortcutStore.handle(action)
                }
        }
        .modelContainer(modelContainer)
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

    private static func makeModelContainer() -> ModelContainer {
        let schema = Schema(modelTypes)
        let configuration = ModelConfiguration(
            schema: schema,
            groupContainer: .identifier(DevBarCoreConstants.AppGroup.groupID),
            cloudKitDatabase: .none
        )
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Unable to create SwiftData model container: \(error)")
        }
    }

    private static var modelTypes: [any PersistentModel.Type] {
        [
            IOSAPIRecord.self,
            IOSWebHistoryRecord.self,
            IOSMemoItem.self,
            IOSMarkdownDocument.self,
            IOSHermesConversation.self,
            IOSHermesMessage.self,
            IOSTerminalServer.self,
        ]
    }
}

private struct ThemeRootView: View {
    @Environment(\.colorScheme) private var systemColorScheme
    @EnvironmentObject private var themeManager: IOSThemeManager

    var body: some View {
        IOSRootView()
            .onAppear {
                themeManager.updateBarAppearance()
            }
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
