// SettingsWeChat.swift
// DevBar

import SwiftUI

struct SettingsWeChat: View {
    @ObservedObject var viewModel: WeChatViewModel
    @ObservedObject private var agentRouter: WeChatAgentRouter
    @ObservedObject private var approvalCoordinator: WeChatApprovalCoordinator
    @ObservedObject private var authorizedDirectoryStore: WeChatAuthorizedDirectoryStore
    @State private var showLoginSheet = false
    @State private var showAddAgent = false
    @State private var cwdAccessError: String?

    init(viewModel: WeChatViewModel) {
        self.viewModel = viewModel
        self.agentRouter = viewModel.agentRouter
        self.approvalCoordinator = viewModel.agentRouter.approvalCoordinator
        self.authorizedDirectoryStore = viewModel.agentRouter.authorizedDirectoryStore
    }

    var body: some View {
        Form {
            // Enable toggle
            Section {
                Toggle(isOn: $viewModel.isEnabled) {
                    HStack(spacing: 8) {
                        Image(systemName: "message.fill")
                            .foregroundStyle(.green)
                        Text("wechat_enable")
                    }
                }
            }

            // Connection status
            if viewModel.isEnabled {
                Section {
                    HStack {
                        Text("wechat_status")
                        Spacer()
                        statusView
                    }

                    if viewModel.connectionState.isConnected {
                        Button {
                            viewModel.restart()
                        } label: {
                            HStack {
                                Image(systemName: "arrow.clockwise")
                                Text("wechat_restart")
                            }
                        }
                    }
                }

                // Accounts
                Section {
                    if viewModel.authService.accounts.isEmpty {
                        HStack {
                            Spacer()
                            VStack(spacing: 8) {
                                Image(systemName: "qrcode")
                                    .font(.title2)
                                    .foregroundStyle(.secondary)
                                Text("wechat_no_accounts")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .padding(.vertical, 12)
                    } else {
                        ForEach(viewModel.authService.accounts, id: \.ilinkBotID) { account in
                            HStack {
                                Image(systemName: "circle.fill")
                                    .font(.caption2)
                                    .foregroundStyle(viewModel.connectionState.isConnected ? .green : .gray)
                                Text(account.ilinkBotID)
                                    .font(.system(.caption, design: .monospaced))
                                    .lineLimit(1)
                                Spacer()
                                Button {
                                    viewModel.authService.deleteAccount(account)
                                    if viewModel.hasAccounts {
                                        viewModel.restart()
                                    } else {
                                        viewModel.stop()
                                    }
                                } label: {
                                    Image(systemName: "trash")
                                        .foregroundStyle(.red)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    Button {
                        showLoginSheet = true
                    } label: {
                        Label("wechat_add_account", systemImage: "plus.circle")
                    }
                } header: {
                    Text("wechat_accounts")
                }

                // Agent config
                Section {
                    if hasProtectedWorkingDirectories {
                        Label("wechat_cwd_protected_notice", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.yellow)
                    }

                    if viewModel.agentRouter.agents.isEmpty {
                        HStack {
                            Spacer()
                            VStack(spacing: 4) {
                                Text("wechat_no_agents")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .padding(.vertical, 8)
                    } else {
                        Picker("wechat_default_agent", selection: $viewModel.defaultAgent) {
                            Text("None").tag("")
                            ForEach(viewModel.agentRouter.agents) { agent in
                                Text("\(agent.name) (\(agent.type.rawValue))").tag(agent.name)
                            }
                        }

                        ForEach(viewModel.agentRouter.agents) { agent in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Image(systemName: agentIcon(agent.type))
                                        .foregroundStyle(agent.type == .acp ? .purple : .blue)
                                        .frame(width: 20)
                                    Text(agent.name)
                                        .font(.caption)
                                    Spacer()
                                    Text(agent.type.rawValue.uppercased())
                                        .font(.caption2)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(agent.type == .acp ? Color.purple.opacity(0.15) : Color.secondary.opacity(0.15), in: RoundedRectangle(cornerRadius: 4))
                                    Button {
                                        viewModel.agentRouter.deleteAgent(agent)
                                    } label: {
                                        Image(systemName: "trash")
                                            .foregroundStyle(.red)
                                    }
                                    .buttonStyle(.plain)
                                }

                                if agent.type == .cli || agent.type == .acp {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("当前工作目录")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)

                                        HStack(spacing: 6) {
                                            cwdStatusLabel(for: agent)
                                            Spacer()
                                            Button {
                                                chooseWorkingDirectory(for: agent)
                                            } label: {
                                                Image(systemName: "folder")
                                            }
                                            .buttonStyle(.plain)
                                            .help(Text("选择当前工作目录，所选目录会加入远程可用目录"))

                                            if agent.cwd?.isEmpty == false {
                                                Button {
                                                    viewModel.agentRouter.updateAgentWorkingDirectory(agent, cwd: nil)
                                                    if viewModel.messageService.isRunning {
                                                        viewModel.restart()
                                                    }
                                                } label: {
                                                    Image(systemName: "xmark.circle")
                                                }
                                                .buttonStyle(.plain)
                                                .help(Text("wechat_cwd_use_default"))
                                            }
                                        }
                                    }

                                    Picker("授权", selection: approvalPolicyBinding(for: agent)) {
                                        ForEach(WeChatAgentRouter.AgentConfig.ApprovalPolicy.allCases) { policy in
                                            Text(policy.displayName).tag(policy)
                                        }
                                    }
                                    .font(.caption2)

                                    if agent.type == .cli && agent.effectiveApprovalPolicy == .wechatConfirm {
                                        Toggle(isOn: highRiskWechatApprovalBinding(for: agent)) {
                                            Text("高风险也允许微信确认")
                                        }
                                        .font(.caption2)
                                        .help(Text("提交代码、写文件、删除、安装、执行等高风险操作也可通过微信 Y 放行"))
                                    }
                                }
                            }
                        }
                    }

                    HStack {
                        Button {
                            showAddAgent = true
                        } label: {
                            Label("wechat_add_agent", systemImage: "plus.circle")
                        }

                        Spacer()

                        Button {
                            Task { await viewModel.detectAgents() }
                        } label: {
                            if viewModel.agentDetector.isScanning {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Label("wechat_scan_agents", systemImage: "wand.and.stars")
                            }
                        }
                    }
                } header: {
                    Text("wechat_agents")
                }

                Section {
                    Text("添加目录时会同时验证 DevBar 和外部 CLI 子进程访问权限。若目录位于文稿、桌面、下载或 iCloud，系统授权会在这里完成，避免远程首次访问才弹窗。")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Label {
                        Text("默认安全目录: \(WeChatWorkingDirectoryPolicy.ensureDefaultDirectory())")
                    } icon: {
                        Image(systemName: "folder")
                    }
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    if authorizedDirectoryStore.directories.isEmpty {
                        Text("未添加授权目录")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(authorizedDirectoryStore.directories) { directory in
                            HStack(spacing: 8) {
                                Image(systemName: directory.isStale ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                                    .foregroundStyle(directory.isStale ? .yellow : .green)
                                    .frame(width: 18)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(WeChatWorkingDirectoryPolicy.displayPath(directory.path))
                                        .font(.caption2)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                    if directory.isStale {
                                        Text("需重新授权")
                                            .font(.caption2)
                                            .foregroundStyle(.yellow)
                                    }
                                }

                                Spacer()

                                Button {
                                    authorizedDirectoryStore.removeDirectory(id: directory.id)
                                } label: {
                                    Image(systemName: "trash")
                                        .foregroundStyle(.red)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    Button {
                        addAuthorizedDirectory()
                    } label: {
                        Label("添加可切换目录", systemImage: "folder.badge.plus")
                    }
                } header: {
                    Text("远程可切换目录")
                }

                if !approvalCoordinator.pendingRequests.isEmpty {
                    Section {
                        ForEach(approvalCoordinator.pendingRequests) { request in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("\(request.agentName) · \(request.risk.displayName)")
                                        .font(.caption)
                                        .fontWeight(.medium)
                                    Spacer()
                                    Text(request.id)
                                        .font(.system(.caption2, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                }

                                Text(request.message)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)

                                Text(request.cwd ?? "未设置工作目录")
                                    .font(.system(.caption2, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)

                                HStack {
                                    Button("拒绝") {
                                        _ = approvalCoordinator.resolve(
                                            id: request.id,
                                            userID: request.userID,
                                            approved: false,
                                            source: .mac
                                        )
                                    }
                                    Button("允许") {
                                        _ = approvalCoordinator.resolve(
                                            id: request.id,
                                            userID: request.userID,
                                            approved: true,
                                            source: .mac
                                        )
                                    }
                                    .buttonStyle(.borderedProminent)
                                }
                            }
                        }
                    } header: {
                        Text("待授权")
                    }
                }

                // Logs
                Section {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(alignment: .leading) {
                                ForEach(viewModel.messageService.logLines) { entry in
                                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                                        Text(entry.time, style: .time)
                                            .font(.system(.caption2, design: .monospaced))
                                            .foregroundStyle(.tertiary)
                                        Text(entry.message)
                                            .font(.system(.caption, design: .monospaced))
                                            .foregroundStyle(.secondary)
                                    }
                                    .id(entry.id)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        .frame(maxHeight: 120)
                        .onChange(of: viewModel.messageService.logLines.count) { _, _ in
                            if let last = viewModel.messageService.logLines.last {
                                withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                            }
                        }
                    }

                    if viewModel.messageService.canOpenLogFile {
                        Button {
                            viewModel.messageService.openLogFile()
                        } label: {
                            Label("wechat_open_log_file", systemImage: "doc.text")
                        }
                    }
                } header: {
                    Text("wechat_logs")
                }
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $showLoginSheet) {
            WeChatLoginSheet(authService: viewModel.authService) {
                showLoginSheet = false
                viewModel.restart()
            }
        }
        .sheet(isPresented: $showAddAgent) {
            WeChatAddAgentSheet(router: viewModel.agentRouter)
        }
        .alert("wechat_cwd_access_failed", isPresented: cwdAccessErrorBinding) {
            Button("OK", role: .cancel) {
                cwdAccessError = nil
            }
        } message: {
            Text(cwdAccessError ?? "")
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private var statusView: some View {
        switch viewModel.connectionState {
        case .disconnected:
            Label("wechat_disconnected", systemImage: "circle.fill")
                .foregroundStyle(.gray)
                .font(.caption)
        case .connecting:
            Label("wechat_connecting", systemImage: "circle.fill")
                .foregroundStyle(.yellow)
                .font(.caption)
        case .connected:
            Label("wechat_connected", systemImage: "circle.fill")
                .foregroundStyle(.green)
                .font(.caption)
        case .error(let msg):
            Label(msg, systemImage: "exclamationmark.circle.fill")
                .foregroundStyle(.red)
                .font(.caption)
        }
    }

    private func agentIcon(_ type: WeChatAgentRouter.AgentConfig.AgentType) -> String {
        switch type {
        case .http: return "network"
        case .cli: return "terminal"
        case .acp: return "cpu"
        }
    }

    private var hasProtectedWorkingDirectories: Bool {
        viewModel.agentRouter.agents.contains { agent in
            switch WeChatWorkingDirectoryPolicy.status(for: agent.cwd) {
            case .protected:
                return true
            case .unset, .normal, .missing:
                return false
            }
        }
    }

    @ViewBuilder
    private func cwdStatusLabel(for agent: WeChatAgentRouter.AgentConfig) -> some View {
        switch WeChatWorkingDirectoryPolicy.status(for: agent.cwd) {
        case .unset:
            Label("wechat_cwd_default_hint", systemImage: "folder")
                .font(.caption2)
                .foregroundStyle(.secondary)
        case .normal(let path):
            Label(WeChatWorkingDirectoryPolicy.displayPath(path), systemImage: "folder")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        case .protected(let path, let kind):
            Label {
                Text("\(WeChatWorkingDirectoryPolicy.displayPath(path)) - \(kind.displayName)")
                    .lineLimit(1)
                    .truncationMode(.middle)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
            }
            .font(.caption2)
            .foregroundStyle(.yellow)
        case .missing(let path):
            Label {
                Text("\(WeChatWorkingDirectoryPolicy.displayPath(path)) - \(String(localized: "wechat_cwd_missing"))")
                    .lineLimit(1)
                    .truncationMode(.middle)
            } icon: {
                Image(systemName: "xmark.octagon.fill")
            }
            .font(.caption2)
            .foregroundStyle(.red)
        }
    }

    private func chooseWorkingDirectory(for agent: WeChatAgentRouter.AgentConfig) {
        guard let url = WeChatWorkingDirectoryPolicy.chooseDirectoryURL(initialPath: agent.cwd) else { return }
        do {
            try authorizedDirectoryStore.addDirectory(url: url)
        } catch {
            cwdAccessError = error.localizedDescription
            return
        }

        let path = url.path
        let access = WeChatWorkingDirectoryPolicy.validateAccess(for: path)
        guard access.isAccessible else {
            cwdAccessError = access.message
            return
        }
        viewModel.agentRouter.updateAgentWorkingDirectory(agent, cwd: access.path)
        if viewModel.messageService.isRunning {
            viewModel.restart()
        }
    }

    private func addAuthorizedDirectory() {
        guard let url = WeChatWorkingDirectoryPolicy.chooseDirectoryURL(initialPath: nil) else { return }
        do {
            try authorizedDirectoryStore.addDirectory(url: url)
            cwdAccessError = nil
        } catch {
            cwdAccessError = error.localizedDescription
        }
    }

    private var cwdAccessErrorBinding: Binding<Bool> {
        Binding(
            get: { cwdAccessError != nil },
            set: { if !$0 { cwdAccessError = nil } }
        )
    }

    private func approvalPolicyBinding(for agent: WeChatAgentRouter.AgentConfig) -> Binding<WeChatAgentRouter.AgentConfig.ApprovalPolicy> {
        Binding(
            get: { agent.effectiveApprovalPolicy },
            set: { viewModel.agentRouter.updateAgentApprovalPolicy(agent, policy: $0) }
        )
    }

    private func highRiskWechatApprovalBinding(for agent: WeChatAgentRouter.AgentConfig) -> Binding<Bool> {
        Binding(
            get: { agent.canWechatApproveHighRisk },
            set: { viewModel.agentRouter.updateAgentHighRiskWechatApproval(agent, isAllowed: $0) }
        )
    }
}

private extension WeChatViewModel.ConnectionState {
    var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }
}
