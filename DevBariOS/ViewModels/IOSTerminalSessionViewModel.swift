import DevBarCore
import Combine
import Foundation

@MainActor
final class IOSTerminalSessionViewModel: ObservableObject {
    enum ConnectionState: Equatable {
        case disconnected
        case connecting
        case connected
        case failed(String)

        var title: String {
            switch self {
            case .disconnected:
                return "Disconnected"
            case .connecting:
                return "Connecting"
            case .connected:
                return "Connected"
            case .failed:
                return "Failed"
            }
        }
    }

    @Published private(set) var state: ConnectionState = .disconnected
    @Published private(set) var output = ""

    private let server: IOSTerminalServer
    private let credentialStore: TerminalCredentialStore
    private let client: TerminalSessionClient
    private var outputTask: Task<Void, Never>?
    private var terminalColumns = 44
    private var terminalRows = 24

    init(
        server: IOSTerminalServer,
        credentialStore: TerminalCredentialStore = TerminalCredentialStore(),
        client: TerminalSessionClient = NIOSSHSessionClient()
    ) {
        self.server = server
        self.credentialStore = credentialStore
        self.client = client
    }

    var canSendInput: Bool {
        state == .connected
    }

    var isConnected: Bool {
        state == .connected
    }

    func updateViewport(columns: Int, rows: Int) {
        terminalColumns = min(120, max(24, columns))
        terminalRows = min(80, max(12, rows))
    }

    func connect() {
        guard state != .connecting, state != .connected else { return }

        outputTask?.cancel()
        state = .connecting
        updateLiveActivity(status: .connecting)

        Task {
            do {
                let configuration = try makeConnectionConfiguration()
                try await client.connect(configuration: configuration)
                server.lastConnectedAt = .now
                state = .connected
                updateLiveActivity(status: .connected)
                appendSystemLine("Connected to \(server.displayAddress)")
                observeOutput()
            } catch {
                state = .failed(error.localizedDescription)
                updateLiveActivity(status: .failed, statusText: error.localizedDescription)
                appendSystemLine(error.localizedDescription)
            }
        }
    }

    func reconnect() {
        guard state != .connecting else { return }

        outputTask?.cancel()
        outputTask = nil

        Task {
            await client.disconnect()
            await MainActor.run {
                state = .disconnected
                updateLiveActivity(status: .disconnected)
                connect()
            }
        }
    }

    func disconnect(shouldRecordOutput: Bool = false) {
        let shouldAppendDisconnected = shouldRecordOutput && (state == .connecting || state == .connected)
        outputTask?.cancel()
        outputTask = nil
        Task {
            await client.disconnect()
        }
        state = .disconnected
        updateLiveActivity(status: .disconnected)
        if shouldAppendDisconnected {
            appendSystemLine("Disconnected")
        }
    }

    func sendText(_ text: String) {
        guard !text.isEmpty else { return }
        send(Data(text.utf8))
    }

    func sendReturn() {
        send(Data([0x0A]))
    }

    func sendDeleteBackward() {
        send(TerminalInputControl.deleteBackward)
    }

    func sendShortcut(_ shortcut: TerminalShortcutKey) {
        send(shortcut.payload)
    }

    func clearOutput() {
        output = ""
    }

    func updateLiveActivityForBackgroundState(isBackgrounded: Bool) {
        guard state == .connected else { return }
        updateLiveActivity(status: isBackgrounded ? .suspended : .connected)
    }

    private func send(_ data: Data) {
        guard canSendInput else { return }
        Task {
            do {
                try await client.send(data)
            } catch {
                handleSendFailure(error)
            }
        }
    }

    private func observeOutput() {
        outputTask = Task { [weak self] in
            guard let self else { return }
            do {
                for try await chunk in await client.outputStream() {
                    guard !Task.isCancelled else { return }
                    append(chunk)
                }
                guard !Task.isCancelled else { return }
                markSessionEnded()
            } catch {
                guard !Task.isCancelled else { return }
                if isExpectedDisconnect(error) {
                    markSessionEnded()
                } else {
                    state = .failed(error.localizedDescription)
                    updateLiveActivity(status: .failed, statusText: error.localizedDescription)
                    appendSystemLine(error.localizedDescription)
                }
            }
        }
    }

    private func handleSendFailure(_ error: Error) {
        if isExpectedDisconnect(error) {
            markSessionEnded()
        } else {
            state = .failed(error.localizedDescription)
            updateLiveActivity(status: .failed, statusText: error.localizedDescription)
            appendSystemLine(error.localizedDescription)
        }
    }

    private func markSessionEnded() {
        guard state == .connected || state == .connecting else { return }
        state = .disconnected
        updateLiveActivity(status: .disconnected)
        appendSystemLine("Session ended")
    }

    private func updateLiveActivity(status: TerminalActivityStatus, statusText: String? = nil) {
        Task {
            if status == .disconnected {
                await IOSTerminalLiveActivityManager.shared.end(serverID: server.id)
            } else {
                await IOSTerminalLiveActivityManager.shared.update(
                    serverID: server.id,
                    serverName: server.name,
                    address: server.displayAddress,
                    remoteOSFamily: server.remoteOSFamily,
                    status: status,
                    statusText: statusText
                )
            }
        }
    }

    private func isExpectedDisconnect(_ error: Error) -> Bool {
        if let clientError = error as? TerminalSessionClientError,
           clientError == .notConnected {
            return true
        }
        return false
    }

    private func makeConnectionConfiguration() throws -> TerminalConnectionConfiguration {
        let secretKey: String?
        var passphrase: String?
        switch server.authMethod {
        case .password:
            secretKey = server.passwordSecretKey
        case .privateKey:
            secretKey = server.privateKeySecretKey
            if let passphraseKey = server.privateKeyPassphraseSecretKey {
                passphrase = TerminalPrivateKeyPassphrasePolicy.normalized(credentialStore.loadSecret(forKey: passphraseKey))
            }
        }

        guard let secretKey,
              let secret = credentialStore.loadSecret(forKey: secretKey),
              !secret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw TerminalSessionError.missingCredential
        }

        if server.authMethod == .privateKey,
           passphrase == nil,
           (try? TerminalPrivateKeyParser.isEncrypted(secret)) == true {
            throw TerminalPrivateKeyParserError.missingPassphrase
        }

        return TerminalConnectionConfiguration(
            host: server.host,
            port: server.port,
            username: server.username,
            authentication: server.authMethod == .password
                ? .password(secret)
                : .privateKey(secret, passphrase: passphrase),
            columns: terminalColumns,
            rows: terminalRows
        )
    }

    private func appendSystemLine(_ line: String) {
        append("\n[\(line)]\n")
    }

    private func append(_ chunk: String) {
        TerminalOutputSanitizer.append(chunk, to: &output)
        if output.count > 80_000 {
            output.removeFirst(output.count - 80_000)
        }
    }
}

enum TerminalSessionError: LocalizedError {
    case missingCredential

    var errorDescription: String? {
        switch self {
        case .missingCredential:
            return "Missing terminal credential."
        }
    }
}
