import Combine
import SwiftData
import SwiftUI
import Translation
import UIKit
import WebKit

@available(iOS 18.0, *)
struct IOSWebKitView: View {
    @Environment(\.themeTokens) private var theme
    @EnvironmentObject private var themeManager: IOSThemeManager
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \IOSAPIRecord.lastOpenedAt, order: .reverse) private var savedRecords: [IOSAPIRecord]
    @Query(sort: \IOSWebHistoryRecord.visitedAt, order: .reverse) private var historyRecords: [IOSWebHistoryRecord]

    @StateObject private var browser = IOSBrowserStore()
    @State private var addressText = ""
    @State private var isShowingBrowser = false
    @State private var apiClientRecord: IOSAPIRecord?
    @State private var isShowingTabsManager = false
    @State private var isShowingRecordsManager = false
    @State private var isShowingHistoryManager = false
    @State private var pendingHistoryURL: String?
    @AppStorage("webkit.searchEngine") private var searchEngine: IOSSearchEngine = .google

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                quickOpenCard
                tabsSection
                recordsSection
                historySection
            }
            .padding(16)
        }
        .iosGeekScreenBackground(theme)
        .navigationTitle("WebKit")
        .toolbarTitleDisplayMode(.inlineLarge)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    openNewTab()
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .navigationDestination(isPresented: $isShowingBrowser) {
            IOSBrowserView(browser: browser)
        }
        .navigationDestination(item: $apiClientRecord) { record in
            IOSAPIClientView(record: record)
        }
        .navigationDestination(isPresented: $isShowingTabsManager) {
            IOSTabsSheet(browser: browser)
        }
        .navigationDestination(isPresented: $isShowingRecordsManager) {
            IOSAPIRecordsSheet(
                records: savedRecords,
                openRecord: openRecord
            )
        }
        .navigationDestination(isPresented: $isShowingHistoryManager) {
            IOSHistoryRecordsView(
                records: historyRecords,
                openHistory: { record in
                    pendingHistoryURL = record.url
                    isShowingHistoryManager = false
                }
            )
        }
        .onChange(of: isShowingHistoryManager) { _, isShowing in
            if !isShowing, let url = pendingHistoryURL {
                pendingHistoryURL = nil
                openURLString(url)
            }
        }
        .onReceive(browser.$selectedTabID) { _ in
            addressText = browser.currentTab?.urlString ?? ""
        }
        .onChange(of: browser.latestVisitedPage?.id) { _, _ in
            saveLatestHistory()
        }
        .onAppear {
            addressText = browser.currentTab?.urlString ?? ""
        }
    }

    private var quickOpenCard: some View {
        HStack(spacing: 10) {
            HStack(spacing: 10) {
                Menu {
                    ForEach(IOSSearchEngine.allCases, id: \.self) { engine in
                        Button {
                            searchEngine = engine
                        } label: {
                            Label(engine.localizedName, systemImage: engine == searchEngine ? "checkmark" : "")
                        }
                    }
                } label: {
                    Image(systemName: searchEngine.systemImage)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(theme.brandPrimary)
                        .frame(width: 28, height: 28)
                        .background(theme.surfaceSecondary, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }

                Rectangle()
                    .fill(theme.borderSubtle)
                    .frame(width: 1, height: 18)

                TextField("Search or enter website name", text: $addressText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .submitLabel(.go)
                    .onSubmit {
                        openAddress()
                    }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(theme.backgroundSecondary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            Button {
                openAddress()
            } label: {
                Image(systemName: "arrow.right.circle")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(theme.brandPrimary)
                    .frame(width: 36, height: 36)
                    .background(theme.surfacePrimary.opacity(0.72), in: Circle())
                    .overlay(
                        Circle()
                            .stroke(theme.borderSubtle.opacity(0.7), lineWidth: 0.8)
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .iosGlassContainer(theme, cornerRadius: 20)
    }

    private var tabsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(title: "Tabs", systemImage: "square.on.square.dashed") {
                isShowingTabsManager = true
            }

            if browser.orderedTabs.isEmpty {
                ContentUnavailableView(
                    "No Tabs yet",
                    systemImage: "square.on.square.dashed",
                    description: Text("Open a page from Quick Open or tap +.")
                )
                .frame(maxWidth: .infinity, minHeight: 140)
            } else {
                ForEach(browser.orderedTabs.prefix(5)) { tab in
                    Button {
                        openTab(tab)
                    } label: {
                        row(
                            title: tab.title,
                            subtitle: tab.urlString,
                            systemImage: tab.isPinned ? "pin.fill" : "globe",
                            badge: tab.id == browser.selectedTabID ? "Active" : nil
                        )
                    }
                    .buttonStyle(.plain)
                    .swipeActions {
                        Button {
                            browser.togglePin(tab.id)
                        } label: {
                            Label(tab.isPinned ? "Unpin" : "Pin", systemImage: tab.isPinned ? "pin.slash" : "pin")
                        }
                        .tint(.orange)

                        Button(role: .destructive) {
                            browser.close(tab.id)
                        } label: {
                            Label("Close", systemImage: "trash")
                        }
                    }
                }
            }
        }
        .padding(16)
        .iosGlassContainer(theme, cornerRadius: 20)
    }

    private var recordsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(title: "API Records", systemImage: "tray.full") {
                isShowingRecordsManager = true
            }

            if savedRecords.isEmpty {
                ContentUnavailableView(
                    "No API Records yet",
                    systemImage: "bookmark",
                    description: Text("Save pages from the browser detail view.")
                )
                .frame(maxWidth: .infinity, minHeight: 160)
            } else {
                ForEach(savedRecords.prefix(5)) { record in
                    Button {
                        openRecord(record)
                    } label: {
                        row(
                            title: record.title,
                            subtitle: record.url,
                            systemImage: record.isFavorite ? "star.fill" : "bookmark",
                            badge: recordBadge(record)
                        )
                    }
                    .buttonStyle(.plain)
                    .swipeActions {
                        Button {
                            record.isFavorite.toggle()
                            record.lastOpenedAt = .now
                        } label: {
                            Label(record.isFavorite ? "Unfavorite" : "Favorite", systemImage: record.isFavorite ? "star.slash" : "star")
                        }
                        .tint(.yellow)
                    }
                }
            }
        }
        .padding(16)
        .iosGlassContainer(theme, cornerRadius: 20)
    }

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(title: "History", systemImage: "clock.arrow.circlepath") {
                isShowingHistoryManager = true
            }

            if historyRecords.isEmpty {
                ContentUnavailableView(
                    "No History yet",
                    systemImage: "clock",
                    description: Text("Visited pages will appear here.")
                )
                .frame(maxWidth: .infinity, minHeight: 140)
            } else {
                ForEach(historyRecords.prefix(5)) { history in
                    Button {
                        openHistory(history)
                    } label: {
                        row(
                            title: history.title,
                            subtitle: history.url,
                            systemImage: "clock",
                            badge: history.visitCount > 1 ? "\(history.visitCount)x" : nil
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(16)
        .iosGlassContainer(theme, cornerRadius: 20)
    }

    private func sectionHeader(title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        HStack {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .foregroundStyle(theme.textPrimary)

            Spacer()

            Button(action: action) {
                Image(systemName: "slider.horizontal.3")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(theme.textSecondary)
                    .frame(width: 30, height: 30)
                    .background(theme.surfaceSecondary, in: Circle())
            }
        }
    }

    private func row(title: String, subtitle: String, systemImage: String, badge: String?) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.headline)
                .foregroundStyle(theme.brandPrimary)
                .frame(width: 34, height: 34)
                .background(theme.surfaceSecondary, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(theme.textPrimary)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(theme.textSecondary)
                    .lineLimit(1)
            }

            Spacer()

            if let badge {
                Text(badge)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(theme.brandPrimary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(theme.surfaceSecondary, in: Capsule())
            }
        }
        .padding(12)
        .background(theme.backgroundSecondary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func openNewTab() {
        let tab = browser.openNewTab(urlString: "")
        addressText = tab.urlString
        isShowingBrowser = true
    }

    private func openAddress() {
        let trimmed = addressText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if IOSSearchEngine.looksLikeURL(trimmed) {
            openURLString(trimmed)
        } else {
            let query = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? trimmed
            openURLString(searchEngine.searchURL(for: query))
        }
    }

    private func openURLString(_ urlString: String) {
        let tab = browser.openNewTab(urlString: urlString)
        addressText = tab.urlString
        isShowingBrowser = true
    }

    private func openTab(_ tab: IOSBrowserTab) {
        browser.select(tab.id)
        addressText = tab.urlString
        isShowingBrowser = true
    }

    private func openRecord(_ record: IOSAPIRecord) {
        record.lastOpenedAt = .now
        if record.method.uppercased() == "GET" {
            openURLString(record.url)
        } else {
            apiClientRecord = record
        }
    }

    private func openHistory(_ history: IOSWebHistoryRecord) {
        openURLString(history.url)
    }

    private func recordBadge(_ record: IOSAPIRecord) -> String? {
        let method = record.method.uppercased()
        if let provider = record.provider {
            return "\(method) · \(provider)"
        }
        return method
    }

    private func saveLatestHistory() {
        guard let page = browser.latestVisitedPage else { return }
        if let existing = historyRecords.first(where: { $0.url == page.url.absoluteString }) {
            existing.title = page.title
            existing.visitedAt = page.visitedAt
            existing.visitCount += 1
        } else {
            modelContext.insert(IOSWebHistoryRecord(
                title: page.title,
                url: page.url.absoluteString,
                visitedAt: page.visitedAt
            ))
        }
    }
}

@available(iOS 18.0, *)
private struct IOSBrowserView: View {
    @ObservedObject var browser: IOSBrowserStore
    @Environment(\.themeTokens) private var theme
    @Environment(\.modelContext) private var modelContext

    @State private var addressText = ""
    @State private var isShowingAddressBar = false
    @State private var isShowingSaveToast = false

    @StateObject private var translator = PageTranslator()

    var body: some View {
        ZStack {
            theme.backgroundSecondary
                .ignoresSafeArea()

            if let currentTab = browser.currentTab {
                IOSBrowserWebView(webView: currentTab.webView)
                    .ignoresSafeArea(.container, edges: [.top, .bottom])
                    .background(Color(.systemBackground))
                    .overlay(alignment: .top) {
                        if currentTab.isLoading {
                            ProgressView(value: currentTab.estimatedProgress)
                                .progressViewStyle(.linear)
                                .tint(theme.brandPrimary)
                        }
                    }
            } else {
                ContentUnavailableView("No Tabs", systemImage: "safari")
            }

            // Translation progress banner
            if translator.isTranslating {
                VStack {
                    Spacer()
                    HStack(spacing: 10) {
                        ProgressView()
                            .tint(.white)
                        Text(translator.progress.isEmpty ? "Translating..." : translator.progress)
                            .font(.caption)
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(Color.black.opacity(0.75)))
                    .padding(.bottom, 80)
                }
                .allowsHitTesting(false)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .animation(.easeInOut, value: translator.isTranslating)
            }

            if isShowingSaveToast {
                VStack(spacing: 18) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 56, weight: .semibold))
                        .foregroundStyle(.white)

                    Text("Saved")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.white)
                }
                .frame(width: 220, height: 220)
                .background(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(Color.black.opacity(0.82))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.28), radius: 24, y: 12)
                .transition(.scale(scale: 0.96).combined(with: .opacity))
                .allowsHitTesting(false)
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if isShowingAddressBar {
                addressBar
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
                    .background(.regularMaterial)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .navigationTitle(browser.currentTitle ?? "WebKit")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .toolbarRole(.browser)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    if isShowingAddressBar {
                        loadAddress()
                    } else {
                        addressText = browser.currentTab?.urlString ?? addressText
                        withAnimation(.easeInOut(duration: 0.18)) {
                            isShowingAddressBar = true
                        }
                    }
                } label: {
                    if isShowingAddressBar {
                        Label("Go", systemImage: "arrow.right.circle.fill")
                    } else {
                        Image(systemName: "magnifyingglass")
                    }
                }
                .disabled(isShowingAddressBar && addressText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            ToolbarItemGroup(placement: .bottomBar) {
                browserBackButton
                browserForwardButton
                Spacer()
                browserReloadButton
                browserMoreMenu
            }
        }
        .onReceive(browser.$selectedTabID) { _ in
            addressText = browser.currentTab?.urlString ?? ""
        }
        .onAppear {
            addressText = browser.currentTab?.urlString ?? ""
        }
        .onDisappear {
            browser.currentTab?.webView.stopLoading()
            translator.resetState()
        }
        .onChange(of: browser.selectedTabID) {
            translator.resetState()
        }
        .background(TranslationBridgeView(translator: translator))
        .animation(.spring(response: 0.24, dampingFraction: 0.9), value: isShowingSaveToast)
    }

    // MARK: - Toolbar Items

    private var browserBackButton: some View {
        Menu {
            ForEach(Array((browser.currentTab?.backList.reversed() ?? []).enumerated()), id: \.offset) { _, item in
                Button(item.title ?? item.url.absoluteString) {
                    browser.currentTab?.webView.go(to: item)
                }
            }
        } label: {
            Image(systemName: "chevron.backward")
        } primaryAction: {
            browser.goBack()
        }
        .disabled(!(browser.currentTab?.canGoBack ?? false))
    }

    private var browserForwardButton: some View {
        Menu {
            ForEach(Array((browser.currentTab?.forwardList ?? []).enumerated()), id: \.offset) { _, item in
                Button(item.title ?? item.url.absoluteString) {
                    browser.currentTab?.webView.go(to: item)
                }
            }
        } label: {
            Image(systemName: "chevron.forward")
        } primaryAction: {
            browser.goForward()
        }
        .disabled(!(browser.currentTab?.canGoForward ?? false))
    }

    private var browserReloadButton: some View {
        Button {
            browser.reload()
        } label: {
            Image(systemName: "arrow.clockwise")
        }
        .disabled(browser.currentURL == nil)
    }

    private var browserMoreMenu: some View {
        Menu {
            Button {
                saveCurrentPage()
            } label: {
                Label("save", systemImage: "arrow.forward.folder.fill")
            }
            .disabled(browser.latestAPIRequest == nil)

            Divider()

            if translator.isTranslated {
                Button {
                    if let webView = browser.currentTab?.webView {
                        Task { await translator.restore(webView: webView) }
                    }
                } label: {
                    Label("show_original", systemImage: "textformat")
                }
            } else {
                Button {
                    translator.prepareForTranslation(webView: browser.currentTab?.webView)
                    translator.triggerTranslation()
                } label: {
                    Label("translate_to_chinese", systemImage: "character.book.closed")
                }
                .disabled(translator.isTranslating)
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
    }

    private var addressBar: some View {
        TextField("Search or enter website name", text: $addressText)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .keyboardType(.URL)
            .submitLabel(.go)
            .onSubmit {
                loadAddress()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .iosGlassContainer(theme, cornerRadius: 14)
    }

    private func loadAddress() {
        browser.load(addressText)
        withAnimation(.easeInOut(duration: 0.18)) {
            isShowingAddressBar = false
        }
    }

    private func saveCurrentPage() {
        guard let apiRequest = browser.latestAPIRequest else { return }
        let record = IOSAPIRecord(
            title: apiRequest.title,
            url: apiRequest.url.absoluteString,
            method: apiRequest.method,
            requestType: apiRequest.type,
            headers: apiRequest.headers,
            body: apiRequest.body,
            provider: inferredProvider(from: apiRequest.url),
            tags: [apiRequest.type, apiRequest.method]
        )
        modelContext.insert(record)
        showSaveToast()
    }

    private func showSaveToast() {
        withAnimation {
            isShowingSaveToast = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.25) {
            withAnimation {
                isShowingSaveToast = false
            }
        }
    }

    private func inferredProvider(from url: URL) -> String? {
        let host = url.host?.lowercased() ?? ""
        if host.contains("openai") {
            return "OpenAI"
        }
        if host.contains("bigmodel") || host.contains("zhipu") || host.contains("glm") {
            return "GLM"
        }
        return nil
    }
}

@available(iOS 18.0, *)
private struct IOSTabsSheet: View {
    @ObservedObject var browser: IOSBrowserStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.themeTokens) private var theme

    var body: some View {
        NavigationStack {
            List {
                if browser.orderedTabs.isEmpty {
                    Section {
                        ContentUnavailableView(
                            "No Tabs yet",
                            systemImage: "square.on.square.dashed",
                            description: Text("Use Quick Open or the top-right + button to create a new tab.")
                        )
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 48, leading: 20, bottom: 48, trailing: 20))
                    }
                } else {
                    ForEach(browser.orderedTabs) { tab in
                        Button {
                            browser.select(tab.id)
                            dismiss()
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(tab.title)
                                    .font(.headline)
                                    .foregroundStyle(theme.textPrimary)
                                Text(tab.urlString)
                                    .font(.caption)
                                    .foregroundStyle(theme.textSecondary)
                                    .lineLimit(1)
                            }
                        }
                        .swipeActions {
                            Button {
                                browser.togglePin(tab.id)
                            } label: {
                                Label(tab.isPinned ? "Unpin" : "Pin", systemImage: tab.isPinned ? "pin.slash" : "pin")
                            }
                            .tint(.orange)

                            Button(role: .destructive) {
                                browser.close(tab.id)
                            } label: {
                                Label("Close", systemImage: "trash")
                            }
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.clear)
            .toolbarBackground(.hidden, for: .navigationBar)
            .navigationTitle("Tabs")
            .toolbar(.hidden, for: .tabBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        browser.openNewTab(urlString: "")
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
        }
    }
}

@available(iOS 18.0, *)
private struct IOSAPIRecordsSheet: View {
    let records: [IOSAPIRecord]
    let openRecord: (IOSAPIRecord) -> Void

    var body: some View {
        NavigationStack {
            List {
                IOSAPIRecordsListView(records: records, openRecord: openRecord)
            }
            .scrollContentBackground(.hidden)
            .background(Color.clear)
            .toolbarBackground(.hidden, for: .navigationBar)
            .navigationTitle("API Records")
            .toolbar(.hidden, for: .tabBar)
        }
    }
}

@available(iOS 18.0, *)
private struct IOSHistoryRecordsView: View {
    let records: [IOSWebHistoryRecord]
    let openHistory: (IOSWebHistoryRecord) -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.themeTokens) private var theme
    @EnvironmentObject private var themeManager: IOSThemeManager

    var body: some View {
        List {
            if records.isEmpty {
                Section {
                    ContentUnavailableView(
                        "No History yet",
                        systemImage: "clock.arrow.circlepath",
                        description: Text("Pages you open in WebKit will appear here.")
                    )
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 48, leading: 20, bottom: 48, trailing: 20))
                }
            } else {
                ForEach(records) { record in
                    Button {
                        openHistory(record)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(record.title)
                                .foregroundStyle(theme.textPrimary)
                            Text(record.url)
                                .font(.caption)
                                .foregroundStyle(theme.textSecondary)
                                .lineLimit(1)
                            Text(themeManager.formatTime(date: record.visitedAt, dateStyle: .abbreviated))
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(theme.brandPrimary)
                        }
                    }
                    .swipeActions {
                        Button(role: .destructive) {
                            modelContext.delete(record)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.clear)
        .toolbarBackground(.hidden, for: .navigationBar)
        .navigationTitle("History")
        .toolbar(.hidden, for: .tabBar)
    }
}

@available(iOS 18.0, *)
private struct IOSBrowserWebView: UIViewRepresentable {
    let webView: WKWebView

    func makeUIView(context: Context) -> WKWebView {
        webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

final class IOSBrowserStore: ObservableObject {
    @Published var tabs: [IOSBrowserTab] = []
    @Published var selectedTabID: UUID?

    private var tabSubscriptions: [UUID: AnyCancellable] = [:]
    private var pendingTab: IOSBrowserTab?

    var currentTab: IOSBrowserTab? {
        if let pending = pendingTab, selectedTabID == pending.id {
            return pending
        }
        return tabs.first(where: { $0.id == selectedTabID }) ?? tabs.first
    }

    var currentURL: URL? {
        currentTab?.webView.url
    }

    var currentTitle: String? {
        currentTab?.title
    }

    var latestAPIRequest: IOSCapturedAPIRequest? {
        currentTab?.apiRequests.last
    }

    var latestVisitedPage: IOSVisitedPage? {
        currentTab?.latestVisitedPage
    }

    var orderedTabs: [IOSBrowserTab] {
        tabs.sorted { lhs, rhs in
            if lhs.isPinned != rhs.isPinned {
                return lhs.isPinned && !rhs.isPinned
            }
            return lhs.createdAt < rhs.createdAt
        }
    }

    @discardableResult
    func openNewTab(urlString: String) -> IOSBrowserTab {
        let tab = IOSBrowserTab(urlString: urlString)
        observe(tab)

        if urlString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            pendingTab = tab
        } else {
            tabs.append(tab)
        }

        selectedTabID = tab.id
        return tab
    }

    func select(_ id: UUID) {
        selectedTabID = id
    }

    func close(_ id: UUID) {
        if let pending = pendingTab, pending.id == id {
            pendingTab = nil
            selectedTabID = tabs.last?.id
            return
        }

        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        tabs.remove(at: index)
        tabSubscriptions.removeValue(forKey: id)

        if selectedTabID == id {
            selectedTabID = tabs.indices.contains(index) ? tabs[index].id : tabs.last?.id
        }
    }

    func load(_ input: String) {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)

        if let pending = pendingTab, selectedTabID == pending.id {
            pending.load(input)
            if !trimmed.isEmpty {
                pendingTab = nil
                tabs.append(pending)
            }
            return
        }

        currentTab?.load(input)
    }

    func goBack() {
        currentTab?.webView.goBack()
    }

    func goForward() {
        currentTab?.webView.goForward()
    }

    func reload() {
        currentTab?.webView.reload()
    }

    func togglePin(_ id: UUID) {
        guard let tab = tabs.first(where: { $0.id == id }) else { return }
        tab.isPinned.toggle()
    }

    private func observe(_ tab: IOSBrowserTab) {
        tabSubscriptions[tab.id] = tab.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
    }
}

struct IOSCapturedAPIRequest: Identifiable, Equatable {
    let id = UUID()
    let type: String
    let method: String
    let url: URL
    let headers: String
    let body: String

    var title: String {
        "\(method) \(url.host ?? url.absoluteString)"
    }

    static func == (lhs: IOSCapturedAPIRequest, rhs: IOSCapturedAPIRequest) -> Bool {
        lhs.type == rhs.type
            && lhs.method == rhs.method
            && lhs.url == rhs.url
            && lhs.headers == rhs.headers
            && lhs.body == rhs.body
    }
}

struct IOSVisitedPage: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let url: URL
    let visitedAt: Date
}

final class IOSBrowserTab: NSObject, ObservableObject, Identifiable, WKNavigationDelegate, WKScriptMessageHandler {
    let id = UUID()
    let createdAt = Date()
    let webView: WKWebView

    @Published var title = "New Tab"
    @Published var urlString = ""
    @Published var isLoading = false
    @Published var estimatedProgress: Double = 0
    @Published var canGoBack = false
    @Published var canGoForward = false
    @Published var apiRequests: [IOSCapturedAPIRequest] = []
    @Published var latestVisitedPage: IOSVisitedPage?
    @Published var isPinned = false

    private var observations: [NSKeyValueObservation] = []

    var backList: [WKBackForwardListItem] {
        webView.backForwardList.backList
    }

    var forwardList: [WKBackForwardListItem] {
        webView.backForwardList.forwardList
    }

    init(urlString: String) {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()

        webView.navigationDelegate = self
        installAPIRecorder()
        wireObservers()
        load(urlString)
    }

    deinit {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "devBarAPIRecord")
        observations.forEach { $0.invalidate() }
    }

    func load(_ input: String) {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let resolvedURL: URL?
        if let directURL = URL(string: trimmed), directURL.scheme != nil {
            resolvedURL = directURL
        } else if let httpsURL = URL(string: "https://\(trimmed)") {
            resolvedURL = httpsURL
        } else {
            resolvedURL = nil
        }

        guard let url = resolvedURL else { return }
        webView.load(URLRequest(url: url))
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard let url = webView.url else { return }
        let pageTitle = webView.title?.trimmingCharacters(in: .whitespacesAndNewlines)
        latestVisitedPage = IOSVisitedPage(
            title: pageTitle?.isEmpty == false ? pageTitle! : url.host ?? url.absoluteString,
            url: url,
            visitedAt: .now
        )
    }

    private func wireObservers() {
        observations = [
            webView.observe(\.title, options: [.initial, .new]) { [weak self] webView, _ in
                DispatchQueue.main.async {
                    self?.title = webView.title?.isEmpty == false ? webView.title! : "New Tab"
                }
            },
            webView.observe(\.url, options: [.initial, .new]) { [weak self] webView, _ in
                DispatchQueue.main.async {
                    self?.urlString = webView.url?.absoluteString ?? ""
                }
            },
            webView.observe(\.isLoading, options: [.initial, .new]) { [weak self] webView, _ in
                DispatchQueue.main.async {
                    self?.isLoading = webView.isLoading
                }
            },
            webView.observe(\.estimatedProgress, options: [.initial, .new]) { [weak self] webView, _ in
                DispatchQueue.main.async {
                    self?.estimatedProgress = webView.estimatedProgress
                }
            },
            webView.observe(\.canGoBack, options: [.initial, .new]) { [weak self] webView, _ in
                DispatchQueue.main.async {
                    self?.canGoBack = webView.canGoBack
                }
            },
            webView.observe(\.canGoForward, options: [.initial, .new]) { [weak self] webView, _ in
                DispatchQueue.main.async {
                    self?.canGoForward = webView.canGoForward
                }
            },
        ]
    }

    private func installAPIRecorder() {
        let script = """
        (function() {
            if (window.__devBarAPIRecorderInstalled) { return; }
            window.__devBarAPIRecorderInstalled = true;

            function resolveURL(input) {
                if (typeof input === "string") { return input; }
                if (input && input.url) { return input.url; }
                return String(input || "");
            }

            function normalizeHeaders(headers) {
                var output = {};
                try {
                    if (!headers) { return output; }
                    if (headers.forEach) {
                        headers.forEach(function(value, key) { output[key] = value; });
                        return output;
                    }
                    Object.keys(headers).forEach(function(key) { output[key] = headers[key]; });
                } catch (_) {}
                return output;
            }

            function post(type, method, url, headers, body) {
                try {
                    var resolvedURL = new URL(resolveURL(url), document.baseURI).href;
                    window.webkit.messageHandlers.devBarAPIRecord.postMessage({
                        type: type,
                        method: method || "GET",
                        url: resolvedURL,
                        headers: normalizeHeaders(headers),
                        body: typeof body === "string" ? body : ""
                    });
                } catch (_) {}
            }

            var originalFetch = window.fetch;
            if (originalFetch) {
                window.fetch = function(input, init) {
                    var method = (init && init.method) || (input && input.method) || "GET";
                    var headers = (init && init.headers) || (input && input.headers) || {};
                    var body = init && init.body;
                    post("Fetch", method, input, headers, body);
                    return originalFetch.apply(this, arguments);
                };
            }

            var originalOpen = XMLHttpRequest.prototype.open;
            XMLHttpRequest.prototype.open = function(method, url) {
                this.__devBarMethod = method || "GET";
                this.__devBarURL = url;
                this.__devBarHeaders = {};
                return originalOpen.apply(this, arguments);
            };

            var originalSetRequestHeader = XMLHttpRequest.prototype.setRequestHeader;
            XMLHttpRequest.prototype.setRequestHeader = function(key, value) {
                this.__devBarHeaders = this.__devBarHeaders || {};
                this.__devBarHeaders[key] = value;
                return originalSetRequestHeader.apply(this, arguments);
            };

            var originalSend = XMLHttpRequest.prototype.send;
            XMLHttpRequest.prototype.send = function(body) {
                post("XHR", this.__devBarMethod || "GET", this.__devBarURL || "", this.__devBarHeaders || {}, body);
                return originalSend.apply(this, arguments);
            };
        })();
        """
        let userScript = WKUserScript(source: script, injectionTime: .atDocumentStart, forMainFrameOnly: false)
        webView.configuration.userContentController.addUserScript(userScript)
        webView.configuration.userContentController.add(IOSWeakScriptMessageHandler(delegate: self), name: "devBarAPIRecord")
    }


    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard
            message.name == "devBarAPIRecord",
            let body = message.body as? [String: Any],
            let type = body["type"] as? String,
            ["Fetch", "XHR"].contains(type),
            let method = body["method"] as? String,
            let urlString = body["url"] as? String,
            let url = URL(string: urlString)
        else {
            return
        }

        let request = IOSCapturedAPIRequest(
            type: type,
            method: method.uppercased(),
            url: url,
            headers: Self.encodedHeaders(from: body["headers"]),
            body: body["body"] as? String ?? ""
        )

        DispatchQueue.main.async {
            guard self.apiRequests.last != request else { return }
            self.apiRequests.append(request)
        }
    }

    private static func encodedHeaders(from value: Any?) -> String {
        guard
            let headers = value as? [String: Any],
            JSONSerialization.isValidJSONObject(headers),
            let data = try? JSONSerialization.data(withJSONObject: headers, options: [.prettyPrinted, .sortedKeys]),
            let string = String(data: data, encoding: .utf8)
        else {
            return ""
        }

        return string
    }
}

private enum IOSSearchEngine: String, CaseIterable {
    case google
    case baidu

    var localizedName: String {
        switch self {
        case .google: return "Google"
        case .baidu: return "Baidu"
        }
    }

    var systemImage: String {
        switch self {
        case .google: return "globe"
        case .baidu: return "pawprint.fill"
        }
    }

    func searchURL(for query: String) -> String {
        switch self {
        case .google: return "https://www.google.com/search?q=\(query)"
        case .baidu: return "https://www.baidu.com/s?wd=\(query)"
        }
    }

    static func looksLikeURL(_ input: String) -> Bool {
        if URL(string: input)?.scheme != nil { return true }
        if input.contains("://") { return true }

        let host = input
            .components(separatedBy: "/").first?
            .components(separatedBy: ":").first ?? input
        let domainPattern = #"^([a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}$"#
        if host.range(of: domainPattern, options: .regularExpression) != nil { return true }
        if host.range(of: #"^\d{1,3}(\.\d{1,3}){3}$"#, options: .regularExpression) != nil { return true }

        return false
    }
}


@available(iOS 18.0, *)
private struct TranslationBridgeView: View {
    @ObservedObject var translator: PageTranslator

    var body: some View {
        Color.clear
            .translationTask(translator.translationConfig) { session in
                await translator.translate(with: session)
            }
    }
}

private final class IOSWeakScriptMessageHandler: NSObject, WKScriptMessageHandler {
    weak var delegate: WKScriptMessageHandler?

    init(delegate: WKScriptMessageHandler) {
        self.delegate = delegate
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        delegate?.userContentController(userContentController, didReceive: message)
    }
}
