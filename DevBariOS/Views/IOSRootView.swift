import SwiftUI

struct IOSRootView: View {
    @EnvironmentObject private var appViewModel: IOSAppViewModel
    @EnvironmentObject private var languageManager: IOSLanguageManager
    @Environment(\.themeTokens) private var theme

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
        }
        .id("tabs.\(languageManager.selectedLanguage.rawValue)")
        .accessibilityIdentifier("ios.root.tabs")
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
