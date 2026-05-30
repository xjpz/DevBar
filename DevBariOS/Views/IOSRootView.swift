import DevBarCore
import SwiftUI

enum ShortcutDestination: String, Identifiable {
    case memo, accounts, apiClient, ocr
    var id: String { rawValue }
}

struct IOSRootView: View {
    @EnvironmentObject private var appViewModel: IOSAppViewModel
    @EnvironmentObject private var languageManager: IOSLanguageManager
    @EnvironmentObject private var shortcutStore: ShortcutStore
    @Environment(\.themeTokens) private var theme
    @State private var shortcutDestination: ShortcutDestination?
    @State private var shortcutMessage: String?

    var body: some View {
        ZStack {
            currentTabBackground
                .ignoresSafeArea()

            TabView(selection: $appViewModel.selectedTab) {
                NavigationStack {
                    IOSDashboardView()
                }
                .id("dashboard.\(languageManager.selectedLanguage.rawValue)")
                .tabItem {
                    Label("ios_tab_overview", systemImage: "sparkles")
                }
                .tag(IOSAppViewModel.TabSelection.dashboard)

                NavigationStack {
                    if #available(iOS 18.0, *) {
                        IOSWebKitView()
                    } else {
                        ContentUnavailableView("Requires iOS 18+", systemImage: "globe")
                    }
                }
                .tabItem {
                    Label("WebKit", systemImage: "globe")
                }
                .tag(IOSAppViewModel.TabSelection.webkit)

                NavigationStack {
                    IOSToolsView()
                }
                .tabItem {
                    Label("Tools", systemImage: "hammer")
                }
                .tag(IOSAppViewModel.TabSelection.tools)
            }
            .toolbarBackground(theme.backgroundPrimary, for: .tabBar)
            .toolbarBackground(.visible, for: .tabBar)
        }
        .id("tabs.\(languageManager.selectedLanguage.rawValue)")
        .accessibilityIdentifier("ios.root.tabs")
        .sheet(item: $shortcutDestination) { destination in
            NavigationStack {
                Group {
                    switch destination {
                    case .memo:
                        IOSMemoListView()
                    case .accounts:
                        IOSAccountsView()
                    case .apiClient:
                        IOSAPIClientView()
                    case .ocr:
                        IOSOCRView()
                    }
                }
            }
        }
        .onAppear {
            handlePendingShortcut()
        }
        .onChange(of: shortcutStore.pendingAction) { _, action in
            guard let action else { return }
            executeShortcut(action)
            shortcutStore.consume()
        }
        .alert("DevBar", isPresented: Binding(
            get: { shortcutMessage != nil },
            set: { if !$0 { shortcutMessage = nil } }
        )) {
            Button("OK", role: .cancel) { shortcutMessage = nil }
        } message: {
            Text(shortcutMessage ?? "")
        }
    }

    /// 冷启动时 pendingAction 在视图创建前已设置，onChange 不会触发。
    /// 延迟到下一个 RunLoop 确保 SwiftUI 视图层级就绪后再呈现 sheet。
    private func handlePendingShortcut() {
        guard shortcutStore.pendingAction != nil else { return }
        DispatchQueue.main.async {
            guard let action = shortcutStore.pendingAction else { return }
            executeShortcut(action)
            shortcutStore.consume()
        }
    }

    /// Sheet 不依赖 NavigationStack 状态，可在任意 tab 下直接呈现
    private func executeShortcut(_ action: ShortcutStore.Action) {
        switch action {
        case .memo:
            shortcutDestination = .memo
        case .qrScan:
            shortcutDestination = nil
            appViewModel.selectedTab = .dashboard
            DispatchQueue.main.async {
                appViewModel.requestDashboardScanner()
            }
        case .apiClient:
            shortcutDestination = .apiClient
        case .lockMac:
            Task {
                shortcutMessage = await MacControlIntentRunner.run(.lockScreen, selectedMac: nil)
            }
        case .wakeMacDisplay:
            Task {
                shortcutMessage = await MacControlIntentRunner.run(.wakeDisplay, selectedMac: nil)
            }
        case .sleepMacDisplay:
            Task {
                shortcutMessage = await MacControlIntentRunner.run(.displaySleep, selectedMac: nil)
            }
        case .ocr:
            shortcutDestination = .ocr
        }
    }

    private var currentTabBackground: Color {
        switch appViewModel.selectedTab {
        case .dashboard:
            theme.backgroundPrimary
        case .webkit, .tools:
            theme.backgroundSecondary
        }
    }
}
