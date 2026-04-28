// SettingsWeChat.swift
// DevBar

import SwiftUI

struct SettingsWeChat: View {
    @EnvironmentObject private var appViewModel: AppViewModel
    @StateObject private var viewModel: WeChatViewModel
    @State private var showLoginSheet = false
    @State private var showAddAgent = false

    init() {
        _viewModel = StateObject(wrappedValue: WeChatViewModel())
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
                } header: {
                    Text("wechat_logs")
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            viewModel.setup()
        }
        .sheet(isPresented: $showLoginSheet) {
            WeChatLoginSheet(authService: viewModel.authService) {
                showLoginSheet = false
                viewModel.restart()
            }
        }
        .sheet(isPresented: $showAddAgent) {
            WeChatAddAgentSheet(router: viewModel.agentRouter)
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
}

private extension WeChatViewModel.ConnectionState {
    var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }
}
