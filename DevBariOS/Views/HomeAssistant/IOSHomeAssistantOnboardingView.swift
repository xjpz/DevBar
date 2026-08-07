import DevBarCore
import SwiftUI

struct IOSHomeAssistantOnboardingView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.themeTokens) private var theme
    @ObservedObject var model: IOSHomeAssistantViewModel
    let isSettings: Bool

    @State private var externalURL = ""
    @State private var internalURL = ""
    @State private var internalSSIDs = [""]
    @State private var token = ""
    @State private var aiAnalysisEnabled = false
    @State private var showsDiagnosticEntities = false
    @State private var isSaving = false
    @State private var errorMessage: String?
    @FocusState private var focusedField: Field?

    var body: some View {
        Form {
            if !isSettings {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Image(systemName: "house.fill")
                            .font(.system(size: 40, weight: .semibold))
                            .foregroundStyle(theme.info)
                        Text("连接 Home Assistant")
                            .font(theme.appFont.font(.title2, weight: .bold))
                        Text("自动读取区域、设备和实体，生成适合 iPhone 的家庭控制台。")
                            .font(theme.bodyFont)
                            .foregroundStyle(theme.textSecondary)
                    }
                    .padding(.vertical, 8)
                }
            }

            Section {
                TextField("公网 HTTPS 地址", text: $externalURL)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focusedField, equals: .externalURL)
                    .accessibilityIdentifier("ios.homeAssistant.externalURL")

                TextField("内网地址（可选）", text: $internalURL)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focusedField, equals: .internalURL)
                    .accessibilityIdentifier("ios.homeAssistant.internalURL")

                ForEach(internalSSIDs.indices, id: \.self) { index in
                    HStack {
                        TextField("家庭 Wi-Fi SSID \(index + 1)", text: $internalSSIDs[index])
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .focused($focusedField, equals: .internalSSID(index))
                            .accessibilityIdentifier("ios.homeAssistant.internalSSID.\(index)")

                        if internalSSIDs.count > 1 {
                            Button(role: .destructive) {
                                internalSSIDs.remove(at: index)
                            } label: {
                                Image(systemName: "minus.circle.fill")
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("删除 SSID \(index + 1)")
                        }
                    }
                }

                if internalSSIDs.count < 3 {
                    Button {
                        internalSSIDs.append("")
                    } label: {
                        Label("添加家庭 Wi-Fi", systemImage: "plus.circle")
                    }
                }

                Button {
                    focusedField = nil
                    Task { await detectCurrentSSID() }
                } label: {
                    Label("使用当前 Wi-Fi", systemImage: "wifi")
                }
            } header: {
                Text("连接地址")
            } footer: {
                Text("最多保存 3 个家庭 SSID。当前 Wi-Fi 与其中任意一个精确匹配时才尝试内网；不匹配、无法读取或使用蜂窝网络时直接连接公网。")
            }

            Section {
                SecureField("Long-Lived Access Token", text: $token)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.system(.body, design: .monospaced))
                    .focused($focusedField, equals: .token)
                    .accessibilityIdentifier("ios.homeAssistant.token")
            } header: {
                Text("认证")
            } footer: {
                Text("Token 仅保存在本机 Keychain，不会写入日志、iCloud 或发送给 AI。")
            }

            if internalURL.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().hasPrefix("http://") {
                Section {
                    Label("内网 HTTP 没有 TLS 加密。同一 Wi‑Fi 中的攻击者可能截获 Token，建议为 Home Assistant 配置 HTTPS。", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(theme.warning)
                }
            }

            Section {
                Toggle("允许 AI 整理控制台", isOn: $aiAnalysisEnabled)
                Toggle("显示诊断实体", isOn: $showsDiagnosticEntities)
            } header: {
                Text("显示与 AI")
            } footer: {
                Text("AI 默认关闭。开启后只发送房间/实体显示名、Domain、Device Class 和能力枚举，不发送地址、Token 或坐标。")
            }

            if isSettings {
                Section {
                    if let savedAt = model.cacheSavedAt {
                        LabeledContent("设备缓存") {
                            Text(savedAt, format: .dateTime.month().day().hour().minute())
                                .foregroundStyle(theme.textSecondary)
                        }
                    } else {
                        LabeledContent("设备缓存", value: "尚未保存")
                    }

                    Button("清除设备缓存", role: .destructive) {
                        model.clearSnapshotCache()
                    }
                    .disabled(model.cacheSavedAt == nil)
                } header: {
                    Text("本地设备")
                } footer: {
                    Text("缓存只用于快速展示上次的设备卡片，不包含 Token，也不会同步到 iCloud。清除后下次进入将重新读取全部设备。")
                }
            }

            Section {
                Button {
                    Task { await save() }
                } label: {
                    HStack {
                        if isSaving { ProgressView() }
                        Text(isSaving ? "正在连接…" : "保存并连接")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isSaving || externalURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                if isSettings {
                    Button("断开并清除配置", role: .destructive) {
                        model.clearConfiguration()
                        dismiss()
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background((theme.isGeek ? Color.black : theme.backgroundSecondary).ignoresSafeArea())
        .navigationTitle(isSettings ? "Home Assistant 设置" : "Home Assistant")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if isSettings {
                ToolbarItem(placement: .cancellationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .alert("Home Assistant", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("好", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .onAppear(perform: load)
        .scrollDismissesKeyboard(.interactively)
    }

    private func load() {
        externalURL = model.settings.externalURL
        internalURL = model.settings.internalURL
        internalSSIDs = model.settings.internalSSIDs.isEmpty
            ? [""]
            : Array(model.settings.internalSSIDs.prefix(3))
        token = model.token
        aiAnalysisEnabled = model.settings.aiAnalysisEnabled
        showsDiagnosticEntities = model.settings.showsDiagnosticEntities
        if !isSettings && externalURL.isEmpty { focusedField = .externalURL }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        do {
            try await model.saveAndConnect(
                externalURL: externalURL,
                internalURL: internalURL,
                internalSSIDs: internalSSIDs,
                token: token,
                aiAnalysisEnabled: aiAnalysisEnabled,
                showsDiagnosticEntities: showsDiagnosticEntities
            )
            if isSettings { dismiss() }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func detectCurrentSSID() async {
        if let ssid = await model.detectCurrentSSID() {
            if internalSSIDs.contains(ssid) { return }
            if let emptyIndex = internalSSIDs.firstIndex(where: {
                $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }) {
                internalSSIDs[emptyIndex] = ssid
            } else if internalSSIDs.count < 3 {
                internalSSIDs.append(ssid)
            } else {
                errorMessage = "最多只能保存 3 个家庭 Wi-Fi SSID，请先删除一个再添加。"
            }
        } else {
            errorMessage = "无法读取当前 Wi-Fi 名称。请在系统设置中允许 DevBar 使用位置，并开启精确位置；也可以手动填写 SSID。"
        }
    }

    private enum Field: Hashable { case externalURL, internalURL, internalSSID(Int), token }
}

struct IOSHomeAssistantSettingsView: View {
    @StateObject private var model = IOSHomeAssistantViewModel()

    var body: some View {
        IOSHomeAssistantOnboardingView(model: model, isSettings: true)
    }
}
