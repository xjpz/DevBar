import CryptoKit
import Foundation
import Network
import Security

@MainActor
public final class DeviceRelayLocalTransport {
    public var messageHandler: ((DeviceRelayMessage) -> Void)?
    public var stateHandler: ((Set<String>) -> Void)?
    public var logHandler: ((DeviceRelayLogEntry.Level, String) -> Void)?

    private var listener: NWListener?
    private var browser: NWBrowser?
    private var pathMonitor: NWPathMonitor?
    private var connections: [ObjectIdentifier: LocalConnection] = [:]
    private var authenticatedConnections: [String: ObjectIdentifier] = [:]
    private var heartbeatTask: Task<Void, Never>?
    private var targetPeerIDs: Set<String> = []
    private var localDeviceID: String?
    private var deviceType: DeviceRelayDeviceType?
    private var secretProvider: ((String) -> String?)?
    private var isLocalPathAvailable = true
    private let queue = DispatchQueue(label: "cc.xjpz.DevBar.deviceRelay.local")

    public init() {}

    public var connectedPeerIDs: Set<String> {
        Set(authenticatedConnections.keys)
    }

    public func start(
        deviceType: DeviceRelayDeviceType,
        localDeviceID: String,
        targetPeerIDs: Set<String>,
        secretProvider: @escaping (String) -> String?
    ) {
        self.deviceType = deviceType
        self.localDeviceID = localDeviceID
        self.targetPeerIDs = targetPeerIDs
        self.secretProvider = secretProvider
        startPathMonitorIfNeeded(deviceType: deviceType)
        startHeartbeatMonitorIfNeeded()

        switch deviceType {
        case .mac:
            startListener(localDeviceID: localDeviceID)
        case .iPhone:
            startBrowser()
        }
    }

    public func updateTargetPeerIDs(_ peerIDs: Set<String>) {
        targetPeerIDs = peerIDs
        if deviceType == .iPhone, browser == nil {
            startBrowser()
        }
    }

    public func restartDiscovery() {
        guard deviceType == .iPhone else { return }
        browser?.cancel()
        browser = nil
        startBrowser()
    }

    public func stop() {
        listener?.cancel()
        browser?.cancel()
        pathMonitor?.cancel()
        heartbeatTask?.cancel()
        connections.values.forEach { $0.connection.cancel() }
        listener = nil
        browser = nil
        pathMonitor = nil
        heartbeatTask = nil
        connections.removeAll()
        authenticatedConnections.removeAll()
        notifyState()
    }

    public func disconnect(peerDeviceID: String) {
        guard let id = authenticatedConnections[peerDeviceID],
              let localConnection = connections[id] else {
            return
        }
        localConnection.connection.cancel()
        remove(localConnection)
    }

    public func send(_ message: DeviceRelayMessage) throws -> Bool {
        guard isLocalPathAvailable else { return false }
        guard let targetDeviceID = message.targetDeviceId,
              let id = authenticatedConnections[targetDeviceID],
              let localConnection = connections[id] else {
            return false
        }
        try localConnection.send(message)
        return true
    }

    public func waitForConnection(peerDeviceID: String, timeout: TimeInterval) async -> Bool {
        guard isLocalPathAvailable else { return false }
        if authenticatedConnections[peerDeviceID] != nil { return true }
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            try? await Task.sleep(for: .milliseconds(120))
            if authenticatedConnections[peerDeviceID] != nil { return true }
        }
        return false
    }

    private func startListener(localDeviceID: String) {
        guard listener == nil else { return }
        do {
            let listener = try NWListener(using: .tcp)
            listener.service = NWListener.Service(
                name: sanitizedServiceName(localDeviceID),
                type: DevBarCoreConstants.DeviceRelay.localServiceType
            )
            listener.newConnectionHandler = { [weak self] connection in
                Task { @MainActor in
                    self?.accept(connection)
                }
            }
            listener.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in
                    self?.handleListenerState(state)
                }
            }
            self.listener = listener
            listener.start(queue: queue)
        } catch {
            logHandler?(.warning, "本地监听启动失败：\(error.localizedDescription)")
        }
    }

    private func startBrowser() {
        guard isLocalPathAvailable else { return }
        guard browser == nil else { return }
        let descriptor = NWBrowser.Descriptor.bonjour(
            type: DevBarCoreConstants.DeviceRelay.localServiceType,
            domain: nil
        )
        let browser = NWBrowser(for: descriptor, using: .tcp)
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            Task { @MainActor in
                self?.handleBrowseResults(results)
            }
        }
        browser.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                self?.handleBrowserState(state)
            }
        }
        self.browser = browser
        browser.start(queue: queue)
    }

    private func startPathMonitorIfNeeded(deviceType: DeviceRelayDeviceType) {
        guard pathMonitor == nil else { return }
        guard deviceType == .iPhone else { return }
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                self?.handlePathUpdate(path)
            }
        }
        pathMonitor = monitor
        monitor.start(queue: queue)
    }

    private func handlePathUpdate(_ path: NWPath) {
        let isAvailable = path.status == .satisfied && path.usesInterfaceType(.wifi)
        guard isAvailable != isLocalPathAvailable else { return }
        isLocalPathAvailable = isAvailable

        if isAvailable {
            logHandler?(.info, "Wi-Fi 已恢复，重新搜索局域网 Mac")
            startBrowser()
        } else {
            logHandler?(.warning, "Wi-Fi 不可用，关闭本地连接并回退远程中继")
            closeBrowserAndConnections()
        }
    }

    private func closeBrowserAndConnections() {
        browser?.cancel()
        browser = nil
        connections.values.forEach { $0.connection.cancel() }
        connections.removeAll()
        authenticatedConnections.removeAll()
        notifyState()
    }

    private func accept(_ connection: NWConnection) {
        let localConnection = LocalConnection(connection: connection, role: .server)
        register(localConnection)
        start(localConnection)
    }

    private func connect(to endpoint: NWEndpoint, peerDeviceID: String) {
        guard authenticatedConnections[peerDeviceID] == nil else { return }
        guard !connections.values.contains(where: { $0.expectedPeerID == peerDeviceID }) else { return }

        let connection = NWConnection(to: endpoint, using: .tcp)
        let localConnection = LocalConnection(connection: connection, role: .client, expectedPeerID: peerDeviceID)
        register(localConnection)
        start(localConnection)
    }

    private func register(_ localConnection: LocalConnection) {
        connections[localConnection.id] = localConnection
        localConnection.messageHandler = { [weak self, weak localConnection] message in
            guard let localConnection else { return }
            Task { @MainActor in
                self?.handle(message, from: localConnection)
            }
        }
        localConnection.closeHandler = { [weak self, weak localConnection] in
            guard let localConnection else { return }
            Task { @MainActor in
                self?.remove(localConnection)
            }
        }
    }

    private func start(_ localConnection: LocalConnection) {
        localConnection.connection.stateUpdateHandler = { [weak self, weak localConnection] state in
            guard let localConnection else { return }
            Task { @MainActor in
                self?.handleConnectionState(state, localConnection: localConnection)
            }
        }
        localConnection.start(on: queue)
    }

    private func handleListenerState(_ state: NWListener.State) {
        switch state {
        case .ready:
            logHandler?(.success, "本地中继已发布")
        case let .failed(error):
            logHandler?(.warning, "本地中继监听失败：\(error.localizedDescription)")
            listener = nil
        case .cancelled:
            listener = nil
        default:
            break
        }
    }

    private func handleBrowserState(_ state: NWBrowser.State) {
        switch state {
        case .ready:
            logHandler?(.info, "正在搜索局域网 Mac")
        case let .failed(error):
            logHandler?(.warning, "局域网搜索失败：\(error.localizedDescription)")
            browser = nil
        case .cancelled:
            browser = nil
        default:
            break
        }
    }

    private func handleBrowseResults(_ results: Set<NWBrowser.Result>) {
        guard !targetPeerIDs.isEmpty else { return }
        for result in results {
            guard let serviceName = result.endpoint.bonjourServiceName,
                  targetPeerIDs.contains(serviceName) else {
                continue
            }
            connect(to: result.endpoint, peerDeviceID: serviceName)
        }
    }

    private func handleConnectionState(_ state: NWConnection.State, localConnection: LocalConnection) {
        switch state {
        case .ready:
            if localConnection.role == .server {
                sendChallenge(to: localConnection)
            }
        case let .failed(error):
            logHandler?(.warning, "本地连接失败：\(error.localizedDescription)")
            remove(localConnection)
        case .cancelled:
            remove(localConnection)
        default:
            break
        }
    }

    private func handle(_ message: DeviceRelayMessage, from localConnection: LocalConnection) {
        localConnection.lastSeenAt = Date()
        switch message.type {
        case .localChallenge:
            respondToChallenge(message, on: localConnection)
        case .localAuth:
            verifyAuth(message, on: localConnection)
        case .localReady:
            markAuthenticated(peerDeviceID: message.fromDeviceId, on: localConnection)
        default:
            guard localConnection.peerDeviceID != nil else {
                logHandler?(.warning, "忽略未认证本地消息：\(message.type.rawValue)")
                return
            }
            messageHandler?(message)
        }
    }

    private func sendChallenge(to localConnection: LocalConnection) {
        guard let localDeviceID else { return }
        let nonce = Self.randomToken()
        localConnection.pendingNonce = nonce
        try? localConnection.send(
            DeviceRelayMessage(
                type: .localChallenge,
                requestId: "local-challenge-\(UUID().uuidString.lowercased())",
                fromDeviceId: localDeviceID,
                payload: ["nonce": nonce]
            )
        )
    }

    private func respondToChallenge(_ message: DeviceRelayMessage, on localConnection: LocalConnection) {
        guard let localDeviceID,
              let remoteDeviceID = message.fromDeviceId,
              targetPeerIDs.contains(remoteDeviceID),
              let nonce = message.payload["nonce"],
              let secret = secretProvider?(remoteDeviceID) else {
            localConnection.connection.cancel()
            return
        }
        let proof = Self.proof(
            secret: secret,
            nonce: nonce,
            fromDeviceID: localDeviceID,
            targetDeviceID: remoteDeviceID
        )
        try? localConnection.send(
            DeviceRelayMessage(
                type: .localAuth,
                requestId: "local-auth-\(UUID().uuidString.lowercased())",
                fromDeviceId: localDeviceID,
                targetDeviceId: remoteDeviceID,
                payload: [
                    "nonce": nonce,
                    "proof": proof,
                ]
            )
        )
    }

    private func verifyAuth(_ message: DeviceRelayMessage, on localConnection: LocalConnection) {
        guard let localDeviceID,
              let peerDeviceID = message.fromDeviceId,
              let nonce = message.payload["nonce"],
              nonce == localConnection.pendingNonce,
              let proof = message.payload["proof"],
              let secret = secretProvider?(peerDeviceID) else {
            logHandler?(.warning, "本地认证失败")
            localConnection.connection.cancel()
            return
        }
        let expected = Self.proof(
            secret: secret,
            nonce: nonce,
            fromDeviceID: peerDeviceID,
            targetDeviceID: localDeviceID
        )
        guard proof == expected else {
            logHandler?(.warning, "本地认证摘要不匹配")
            localConnection.connection.cancel()
            return
        }
        markAuthenticated(peerDeviceID: peerDeviceID, on: localConnection)
        try? localConnection.send(
            DeviceRelayMessage(
                type: .localReady,
                requestId: "local-ready-\(UUID().uuidString.lowercased())",
                fromDeviceId: localDeviceID,
                targetDeviceId: peerDeviceID,
                payload: [:]
            )
        )
    }

    private func markAuthenticated(peerDeviceID: String?, on localConnection: LocalConnection) {
        guard let peerDeviceID else { return }
        localConnection.peerDeviceID = peerDeviceID
        localConnection.lastSeenAt = Date()
        authenticatedConnections[peerDeviceID] = localConnection.id
        logHandler?(.success, "本地连接已认证：\(peerDeviceID)")
        notifyState()
    }

    private func remove(_ localConnection: LocalConnection) {
        connections.removeValue(forKey: localConnection.id)
        if let peerDeviceID = localConnection.peerDeviceID,
           authenticatedConnections[peerDeviceID] == localConnection.id {
            authenticatedConnections.removeValue(forKey: peerDeviceID)
            logHandler?(.info, "本地连接已断开：\(peerDeviceID)")
            notifyState()
        }
    }

    private func notifyState() {
        stateHandler?(connectedPeerIDs)
    }

    private func startHeartbeatMonitorIfNeeded() {
        guard heartbeatTask == nil else { return }
        heartbeatTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(DevBarCoreConstants.DeviceRelay.localHeartbeatInterval))
                self?.checkLocalHeartbeats()
            }
        }
    }

    private func checkLocalHeartbeats() {
        guard let localDeviceID else { return }
        let now = Date()
        for localConnection in Array(connections.values) {
            guard let peerDeviceID = localConnection.peerDeviceID else { continue }
            if now.timeIntervalSince(localConnection.lastSeenAt) > Self.localConnectionTimeout {
                logHandler?(.warning, "本地连接心跳超时：\(peerDeviceID)")
                localConnection.connection.cancel()
                remove(localConnection)
                continue
            }

            do {
                try localConnection.send(
                    DeviceRelayMessage(
                        type: .relayPing,
                        requestId: "local-heartbeat-\(UUID().uuidString.lowercased())",
                        fromDeviceId: localDeviceID,
                        targetDeviceId: peerDeviceID,
                        payload: [:]
                    )
                )
            } catch {
                remove(localConnection)
            }
        }
    }

    private static var localConnectionTimeout: TimeInterval {
        DevBarCoreConstants.DeviceRelay.localHeartbeatInterval * 3
    }

    private func sanitizedServiceName(_ value: String) -> String {
        String(value.prefix(63))
    }

    private static func proof(secret: String, nonce: String, fromDeviceID: String, targetDeviceID: String) -> String {
        let input = "\(nonce)|\(fromDeviceID)|\(targetDeviceID)"
        let key = SymmetricKey(data: Data(secret.utf8))
        let signature = HMAC<SHA256>.authenticationCode(for: Data(input.utf8), using: key)
        return Data(signature).hexString
    }

    private static func randomToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 24)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64URLEncodedString()
    }
}

private extension NWEndpoint {
    var bonjourServiceName: String? {
        if case let .service(name: name, type: _, domain: _, interface: _) = self {
            return name
        }
        return nil
    }
}

private final class LocalConnection: @unchecked Sendable {
    enum Role {
        case server
        case client
    }

    let id: ObjectIdentifier
    let connection: NWConnection
    let role: Role
    let expectedPeerID: String?
    var peerDeviceID: String?
    var pendingNonce: String?
    var lastSeenAt = Date()
    var messageHandler: ((DeviceRelayMessage) -> Void)?
    var closeHandler: (() -> Void)?

    private var buffer = Data()

    init(connection: NWConnection, role: Role, expectedPeerID: String? = nil) {
        self.id = ObjectIdentifier(connection)
        self.connection = connection
        self.role = role
        self.expectedPeerID = expectedPeerID
    }

    func start(on queue: DispatchQueue) {
        connection.start(queue: queue)
        receive()
    }

    func send(_ message: DeviceRelayMessage) throws {
        let text = try DeviceRelayMessageCodec.encode(message) + "\n"
        connection.send(
            content: Data(text.utf8),
            completion: .contentProcessed { [weak self] error in
                if error != nil {
                    self?.closeHandler?()
                }
            }
        )
    }

    private func receive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data, !data.isEmpty {
                self.buffer.append(data)
                self.emitBufferedMessages()
            }
            if isComplete || error != nil {
                self.closeHandler?()
                return
            }
            self.receive()
        }
    }

    private func emitBufferedMessages() {
        while let newlineIndex = buffer.firstIndex(of: 10) {
            let line = buffer[..<newlineIndex]
            buffer.removeSubrange(...newlineIndex)
            guard !line.isEmpty,
                  let message = try? DeviceRelayMessageCodec.decode(Data(line)) else {
                continue
            }
            messageHandler?(message)
        }
    }
}

private extension Data {
    var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}
