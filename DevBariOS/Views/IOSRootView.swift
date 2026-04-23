import SwiftUI

struct IOSRootView: View {
    @EnvironmentObject private var appViewModel: IOSAppViewModel
    @EnvironmentObject private var languageManager: IOSLanguageManager

    var body: some View {
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
                IOSAccountsView()
            }
            .tabItem {
                Label("ios_tab_accounts", systemImage: "person.crop.rectangle.stack")
            }
            .tag(IOSAppViewModel.TabSelection.accounts)

            NavigationStack {
                IOSSettingsView()
            }
            .tabItem {
                Label("ios_tab_settings", systemImage: "gearshape")
            }
            .tag(IOSAppViewModel.TabSelection.settings)
        }
        .id("tabs.\(languageManager.selectedLanguage.rawValue)")
        .accessibilityIdentifier("ios.root.tabs")
    }
}
