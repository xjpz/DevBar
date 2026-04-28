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
                    saveAgent()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!isValid)
            }
        }
        .padding(20)
        .frame(width: 360, height: agentType == .http ? 380 : 300)
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

        TextField("wechat_agent_cwd", text: $cwd)
            .textFieldStyle(.roundedBorder)
    }

    @ViewBuilder
    private var acpFields: some View {
        TextField("wechat_agent_command", text: $command)
            .textFieldStyle(.roundedBorder)
            .font(.system(.body, design: .monospaced))

        TextField("wechat_agent_args", text: $argsText)
            .textFieldStyle(.roundedBorder)
            .font(.system(.body, design: .monospaced))

        TextField("wechat_agent_cwd", text: $cwd)
            .textFieldStyle(.roundedBorder)
    }

    // MARK: - Validation

    private var isValid: Bool {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return false }
        switch agentType {
        case .http:
            return !endpoint.trimmingCharacters(in: .whitespaces).isEmpty
        case .cli, .acp:
            return !command.trimmingCharacters(in: .whitespaces).isEmpty
        }
    }

    // MARK: - Save

    private func saveAgent() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let parsedArgs = argsText.trimmingCharacters(in: .whitespaces).isEmpty
            ? nil
            : argsArgsSplit(argsText)

        switch agentType {
        case .http:
            router.addHTTPAgent(
                name: trimmedName,
                endpoint: endpoint.trimmingCharacters(in: .whitespaces),
                apiKey: apiKey.isEmpty ? nil : apiKey,
                model: model.isEmpty ? nil : model.trimmingCharacters(in: .whitespaces)
            )
        case .cli:
            let agent = WeChatAgentRouter.AgentConfig(
                name: trimmedName, type: .cli,
                command: command.trimmingCharacters(in: .whitespaces),
                args: parsedArgs,
                cwd: cwd.isEmpty ? nil : cwd.trimmingCharacters(in: .whitespaces),
                env: nil, model: nil, systemPrompt: nil, aliases: nil,
                endpoint: nil, apiKey: nil, headers: nil, maxHistory: nil
            )
            router.addAgent(agent)
        case .acp:
            let agent = WeChatAgentRouter.AgentConfig(
                name: trimmedName, type: .acp,
                command: command.trimmingCharacters(in: .whitespaces),
                args: parsedArgs,
                cwd: cwd.isEmpty ? nil : cwd.trimmingCharacters(in: .whitespaces),
                env: nil, model: nil, systemPrompt: nil, aliases: nil,
                endpoint: nil, apiKey: nil, headers: nil, maxHistory: nil
            )
            router.addAgent(agent)
        }
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
