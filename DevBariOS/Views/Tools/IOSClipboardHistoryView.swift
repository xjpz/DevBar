import DevBarCore
import SwiftUI

struct IOSClipboardHistoryView: View {
    @EnvironmentObject private var appViewModel: IOSAppViewModel

    var body: some View {
        IOSClipboardContent(model: appViewModel.clipboard, relay: appViewModel.deviceRelayManager) {
            await appViewModel.prepareClipboard()
        }
    }
}

private struct ClipboardRefreshKey: Hashable {
    var ready: Bool
    var active: Bool
    var query: String
    var pinned: Bool
    var localID: String?
    var peerID: String?
}

private struct IOSClipboardContent: View {
    @ObservedObject var model: IOSClipboardViewModel
    @ObservedObject var relay: DeviceRelayManager
    let prepare: () async -> Void
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.themeTokens) private var theme
    @Environment(\.iosToolEntryContext) private var entryContext
    @State private var query = ""
    @State private var pinned = false
    @State private var ready = false

    private var refreshKey: ClipboardRefreshKey {
        ClipboardRefreshKey(ready: ready, active: scenePhase == .active, query: query, pinned: pinned,
                            localID: relay.localDeviceID, peerID: model.peer?.deviceId)
    }

    var body: some View {
        List {
            Section {
                if let peer = model.peer {
                    Label(peer.deviceName ?? "Mac", systemImage: "macbook")
                    Text(LocalizedStringKey(model.connectionKey)).foregroundStyle(.secondary)
                    if model.offline {
                        Label("clipboard_offline_cache", systemImage: "clock.arrow.circlepath")
                            .font(.caption).foregroundStyle(theme.warning)
                    }
                    if let updatedAt = model.updatedAt {
                        HStack {
                            Text("clipboard_updated")
                            Text(updatedAt, style: .relative)
                        }.font(.caption).foregroundStyle(.secondary)
                    }
                } else if model.offline && !model.summaries.isEmpty {
                    Label("Mac", systemImage: "macbook")
                    Label("clipboard_offline_cache", systemImage: "clock.arrow.circlepath")
                    Text("clipboard_cache_help").font(.caption).foregroundStyle(.secondary)
                } else {
                    NavigationLink { IOSMacRelayView() } label: {
                        Label("clipboard_connect_mac", systemImage: "qrcode.viewfinder")
                    }
                    Text("clipboard_not_paired").font(.caption).foregroundStyle(.secondary)
                }
            }
            if let error = model.error {
                Section { Text(error).foregroundStyle(theme.danger).font(.callout) }
            }
            Section {
                Picker("clipboard_filter", selection: $pinned) {
                    Text("clipboard_all").tag(false)
                    Text("clipboard_pinned").tag(true)
                }.pickerStyle(.segmented)
                if model.loading && model.summaries.isEmpty { ProgressView("clipboard_loading") }
                else if model.summaries.isEmpty {
                    ContentUnavailableView("clipboard_empty", systemImage: "doc.on.clipboard",
                                           description: Text(LocalizedStringKey(model.offline ? "clipboard_cache_help" : "clipboard_empty_help")))
                }
                ForEach(model.summaries) { summary in
                    HStack(spacing: 8) {
                        Button { Task { await model.open(summary) } } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Label(summary.preview, systemImage: summary.kind == .url ? "link" : "text.alignleft")
                                    .lineLimit(2).foregroundStyle(theme.textPrimary)
                                HStack(spacing: 6) {
                                    if summary.isPinned { Image(systemName: "pin.fill") }
                                    Text(summary.lastCopiedAt, style: .relative)
                                }.font(.caption).foregroundStyle(.secondary)
                            }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        }.buttonStyle(.borderless)
                        Button { Task { await model.open(summary, copy: true) } } label: {
                            Image(systemName: model.copiedID == summary.id ? "checkmark" : "doc.on.doc")
                                .frame(width: 44, height: 44)
                        }.buttonStyle(.borderless)
                            .accessibilityLabel(Text(LocalizedStringKey(model.copiedID == summary.id ? "clipboard_copied" : "clipboard_copy")))
                            .disabled(model.detailRequests >= 2)
                    }
                }
                if model.nextOffset != nil {
                    Button("clipboard_load_more") { Task { await model.refresh(loadMore: true) } }
                        .disabled(model.loading)
                }
            }
            if model.cacheEnabled {
                Section { Text("clipboard_cache_help").font(.caption).foregroundStyle(.secondary) }
            }
        }
        .scrollContentBackground(.hidden)
        .iosGeekScreenBackground(theme)
        .navigationTitle("clipboard_title")
        .iosToolTitleDisplayMode(entryContext)
        .toolbar(entryContext.tabBarVisibility, for: .tabBar)
        .iosToolNavigationChrome(theme, showsBackButton: entryContext.showsBackButton)
        .searchable(text: $query, prompt: Text(LocalizedStringKey(model.offline ? "clipboard_search_cache" : "clipboard_search_mac")))
        .refreshable { await model.refresh() }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("clipboard_refresh") { Task { await model.refresh() } }
                    Toggle("clipboard_cache_enabled", isOn: Binding(
                        get: { model.cacheEnabled }, set: { value in Task { await model.setCacheEnabled(value) } }
                    ))
                    Button("clipboard_clear_cache", role: .destructive) { Task { await model.discardCache() } }
                } label: { Image(systemName: "ellipsis").iosToolToolbarIcon(theme) }
                    .accessibilityLabel("clipboard_settings")
            }
        }
        .sheet(item: $model.detail) { entry in
            IOSClipboardDetailView(entry: entry, model: model)
        }
        .task { ready = true; await prepare() }
        .task(id: refreshKey) {
            guard ready, scenePhase == .active else { model.stop(); return }
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            await model.run(query: query, pinnedOnly: pinned)
        }
        .onDisappear { model.stop() }
        .accessibilityIdentifier("ios.clipboard.screen")
    }
}

private struct IOSClipboardDetailView: View {
    let entry: ClipboardEntry
    @ObservedObject var model: IOSClipboardViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(entry.text).font(.system(.body, design: .monospaced)).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading).padding()
            }
            .navigationTitle("clipboard_detail")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("clipboard_done") { dismiss() } }
                ToolbarItemGroup(placement: .primaryAction) {
                    if entry.kind == .url, let url = URL(string: entry.text) {
                        Link(destination: url) { Image(systemName: "safari") }.accessibilityLabel("clipboard_open_link")
                    }
                    Button { Task { await model.open(ClipboardSummary(entry), copy: true) } } label: {
                        Label(LocalizedStringKey(model.copiedID == entry.id ? "clipboard_copied" : "clipboard_copy"), systemImage: "doc.on.doc")
                    }.disabled(model.detailRequests >= 2)
                }
            }
        }
    }
}
