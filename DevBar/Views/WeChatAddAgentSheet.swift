// WeChatAddAgentSheet.swift
// DevBar

import SwiftUI

struct WeChatAddAgentSheet: View {
    @ObservedObject var router: WeChatAgentRouter
    @Environment(\.dismiss) private var dismiss

    @State private var agentType: WeChatAgentRouter.AgentConfig.AgentType = .http
    @State private var name = ""
    @State private var endpoint = ""
    @State private var apiKey = ""
    @State private var model = ""
    @State private var command = ""
    @State private var argsText = ""
    @State private var cwd = ""
    @State private var cwdAccessError: String?

    private var cwdStatus: WeChatWorkingDirectoryPolicy.DirectoryStatus {
        WeChatWorkingDirectoryPolicy.status(for: cwd)
    }

    var body: some View {
        VStack(spacing: 16) {
            Text("wechat_add_agent_title")
                .font(.headline)

            Form {
                Picker("wechat_agent_type", selection: $agentType) {
                    Text("HTTP").tag(WeChatAgentRouter.AgentConfig.AgentType.http)
                    Text("CLI").tag(WeChatAgentRouter.AgentConfig.AgentType.cli)
                    Text("ACP").tag(WeChatAgentRouter.AgentConfig.AgentType.acp)
                }
                .pickerStyle(.segmented)

                TextField("wechat_agent_name", text: $name)
                    .textFieldStyle(.roundedBorder)

                switch agentType {
                case .http:
                    httpFields
                case .cli:
                    cliFields
                case .acp:
                    acpFields
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)

            HStack(spacing: 16) {
                Button("Cancel") { dismiss() }
                Button("wechat_add_agent_save") {
                    if saveAgent() {
                        dismiss()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!isValid)
            }
        }
        .padding(20)
        .frame(width: 420)
    }

    // MARK: - Field Sections

    @ViewBuilder
    private var httpFields: some View {
        TextField("wechat_agent_endpoint", text: $endpoint)
            .textFieldStyle(.roundedBorder)
            .font(.system(.body, design: .monospaced))

        SecureField("wechat_agent_api_key", text: $apiKey)
            .textFieldStyle(.roundedBorder)

        TextField("wechat_agent_model", text: $model)
            .textFieldStyle(.roundedBorder)
    }

    @ViewBuilder
    private var cliFields: some View {
        TextField("wechat_agent_command", text: $command)
            .textFieldStyle(.roundedBorder)
            .font(.system(.body, design: .monospaced))

        TextField("wechat_agent_args", text: $argsText)
            .textFieldStyle(.roundedBorder)
            .font(.system(.body, design: .monospaced))

        workingDirectoryField
    }

    @ViewBuilder
    private var acpFields: some View {
        TextField("wechat_agent_command", text: $command)
            .textFieldStyle(.roundedBorder)
            .font(.system(.body, design: .monospaced))

        TextField("wechat_agent_args", text: $argsText)
            .textFieldStyle(.roundedBorder)
            .font(.system(.body, design: .monospaced))

        workingDirectoryField
    }

    @ViewBuilder
    private var workingDirectoryField: some View {
        HStack(spacing: 8) {
            TextField("wechat_agent_cwd", text: $cwd)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))

            Button {
                if let path = WeChatWorkingDirectoryPolicy.chooseDirectory(initialPath: cwd) {
                    let access = WeChatWorkingDirectoryPolicy.validateAccess(for: path)
                    if access.isAccessible {
                        cwd = access.path
                        cwdAccessError = nil
                    } else {
                        cwdAccessError = access.message
                    }
                }
            } label: {
                Image(systemName: "folder")
            }
            .help(Text("wechat_cwd_choose"))
        }

        cwdStatusView(cwdStatus)

        if let cwdAccessError {
            Label(cwdAccessError, systemImage: "xmark.octagon.fill")
                .font(.caption)
                .foregroundStyle(.red)
        }
    }

    // MARK: - Validation

    private var isValid: Bool {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return false }
        switch agentType {
        case .http:
            return !endpoint.trimmingCharacters(in: .whitespaces).isEmpty
        case .cli, .acp:
            return !command.trimmingCharacters(in: .whitespaces).isEmpty && cwdStatus.isValidForSave
        }
    }

    @ViewBuilder
    private func cwdStatusView(_ status: WeChatWorkingDirectoryPolicy.DirectoryStatus) -> some View {
        switch status {
        case .unset:
            Label("wechat_cwd_default_hint", systemImage: "folder")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .normal(let path):
            Label(WeChatWorkingDirectoryPolicy.displayPath(path), systemImage: "folder")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .protected(let path, let kind):
            Label {
                Text("\(WeChatWorkingDirectoryPolicy.displayPath(path)) - \(String(localized: "wechat_cwd_protected_hint")) \(kind.displayName)")
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
            }
            .font(.caption)
            .foregroundStyle(.yellow)
        case .missing(let path):
            Label {
                Text("\(WeChatWorkingDirectoryPolicy.displayPath(path)) - \(String(localized: "wechat_cwd_missing"))")
            } icon: {
                Image(systemName: "xmark.octagon.fill")
            }
            .font(.caption)
            .foregroundStyle(.red)
        }
    }

    // MARK: - Save

    @discardableResult
    private func saveAgent() -> Bool {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let parsedArgs = argsText.trimmingCharacters(in: .whitespaces).isEmpty
            ? nil
            : argsArgsSplit(argsText)

        switch agentType {
        case .http:
            cwdAccessError = nil
            router.addHTTPAgent(
                name: trimmedName,
                endpoint: endpoint.trimmingCharacters(in: .whitespaces),
                apiKey: apiKey.isEmpty ? nil : apiKey,
                model: model.isEmpty ? nil : model.trimmingCharacters(in: .whitespaces)
            )
        case .cli:
            let normalizedCwd = validatedWorkingDirectoryForSave()
            if cwdAccessError != nil {
                return false
            }
            let agent = WeChatAgentRouter.AgentConfig(
                name: trimmedName, type: .cli,
                command: command.trimmingCharacters(in: .whitespaces),
                args: parsedArgs,
                cwd: normalizedCwd,
                env: nil, model: nil, systemPrompt: nil, aliases: nil,
                endpoint: nil, apiKey: nil, headers: nil, maxHistory: nil,
                approvalPolicy: nil, approvalTimeoutSeconds: nil, allowWechatConfirmForLowRisk: nil
            )
            router.addAgent(agent)
        case .acp:
            let normalizedCwd = validatedWorkingDirectoryForSave()
            if cwdAccessError != nil {
                return false
            }
            let agent = WeChatAgentRouter.AgentConfig(
                name: trimmedName, type: .acp,
                command: command.trimmingCharacters(in: .whitespaces),
                args: parsedArgs,
                cwd: normalizedCwd,
                env: nil, model: nil, systemPrompt: nil, aliases: nil,
                endpoint: nil, apiKey: nil, headers: nil, maxHistory: nil,
                approvalPolicy: nil, approvalTimeoutSeconds: nil, allowWechatConfirmForLowRisk: nil
            )
            router.addAgent(agent)
        }
        return true
    }

    private func validatedWorkingDirectoryForSave() -> String? {
        let trimmedCwd = cwd.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedCwd.isEmpty else {
            cwdAccessError = nil
            return nil
        }

        let access = WeChatWorkingDirectoryPolicy.validateAccess(for: trimmedCwd)
        guard access.isAccessible else {
            cwdAccessError = access.message
            return nil
        }
        cwdAccessError = nil
        return access.path
    }

    private func argsArgsSplit(_ text: String) -> [String] {
        var args: [String] = []
        var current = ""
        var quote: Character?
        var escaping = false

        for char in text {
            if escaping {
                current.append(char)
                escaping = false
                continue
            }
            if char == "\\" {
                escaping = true
                continue
            }
            if let activeQuote = quote {
                if char == activeQuote {
                    quote = nil
                } else {
                    current.append(char)
                }
                continue
            }
            if char == "\"" || char == "'" {
                quote = char
                continue
            }
            if char.isWhitespace {
                if !current.isEmpty {
                    args.append(current)
                    current.removeAll()
                }
                continue
            }
            current.append(char)
        }

        if escaping {
            current.append("\\")
        }
        if !current.isEmpty {
            args.append(current)
        }
        return args
    }
}
