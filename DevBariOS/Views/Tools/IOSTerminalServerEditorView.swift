import DevBarCore
import SwiftData
import SwiftUI

struct IOSTerminalServerEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.themeTokens) private var theme

    let mode: IOSTerminalServerEditorMode

    @State private var name = ""
    @State private var host = ""
    @State private var portText = "22"
    @State private var username = ""
    @State private var remoteOSFamily: TerminalRemoteOSFamily = .auto
    @State private var authMethod: IOSTerminalAuthMethod = .password
    @State private var password = ""
    @State private var privateKey = ""
    @State private var privateKeyPassphrase = ""
    @State private var errorMessage: String?
    @State private var isSaving = false

    private let credentialStore = TerminalCredentialStore()
    private let commandClient = NIOSSHCommandClient()

    var body: some View {
        Form {
            Section("Server") {
                TextField("Name", text: $name)
                TextField("Host", text: $host)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                TextField("Port", text: $portText)
                    .keyboardType(.numberPad)
                TextField("Username", text: $username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Picker("System", selection: $remoteOSFamily) {
                    ForEach(TerminalRemoteOSFamily.allCases) { family in
                        Text(family.title).tag(family)
                    }
                }
            }

            Section("Authentication") {
                Picker("Method", selection: $authMethod) {
                    ForEach(IOSTerminalAuthMethod.allCases) { method in
                        Text(method.title).tag(method)
                    }
                }
                .pickerStyle(.segmented)

                switch authMethod {
                case .password:
                    SecureField(passwordPlaceholder, text: $password)
                case .privateKey:
                    TextEditor(text: $privateKey)
                        .font(theme.bodyMonoFont)
                        .frame(minHeight: 160)
                        .overlay(alignment: .topLeading) {
                            if privateKey.isEmpty {
                                Text(privateKeyPlaceholder)
                                    .foregroundStyle(theme.textTertiary)
                                    .padding(.top, 8)
                                    .padding(.leading, 5)
                            }
                        }
                    SecureField(privateKeyPassphrasePlaceholder, text: $privateKeyPassphrase)
                }
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .font(theme.footnoteFont)
                        .foregroundStyle(theme.danger)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .iosGeekScreenBackground(theme)
        .navigationTitle(navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(theme.backgroundSecondary, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .presentationBackground(theme.backgroundPrimary)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("ios_common_cancel") {
                    dismiss()
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(isSaving ? "Saving..." : "Save") {
                    Task {
                        await save()
                    }
                }
                .disabled(isSaving)
            }
        }
        .onAppear(perform: loadInitialValues)
    }

    private var navigationTitle: String {
        switch mode {
        case .add:
            return "Add Server"
        case .edit:
            return "Edit Server"
        }
    }

    private var passwordPlaceholder: String {
        switch mode {
        case .add:
            return "Password"
        case .edit:
            return "Password, leave blank to keep current"
        }
    }

    private var privateKeyPlaceholder: String {
        switch mode {
        case .add:
            return "Paste private key"
        case .edit:
            return "Paste private key, or leave blank to keep current"
        }
    }

    private var privateKeyPassphrasePlaceholder: String {
        switch mode {
        case .add:
            return "Passphrase, optional"
        case .edit:
            return "Passphrase, leave blank to keep current"
        }
    }

    private func loadInitialValues() {
        guard case let .edit(server) = mode else { return }
        name = server.name
        host = server.host
        portText = "\(server.port)"
        username = server.username
        remoteOSFamily = server.remoteOSFamily
        authMethod = server.authMethod
    }

    private func save() async {
        guard !isSaving else { return }
        isSaving = true
        defer { isSaving = false }

        do {
            errorMessage = nil
            let server = currentServer
            let existingSecret = currentExistingSecret(for: server)
            let enteredSecret = currentEnteredSecret
            let validationSecret = enteredSecret.isEmpty ? existingSecret : enteredSecret

            let draft = TerminalServerDraft(
                name: name,
                host: host,
                portText: portText,
                username: username,
                authentication: authMethod == .password
                    ? .password(secret: validationSecret)
                    : .privateKey(secret: validationSecret)
            )
            let configuration = try TerminalServerValidator.validate(draft)
            let authentication = try makeConnectionAuthentication(secret: validationSecret)
            let detectedOSFamily = try await verifyConnectionAndResolveRemoteOSFamily(
                configuration: configuration,
                authentication: authentication
            )

            let targetServer = server ?? IOSTerminalServer(
                name: configuration.name,
                host: configuration.host,
                port: configuration.port,
                username: configuration.username,
                authMethod: authMethod
            )

            targetServer.name = configuration.name
            targetServer.host = configuration.host
            targetServer.port = configuration.port
            targetServer.username = configuration.username
            targetServer.authMethod = authMethod
            targetServer.remoteOSFamily = detectedOSFamily
            targetServer.updatedAt = .now

            saveSecretIfNeeded(for: targetServer, enteredSecret: enteredSecret)
            savePrivateKeyPassphraseIfNeeded(for: targetServer)

            if server == nil {
                modelContext.insert(targetServer)
            }

            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private var currentServer: IOSTerminalServer? {
        guard case let .edit(server) = mode else { return nil }
        return server
    }

    private var currentEnteredSecret: String {
        switch authMethod {
        case .password:
            return password.trimmingCharacters(in: .whitespacesAndNewlines)
        case .privateKey:
            return privateKey.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private func currentExistingSecret(for server: IOSTerminalServer?) -> String {
        guard let server else { return "" }
        let key = authMethod == .password ? server.passwordSecretKey : server.privateKeySecretKey
        guard let key else { return "" }
        return credentialStore.loadSecret(forKey: key) ?? ""
    }

    private func verifyConnectionAndResolveRemoteOSFamily(
        configuration: TerminalServerConfiguration,
        authentication: TerminalConnectionAuthentication
    ) async throws -> TerminalRemoteOSFamily {
        let command = remoteOSFamily == .auto
            ? TerminalRemoteOSDetector.probeCommand
            : "printf devbar-terminal-ok"
        let output = try await commandClient.run(
            command: command,
            configuration: TerminalConnectionConfiguration(
                host: configuration.host,
                port: configuration.port,
                username: configuration.username,
                authentication: authentication
            )
        )

        guard remoteOSFamily == .auto else {
            return remoteOSFamily
        }

        let detected = TerminalRemoteOSDetector.detect(from: output)
        return detected == .unknown ? .linux : detected
    }

    private func makeConnectionAuthentication(secret: String) throws -> TerminalConnectionAuthentication {
        switch authMethod {
        case .password:
            return .password(secret)
        case .privateKey:
            let passphrase = resolvedPrivateKeyPassphrase()
            if passphrase == nil,
               try TerminalPrivateKeyParser.isEncrypted(secret) {
                throw TerminalPrivateKeyParserError.missingPassphrase
            }
            return .privateKey(secret, passphrase: passphrase)
        }
    }

    private func resolvedPrivateKeyPassphrase() -> String? {
        guard authMethod == .privateKey else { return nil }

        if let enteredPassphrase = TerminalPrivateKeyPassphrasePolicy.normalized(privateKeyPassphrase) {
            return enteredPassphrase
        }

        guard let passphraseKey = currentServer?.privateKeyPassphraseSecretKey else { return nil }
        return TerminalPrivateKeyPassphrasePolicy.normalized(credentialStore.loadSecret(forKey: passphraseKey))
    }

    private func saveSecretIfNeeded(for server: IOSTerminalServer, enteredSecret: String) {
        guard !enteredSecret.isEmpty else { return }

        switch authMethod {
        case .password:
            server.passwordSecretKey = credentialStore.savePassword(enteredSecret, serverID: server.id)
        case .privateKey:
            server.privateKeySecretKey = credentialStore.savePrivateKey(enteredSecret, serverID: server.id)
        }
    }

    private func savePrivateKeyPassphraseIfNeeded(for server: IOSTerminalServer) {
        guard authMethod == .privateKey else { return }
        guard let enteredPassphrase = TerminalPrivateKeyPassphrasePolicy.normalized(privateKeyPassphrase) else {
            if currentServer == nil || !privateKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                server.privateKeyPassphraseSecretKey = nil
            }
            return
        }
        server.privateKeyPassphraseSecretKey = credentialStore.savePrivateKeyPassphrase(
            enteredPassphrase,
            serverID: server.id
        )
    }
}
