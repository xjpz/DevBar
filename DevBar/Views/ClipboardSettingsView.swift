import SwiftUI

struct ClipboardSettingsView: View {
    @ObservedObject var controller: MacClipboardController
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack {
            Form {
                Section {
                    Toggle("clipboard_record", isOn: Binding(get: { controller.recordingEnabled }, set: controller.setRecording))
                    Text("clipboard_record_help").font(.caption).foregroundStyle(.secondary)
                    Text("clipboard_retention").font(.caption).foregroundStyle(.secondary)
                }
                Section {
                    Toggle("clipboard_share", isOn: Binding(get: { controller.sharingEnabled }, set: controller.setSharing))
                    Text("clipboard_share_help").font(.caption).foregroundStyle(.secondary)
                    Text("clipboard_pause_help").font(.caption).foregroundStyle(.secondary)
                }
                Section("clipboard_exclusions") {
                    TextEditor(text: $controller.ignoredApps).font(.system(.body, design: .monospaced)).frame(height: 90)
                        .accessibilityLabel("clipboard_exclusions")
                    Toggle("clipboard_strict_source", isOn: $controller.strictSource)
                    Text("clipboard_sensitive_help").font(.caption).foregroundStyle(.secondary)
                }
                Section {
                    LabeledContent("clipboard_skipped", value: "\(controller.skippedCount)")
                    Button("clipboard_refresh") { Task { await controller.reload() } }
                }
            }.formStyle(.grouped)
            Button("clipboard_done") { dismiss() }.keyboardShortcut(.defaultAction).padding(.bottom)
        }.frame(width: 540, height: 600)
    }
}
