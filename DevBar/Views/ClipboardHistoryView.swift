import DevBarCore
import SwiftUI

struct ClipboardHistoryView: View {
    @ObservedObject var controller: MacClipboardController
    @State private var query = ""
    @State private var pinnedOnly = false
    @State private var selection: UUID?
    @State private var settings = false
    @State private var clearAll: Bool?
    @FocusState private var searchFocused: Bool

    private var entries: [ClipboardEntry] {
        controller.snapshot.entries.filter {
            (!pinnedOnly || $0.isPinned) && (query.isEmpty || $0.text.localizedCaseInsensitiveContains(query))
        }
    }
    private var selected: ClipboardEntry? { entries.first { $0.id == selection } }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label(LocalizedStringKey(controller.statusKey), systemImage: "doc.on.clipboard")
                Spacer()
                Menu("clipboard_pause") {
                    Button("clipboard_pause_15") { controller.pause(for: 900) }
                    Button("clipboard_pause_hour") { controller.pause(for: 3600) }
                    Button("clipboard_pause_manual") { controller.pause(for: 100 * 365 * 86_400) }
                    Button("clipboard_resume") { controller.pause(for: nil) }
                }
                Button { settings.toggle() } label: { Image(systemName: "gearshape") }
                    .help("clipboard_settings")
            }.padding()
            if let error = controller.error { Text(error).foregroundStyle(.red).padding(.horizontal) }
            if controller.statusKey == "clipboard_status_permission" {
                HStack {
                    Text("clipboard_permission_help").font(.caption)
                    Button("clipboard_permission_action") { controller.requestPermission() }
                }.padding(.horizontal).padding(.bottom, 8)
            }
            HStack {
                TextField("clipboard_search", text: $query).focused($searchFocused)
                Toggle("clipboard_pinned", isOn: $pinnedOnly).toggleStyle(.button)
            }.padding(.horizontal).padding(.bottom)
            HSplitView {
                List(entries, selection: $selection) { entry in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Image(systemName: entry.kind == .url ? "link" : "text.alignleft")
                            Text(entry.preview).lineLimit(2)
                            if entry.isPinned { Image(systemName: "pin.fill").foregroundStyle(.secondary) }
                        }
                        Text(entry.lastCopiedAt, style: .relative).font(.caption).foregroundStyle(.secondary)
                    }
                    .tag(entry.id)
                    .contextMenu {
                        Button("clipboard_copy") { controller.copy(entry) }
                        Button(LocalizedStringKey(entry.isPinned ? "clipboard_unpin" : "clipboard_pin")) { Task { await controller.pin(entry) } }
                        Button("clipboard_delete", role: .destructive) { Task { await controller.remove(entry) } }
                    }
                }.frame(minWidth: 250, idealWidth: 320)
                if let entry = selected {
                    VStack(alignment: .leading) {
                        HStack {
                            Button("clipboard_copy") { controller.copy(entry) }.keyboardShortcut(.return, modifiers: [])
                            Button(LocalizedStringKey(entry.isPinned ? "clipboard_unpin" : "clipboard_pin")) { Task { await controller.pin(entry) } }
                            Spacer()
                            Button("clipboard_delete", role: .destructive) { Task { await controller.remove(entry) } }
                        }
                        ScrollView { Text(entry.text).font(.system(.body, design: .monospaced)).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.top) }
                    }.padding().frame(minWidth: 320, maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ContentUnavailableView("clipboard_select", systemImage: "doc.on.clipboard",
                                           description: Text("clipboard_retention"))
                        .frame(minWidth: 320, maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            HStack {
                Text("\(controller.snapshot.entries.count) / 600").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Menu("clipboard_clear") {
                    Button("clipboard_clear_unpinned", role: .destructive) { clearAll = false }
                    Button("clipboard_clear_all", role: .destructive) { clearAll = true }
                }
            }.padding(10)
        }
        .frame(minWidth: 720, minHeight: 480)
        .background {
            Button("") { searchFocused = true }.keyboardShortcut("f", modifiers: .command).hidden()
        }
        .sheet(isPresented: $settings) { ClipboardSettingsView(controller: controller) }
        .confirmationDialog("clipboard_clear_confirm", isPresented: Binding(
            get: { clearAll != nil }, set: { if !$0 { clearAll = nil } }
        )) {
            Button("clipboard_delete", role: .destructive) {
                let all = clearAll ?? false; clearAll = nil
                Task { await controller.clear(includingPinned: all) }
            }
        }
        .task { await controller.reload() }
    }
}
