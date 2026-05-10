// SettingsFinder.swift
// DevBar

import SwiftUI

struct SettingsFinder: View {
    @State private var preferredTerminal: TerminalApp = FinderSyncPreferences.shared.preferredTerminal
    @State private var enableTxt: Bool = FinderSyncPreferences.shared.enableTxt
    @State private var enableSh: Bool = FinderSyncPreferences.shared.enableSh
    @State private var enableMd: Bool = FinderSyncPreferences.shared.enableMd
    @State private var enableDocx: Bool = FinderSyncPreferences.shared.enableDocx
    @State private var enableXlsx: Bool = FinderSyncPreferences.shared.enableXlsx
    @State private var enablePptx: Bool = FinderSyncPreferences.shared.enablePptx
    @State private var enableCopyPath: Bool = FinderSyncPreferences.shared.enableCopyPath

    var body: some View {
        Form {
            Section {
                HStack {
                    Text("默认终端")
                    Spacer()
                    Picker("", selection: $preferredTerminal) {
                        ForEach(TerminalApp.allCases) { app in
                            Text(app.displayName).tag(app)
                        }
                    }
                    .pickerStyle(.menu)
                }
                .onChange(of: preferredTerminal) { _, newValue in
                    FinderSyncPreferences.shared.preferredTerminal = newValue
                }

                Toggle("拷贝文件路径", isOn: $enableCopyPath)
                    .onChange(of: enableCopyPath) { _, newValue in
                        FinderSyncPreferences.shared.enableCopyPath = newValue
                    }
            }

            Section("文件类型") {
                Toggle("Text File (.txt)", isOn: $enableTxt)
                    .onChange(of: enableTxt) { _, newValue in
                        FinderSyncPreferences.shared.enableTxt = newValue
                    }
                Toggle("Shell Script (.sh)", isOn: $enableSh)
                    .onChange(of: enableSh) { _, newValue in
                        FinderSyncPreferences.shared.enableSh = newValue
                    }
                Toggle("Markdown (.md)", isOn: $enableMd)
                    .onChange(of: enableMd) { _, newValue in
                        FinderSyncPreferences.shared.enableMd = newValue
                    }
                Toggle("Word 文档 (.docx)", isOn: $enableDocx)
                    .onChange(of: enableDocx) { _, newValue in
                        FinderSyncPreferences.shared.enableDocx = newValue
                    }
                Toggle("Excel 表格 (.xlsx)", isOn: $enableXlsx)
                    .onChange(of: enableXlsx) { _, newValue in
                        FinderSyncPreferences.shared.enableXlsx = newValue
                    }
                Toggle("PowerPoint 演示 (.pptx)", isOn: $enablePptx)
                    .onChange(of: enablePptx) { _, newValue in
                        FinderSyncPreferences.shared.enablePptx = newValue
                    }
            }

            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text("使用说明")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("在 Finder 中右键即可使用这些功能。需在系统设置 > 扩展中启用 DevBar Finder Extension。")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }
}
