import Combine
import Foundation
import Security

@MainActor
public final class DeviceRelayManager: ObservableObject {
    @Published public private(set) var localDeviceID: String?
    @Published public private(set) var deviceToken: String?
    @Published public private(set) var peers: [DeviceRelayDevice] = []
    @Published public private(set) var pairQRCodePayload: DeviceRelayPairQRCodePayload?
    @Published public private(set) var connectionState: DeviceRelayConnectionState = .disconnected
    @Published public private(set) var activeTransport: DeviceRelayActiveTransport = .none
    @Published public private(set) var localConnectedPeerIDs: Set<String> = []
    @Published public private(set) var peerRuntimeStates: [String: DeviceRelayPeerRuntimeState] = [:]
    @Published public private(set) var receivedMessages: [DeviceRelayMessage] = []
    @Published public private(set) var agentTasks: [DeviceRelayAgentTask] = []
    @Published public private(set) var logLines: [DeviceRelayLogEntry] = []
    @Published public private(set) var lastErrorMessage: String?

    private let service: DeviceRelayService
    private let store: DeviceRelayStore
    private let localTransport = DeviceRelayLocalTransport()
    private var socketTask: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?
    private var heartbeatTask: Task<Void, Never>?
    private var deviceType: DeviceRelayDeviceType?
    private var deviceName: String?
    public var messageHandler: ((DeviceRelayMessage) -> Void)?

    public init(
        service: DeviceRelayService = .shared,
        store: DeviceRelayStore = DeviceRelayStore()
    ) {
        self.service = service
        self.store = store
        self.deviceToken = store.loadDeviceToken()
        bindLocalTransport()
    }

    public var onlinePeers: [DeviceRelayDevice] {
        peers.filter(\.online)
    }

    public func connectionStatus(for peer: DeviceRelayDevice, now: Date = Date()) -> DeviceRelayPeerConnectionStatus {
        if localConnectedPeerIDs.contains(peer.deviceId) {
            return .local
        }
        if isRemotePeerReachable(peer, now: now) {
            return .remote
        }
        return .offline
    }

    public func isPeerReachable(_ peer: DeviceRelayDevice, now: Date = Date()) -> Bool {
        connectionStatus(for: peer, now: now) != .offline
    }

    public func displayName(for peer: DeviceRelayDevice) -> String {
        if let runtimeName = normalizedDeviceName(peerRuntimeStates[peer.deviceId]?.displayName) {
            return runtimeName
        }
        if let peerName = normalizedDeviceName(peer.deviceName) {
            return peerName
        }
        return peer.deviceType == .iPhone ? "iPhone" : peer.deviceId
    }

    public func screenLocked(for peer: DeviceRelayDevice) -> Bool? {
        peerRuntimeStates[peer.deviceId]?.screenLocked
    }

#if DEBUG
    func setConnectedForTesting() {
        connectionState = .connected
    }

    func recordAgentTaskForTesting(_ task: DeviceRelayAgentTask) {
        upsertAgentTask(task)
    }

    func handleMessageForTesting(_ message: DeviceRelayMessage) {
        markPeerRemoteSeen(from: message)
        handle(message)
    }
#endif

    public func setup(deviceType: DeviceRelayDeviceType, deviceName: String?) async {
        self.deviceType = deviceType
        self.deviceName = deviceName
        let deviceID = store.loadOrCreateDeviceID(for: deviceType)
        let secret = store.loadOrCreateDeviceSecret(for: deviceType)
        localDeviceID = deviceID
        appendLog(.info, "注册设备 \(deviceType.rawValue) \(deviceID)")

        do {
            let response = try await service.registerDevice(
                DeviceRelayRegistration(
                    deviceId: deviceID,
                    deviceType: deviceType,
                    deviceName: deviceName,
                    publicKey: nil,
                    deviceSecret: secret
                )
            )
            store.saveDeviceToken(response.deviceToken)
            deviceToken = response.deviceToken
            lastErrorMessage = nil
            appendLog(.success, "设备注册成功，开始刷新 peers")
            await refreshPeers()
            startLocalTransportIfPossible()
            connect()
        } catch {
            fail(error)
        }
    }

    public func createPairQRCode(deviceName: String?) async {
        if localDeviceID == nil || deviceToken == nil {
            await setup(deviceType: .mac, deviceName: deviceName)
        }

        guard let macDeviceID = localDeviceID else {
            fail(DeviceRelayError.missingDeviceID)
            return
        }
        guard let token = deviceToken else {
            fail(DeviceRelayError.missingDeviceToken)
            return
        }

        do {
            if connectionState != .connected {
                connect()
                try await waitUntilConnected(timeout: 8)
            }
            appendLog(.info, "请求生成 iPhone 配对码")
            let pairCode = try await service.createPairCode(macDeviceId: macDeviceID, deviceToken: token)
            let localSecret = Self.randomLocalSecret()
            store.savePendingLocalPairSecret(localSecret, pairCode: pairCode.pairCode)
            pairQRCodePayload = DeviceRelayPairQRCodePayload(
                relay: URL(string: DevBarCoreConstants.DeviceRelay.baseURL)!,
                pairCode: pairCode.pairCode,
                macDeviceId: macDeviceID,
                expiresAt: pairCode.expiresAt,
                localSecret: localSecret
            )
            lastErrorMessage = nil
            appendLog(.success, "配对码已生成：\(pairCode.pairCode)")
        } catch {
            fail(error)
        }
    }

    public func pairQRCodeString() throws -> String {
        guard let pairQRCodePayload else {
            throw DeviceRelayError.invalidQRCode
        }
        return try DeviceRelayPairQRCodeCodec.encode(pairQRCodePayload)
    }

    public func confirmPairing(from rawQRCode: String, deviceName: String?) async throws {
        let payload = try DeviceRelayPairQRCodeCodec.decode(rawQRCode)
        let deviceID = store.loadOrCreateDeviceID(for: .iPhone)
        localDeviceID = deviceID
        deviceType = .iPhone
        if let localSecret = payload.localSecret {
            store.saveLocalPairSecret(localSecret, peerDeviceID: payload.macDeviceId)
        }
        appendLog(.info, "确认 Mac 配对 \(payload.macDeviceId)")

        let pairingService = DeviceRelayService(baseURL: payload.relay)
        let response = try await pairingService.confirmPair(
            pairCode: payload.pairCode,
            macDeviceId: payload.macDeviceId,
            iphoneDeviceId: deviceID,
            iphoneDeviceName: deviceName,
            publicKey: nil
        )

        store.saveDeviceToken(response.deviceToken)
        deviceToken = response.deviceToken
        peers = [
            DeviceRelayDevice(
                deviceId: response.macDevice.deviceId,
                deviceType: .mac,
                deviceName: response.macDevice.deviceName,
                status: .online,
                online: true,
                lastSeenAt: Int64(Date().timeIntervalSince1970 * 1000)
            ),
        ]
        lastErrorMessage = nil
        appendLog(.success, "配对成功：\(response.macDevice.deviceName ?? response.macDevice.deviceId)")
        disconnect()
        startLocalTransportIfPossible()
        localTransport.restartDiscovery()
        connect(using: pairingService)
        await refreshPeers(using: pairingService)
    }

    public func refreshPeers() async {
        await refreshPeers(using: service)
    }

    public func resumeConnectivity(deviceType: DeviceRelayDeviceType, deviceName: String?) async {
        if localDeviceID == nil || deviceToken == nil {
            await setup(deviceType: deviceType, deviceName: deviceName)
            return
        }

        self.deviceType = deviceType
        self.deviceName = deviceName
        await refreshRegistration(deviceType: deviceType, deviceName: deviceName)
        startLocalTransportIfPossible()
        localTransport.restartDiscovery()

        if socketTask == nil || !connectionState.isConnected {
            connect()
        }

        await refreshPeers()
    }

    public func refreshPeers(using service: DeviceRelayService) async {
        guard let token = deviceToken else { return }
        do {
            peers = try await service.fetchPeers(deviceToken: token)
            promotePendingLocalSecretsIfNeeded()
            localTransport.updateTargetPeerIDs(Set(peers.map(\.deviceId)))
            lastErrorMessage = nil
            appendLog(.info, "已刷新 peers：\(peers.count) 台")
        } catch {
            fail(error)
        }
    }

    public func connect() {
        connect(using: service)
    }

    public func connect(using service: DeviceRelayService) {
        guard socketTask == nil else { return }
        guard let deviceID = localDeviceID else {
            fail(DeviceRelayError.missingDeviceID)
            return
        }
        guard let token = deviceToken else {
            fail(DeviceRelayError.missingDeviceToken)
            return
        }

        do {
            connectionState = .connecting
            let task = try service.makeWebSocketTask(deviceId: deviceID, deviceToken: token)
            socketTask = task
            task.resume()
            print("[DevBar:DeviceRelay] WebSocket connecting deviceId=\(deviceID)")
            appendLog(.info, "WebSocket 连接中：\(deviceID)")
            startReceiveLoop()
            startHeartbeat()
        } catch {
            fail(error)
        }
    }

    public func disconnect() {
        heartbeatTask?.cancel()
        receiveTask?.cancel()
        socketTask?.cancel(with: .goingAway, reason: nil)
        heartbeatTask = nil
        receiveTask = nil
        socketTask = nil
        connectionState = .disconnected
        activeTransport = localConnectedPeerIDs.isEmpty ? .none : .local
        appendLog(.info, "WebSocket 已断开")
    }

    public func stop() {
        disconnect()
        localTransport.stop()
        peers.removeAll()
        pairQRCodePayload = nil
        localConnectedPeerIDs.removeAll()
        peerRuntimeStates.removeAll()
        activeTransport = .none
        lastErrorMessage = nil
        appendLog(.info, "Mac 中继已关闭")
    }

    public func revokePair(peerDeviceID: String) async {
        guard let macDeviceID = localDeviceID else {
            fail(DeviceRelayError.missingDeviceID)
            return
        }
        guard let token = deviceToken else {
            fail(DeviceRelayError.missingDeviceToken)
            return
        }

        do {
            _ = try await service.revokePair(
                macDeviceId: macDeviceID,
                iphoneDeviceId: peerDeviceID,
                deviceToken: token
            )
            store.clearLocalPairSecret(peerDeviceID: peerDeviceID)
            localTransport.disconnect(peerDeviceID: peerDeviceID)
            peers.removeAll { $0.deviceId == peerDeviceID }
            peerRuntimeStates.removeValue(forKey: peerDeviceID)
            localConnectedPeerIDs.remove(peerDeviceID)
            localTransport.updateTargetPeerIDs(Set(peers.map(\.deviceId)))
            lastErrorMessage = nil
            appendLog(.success, "已删除 iPhone 连接：\(peerDeviceID)")
        } catch {
            fail(error)
        }
    }

    public func send(_ message: DeviceRelayMessage) async throws {
        if await sendUsingLocalTransportIfPossible(message) {
            return
        }

        if socketTask == nil {
            guard localDeviceID != nil else {
                throw DeviceRelayError.missingDeviceID
            }
            guard deviceToken != nil else {
                throw DeviceRelayError.missingDeviceToken
            }
            appendLog(.warning, "WebSocket 未连接，尝试重新连接")
            connect()
            try await waitUntilConnected(timeout: 8)
        }

        guard let socketTask else {
            throw DeviceRelayError.webSocketNotConnected
        }
        let text = try DeviceRelayMessageCodec.encode(message)
        do {
            try await socketTask.send(.string(text))
            activeTransport = .relay
            appendLog(.info, "发送 \(message.type.rawValue) requestId=\(message.requestId ?? "-")")
        } catch {
            self.socketTask = nil
            connectionState = .failed(error.localizedDescription)
            appendLog(.error, "WebSocket 发送失败：\(error.localizedDescription)")
            throw error
        }
    }

    @discardableResult
    public func sendAgentCommand(prompt: String, agent: String? = nil, workspace: String? = nil, targetDeviceId: String) async throws -> String {
        guard let localDeviceID else {
            throw DeviceRelayError.missingDeviceID
        }
        let normalizedAgent = Self.normalizedDeviceName(agent)
        let requestId = "task-\(UUID().uuidString.lowercased())"
        let task = DeviceRelayAgentTask(
            id: requestId,
            targetDeviceId: targetDeviceId,
            prompt: prompt,
            agent: normalizedAgent ?? "default",
            workspace: workspace,
            status: .pending
        )
        upsertAgentTask(task)

        do {
            try await send(
                Self.makeAgentCommandMessage(
                    localDeviceID: localDeviceID,
                    targetDeviceId: targetDeviceId,
                    requestId: requestId,
                    prompt: prompt,
                    agent: normalizedAgent,
                    workspace: workspace
                )
            )
            updateAgentTask(
                requestId: requestId,
                status: .running,
                progressMessage: "任务已发送到 Mac"
            )
            return requestId
        } catch {
            updateAgentTask(
                requestId: requestId,
                status: .failed,
                errorMessage: error.localizedDescription
            )
            throw error
        }
    }

    public static func makeAgentCommandMessage(
        localDeviceID: String,
        targetDeviceId: String,
        requestId: String,
        prompt: String,
        agent: String?,
        workspace: String? = nil
    ) -> DeviceRelayMessage {
        var payload = ["prompt": prompt]
        if let agent = normalizedDeviceName(agent) {
            payload["agent"] = agent
        }
        if let workspace = normalizedDeviceName(workspace) {
            payload["workspace"] = workspace
        }
        return DeviceRelayMessage(
            type: .agentCommand,
            requestId: requestId,
            fromDeviceId: localDeviceID,
            targetDeviceId: targetDeviceId,
            payload: payload
        )
    }

    public func sendLockScreenCommand(targetDeviceId: String) async throws {
        guard let localDeviceID else {
            throw DeviceRelayError.missingDeviceID
        }
        try await send(
            Self.makeLockScreenMessage(
                localDeviceID: localDeviceID,
                targetDeviceId: targetDeviceId
            )
        )
    }

    public func sendSystemStatusRequest(targetDeviceId: String) async throws {
        guard let localDeviceID else {
            throw DeviceRelayError.missingDeviceID
        }
        try await send(
            Self.makeSystemStatusRequestMessage(
                localDeviceID: localDeviceID,
                targetDeviceId: targetDeviceId,
                deviceName: deviceName
            )
        )
    }

    public func sendSystemStatus(
        targetDeviceId: String,
        requestId: String?,
        screenLocked: Bool?,
        deviceName: String?
    ) async throws {
        guard let localDeviceID else {
            throw DeviceRelayError.missingDeviceID
        }
        try await send(
            Self.makeSystemStatusMessage(
                localDeviceID: localDeviceID,
                targetDeviceId: targetDeviceId,
                requestId: requestId,
                screenLocked: screenLocked,
                deviceName: deviceName
            )
        )
    }

    private func startReceiveLoop() {
        receiveTask?.cancel()
        receiveTask = Task { @MainActor [weak self] in
            guard let self else { return }
            while !Task.isCancelled, let socketTask = self.socketTask {
                do {
                    let rawMessage = try await socketTask.receive()
                    let message: DeviceRelayMessage
                    switch rawMessage {
                    case let .string(text):
                        message = try DeviceRelayMessageCodec.decode(text)
                    case let .data(data):
                        message = try DeviceRelayMessageCodec.decode(data)
                    @unknown default:
                        continue
                    }
                    print("[DevBar:DeviceRelay] WebSocket received type=\(message.type.rawValue) requestId=\(message.requestId ?? "-")")
                    self.appendLog(.info, "收到 \(message.type.rawValue) requestId=\(message.requestId ?? "-")")
                    self.markPeerRemoteSeen(from: message)
                    self.handle(message)
                } catch {
                    guard !Task.isCancelled else { return }
                    guard let currentSocketTask = self.socketTask, currentSocketTask === socketTask else {
                        self.appendLog(.warning, "忽略旧 WebSocket 接收错误：\(error.localizedDescription)")
                        return
                    }
                    print("[DevBar:DeviceRelay] WebSocket receive failed: \(error)")
                    self.appendLog(.error, "WebSocket 接收失败：\(error.localizedDescription)")
                    self.socketTask = nil
                    self.fail(error)
                    return
                }
            }
        }
    }

    private func bindLocalTransport() {
        localTransport.messageHandler = { [weak self] message in
            guard let self else { return }
            self.appendLog(.info, "本地收到 \(message.type.rawValue) requestId=\(message.requestId ?? "-")")
            self.activeTransport = .local
            self.markPeerLocalSeen(from: message)
            self.handle(message)
        }
        localTransport.stateHandler = { [weak self] peerIDs in
            guard let self else { return }
            self.localConnectedPeerIDs = peerIDs
            self.markLocalPeerIDsSeen(peerIDs)
            if !peerIDs.isEmpty {
                self.activeTransport = .local
                self.lastErrorMessage = nil
            } else if self.connectionState == .connected {
                self.activeTransport = .relay
            } else {
                self.activeTransport = .none
            }
        }
        localTransport.logHandler = { [weak self] level, message in
            self?.appendLog(level, message)
        }
    }

    private func startLocalTransportIfPossible() {
        guard let deviceType, let localDeviceID else { return }
        localTransport.start(
            deviceType: deviceType,
            localDeviceID: localDeviceID,
            targetPeerIDs: Set(peers.map(\.deviceId)),
            secretProvider: { [store] peerDeviceID in
                store.loadLocalPairSecret(peerDeviceID: peerDeviceID)
            }
        )
    }

    private func sendUsingLocalTransportIfPossible(_ message: DeviceRelayMessage) async -> Bool {
        guard let targetDeviceID = message.targetDeviceId else { return false }
        if localTransport.connectedPeerIDs.contains(targetDeviceID) {
            return sendLocal(message)
        }
        if deviceType == .iPhone {
            let connected = await localTransport.waitForConnection(
                peerDeviceID: targetDeviceID,
                timeout: DevBarCoreConstants.DeviceRelay.localConnectTimeout
            )
            if connected {
                return sendLocal(message)
            }
        }
        return false
    }

    private func sendLocal(_ message: DeviceRelayMessage) -> Bool {
        do {
            guard try localTransport.send(message) else { return false }
            activeTransport = .local
            appendLog(.info, "本地发送 \(message.type.rawValue) requestId=\(message.requestId ?? "-")")
            return true
        } catch {
            appendLog(.warning, "本地发送失败，回退远程中继：\(error.localizedDescription)")
            return false
        }
    }

    private func startHeartbeat() {
        heartbeatTask?.cancel()
        heartbeatTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(DevBarCoreConstants.DeviceRelay.heartbeatInterval))
                guard let self, let localDeviceID = self.localDeviceID else { continue }
                try? await self.send(
                    Self.makeHeartbeatMessage(localDeviceID: localDeviceID, deviceName: self.deviceName)
                )
            }
        }
    }

    static func makeHeartbeatMessage(localDeviceID: String, deviceName: String? = nil) -> DeviceRelayMessage {
        var payload: [String: String] = [:]
        if let deviceName = normalizedDeviceName(deviceName) {
            payload["deviceName"] = deviceName
        }
        return DeviceRelayMessage(
            type: .relayPing,
            requestId: "heartbeat-\(UUID().uuidString.lowercased())",
            fromDeviceId: localDeviceID,
            targetDeviceId: nil,
            payload: payload
        )
    }

    public static func makeLockScreenMessage(localDeviceID: String, targetDeviceId: String) -> DeviceRelayMessage {
        DeviceRelayMessage(
            type: .systemLockScreen,
            requestId: "lock-\(UUID().uuidString.lowercased())",
            fromDeviceId: localDeviceID,
            targetDeviceId: targetDeviceId,
            payload: ["command": "lockScreen"]
        )
    }

    public static func makeSystemStatusRequestMessage(
        localDeviceID: String,
        targetDeviceId: String,
        deviceName: String? = nil
    ) -> DeviceRelayMessage {
        var payload: [String: String] = [:]
        if let deviceName = normalizedDeviceName(deviceName) {
            payload["deviceName"] = deviceName
        }
        return DeviceRelayMessage(
            type: .systemStatusRequest,
            requestId: "status-\(UUID().uuidString.lowercased())",
            fromDeviceId: localDeviceID,
            targetDeviceId: targetDeviceId,
            payload: payload
        )
    }

    public static func makeSystemStatusMessage(
        localDeviceID: String,
        targetDeviceId: String,
        requestId: String?,
        screenLocked: Bool?,
        deviceName: String?
    ) -> DeviceRelayMessage {
        var payload: [String: String] = [:]
        if let screenLocked {
            payload["screenLocked"] = screenLocked ? "true" : "false"
        }
        if let deviceName = normalizedDeviceName(deviceName) {
            payload["deviceName"] = deviceName
        }
        payload["timestamp"] = "\(Int64(Date().timeIntervalSince1970 * 1000))"
        return DeviceRelayMessage(
            type: .systemStatus,
            requestId: requestId ?? "status-\(UUID().uuidString.lowercased())",
            fromDeviceId: localDeviceID,
            targetDeviceId: targetDeviceId,
            payload: payload
        )
    }

    private func handle(_ message: DeviceRelayMessage) {
        switch message.type {
        case .relayConnected:
            connectionState = .connected
            activeTransport = localConnectedPeerIDs.isEmpty ? .relay : .local
            lastErrorMessage = nil
            appendLog(.success, "WebSocket 已连接")
        case .relayHeartbeat, .relayPong:
            connectionState = .connected
            activeTransport = localConnectedPeerIDs.isEmpty ? .relay : .local
            lastErrorMessage = nil
        case .systemStatus:
            receivedMessages.append(message)
            updatePeerRuntimeState(from: message)
        case .agentProgress:
            receivedMessages.append(message)
            updateAgentTask(
                requestId: message.requestId,
                status: .running,
                progressMessage: message.payload["message"] ?? message.payload["status"]
            )
        case .agentDone:
            receivedMessages.append(message)
            updateAgentTask(
                requestId: message.requestId,
                status: .succeeded,
                progressMessage: message.payload["message"],
                resultSummary: message.payload["summary"] ?? message.payload["result"]
            )
        case .agentFailed:
            receivedMessages.append(message)
            updateAgentTask(
                requestId: message.requestId,
                status: .failed,
                errorMessage: message.payload["message"] ?? message.payload["errorCode"]
            )
        case .relayPaired:
            Task { await refreshPeers() }
            receivedMessages.append(message)
            appendLog(.success, "收到配对成功通知")
        case .relayError:
            receivedMessages.append(message)
            let errorText = message.payload["message"] ?? message.payload["msg"] ?? message.payload["code"] ?? "relay.error"
            print("[DevBar:DeviceRelay] relay.error payload=\(message.payload)")
            lastErrorMessage = "中继服务错误：\(errorText)"
            appendLog(.error, "relay.error：\(errorText)")
        default:
            receivedMessages.append(message)
        }
        messageHandler?(message)
    }

    private func upsertAgentTask(_ task: DeviceRelayAgentTask) {
        if let index = agentTasks.firstIndex(where: { $0.id == task.id }) {
            agentTasks[index] = task
        } else {
            agentTasks.insert(task, at: 0)
        }
        if agentTasks.count > 50 {
            agentTasks.removeLast(agentTasks.count - 50)
        }
    }

    private func updateAgentTask(
        requestId: String?,
        status: DeviceRelayAgentTaskStatus,
        progressMessage: String? = nil,
        resultSummary: String? = nil,
        errorMessage: String? = nil
    ) {
        guard let requestId,
              let index = agentTasks.firstIndex(where: { $0.id == requestId }) else {
            return
        }
        agentTasks[index] = agentTasks[index].updating(
            status: status,
            progressMessage: progressMessage,
            resultSummary: resultSummary,
            errorMessage: errorMessage
        )
    }

    private func fail(_ error: Error) {
        let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        print("[DevBar:DeviceRelay] error=\(message)")
        lastErrorMessage = message
        connectionState = .failed(message)
        activeTransport = localConnectedPeerIDs.isEmpty ? .none : .local
        appendLog(.error, message)
    }

    private func promotePendingLocalSecretsIfNeeded() {
        guard deviceType == .mac,
              let pairQRCodePayload,
              let secret = store.loadPendingLocalPairSecret(pairCode: pairQRCodePayload.pairCode) else {
            return
        }
        let iPhonePeers = peers.filter { $0.deviceType == .iPhone }
        guard !iPhonePeers.isEmpty else { return }
        for peer in iPhonePeers where store.loadLocalPairSecret(peerDeviceID: peer.deviceId) == nil {
            store.saveLocalPairSecret(secret, peerDeviceID: peer.deviceId)
        }
        store.clearPendingLocalPairSecret(pairCode: pairQRCodePayload.pairCode)
    }

    private func refreshRegistration(deviceType: DeviceRelayDeviceType, deviceName: String?) async {
        guard let deviceID = localDeviceID else { return }
        let secret = store.loadOrCreateDeviceSecret(for: deviceType)
        do {
            let response = try await service.registerDevice(
                DeviceRelayRegistration(
                    deviceId: deviceID,
                    deviceType: deviceType,
                    deviceName: deviceName,
                    publicKey: nil,
                    deviceSecret: secret
                )
            )
            store.saveDeviceToken(response.deviceToken)
            deviceToken = response.deviceToken
            lastErrorMessage = nil
        } catch {
            appendLog(.warning, "刷新设备注册失败：\(error.localizedDescription)")
        }
    }

    private func markPeerRemoteSeen(from message: DeviceRelayMessage) {
        guard let peerDeviceID = message.fromDeviceId, peerDeviceID != localDeviceID else { return }
        updateRuntimeState(
            peerDeviceID: peerDeviceID,
            lastRemoteSeenAt: Date(timeIntervalSince1970: TimeInterval(message.timestamp) / 1000),
            displayName: message.payload["deviceName"],
            screenLocked: screenLockedPayload(from: message)
        )
    }

    private func markPeerLocalSeen(from message: DeviceRelayMessage) {
        guard let peerDeviceID = message.fromDeviceId, peerDeviceID != localDeviceID else { return }
        updateRuntimeState(
            peerDeviceID: peerDeviceID,
            lastLocalSeenAt: Date(),
            displayName: message.payload["deviceName"],
            screenLocked: screenLockedPayload(from: message)
        )
    }

    private func markLocalPeerIDsSeen(_ peerIDs: Set<String>) {
        let now = Date()
        for peerID in peerIDs {
            updateRuntimeState(peerDeviceID: peerID, lastLocalSeenAt: now)
        }
    }

    private func updatePeerRuntimeState(from message: DeviceRelayMessage) {
        guard let peerDeviceID = message.fromDeviceId, peerDeviceID != localDeviceID else { return }
        updateRuntimeState(
            peerDeviceID: peerDeviceID,
            displayName: message.payload["deviceName"],
            screenLocked: screenLockedPayload(from: message)
        )
    }

    private func updateRuntimeState(
        peerDeviceID: String,
        lastRemoteSeenAt: Date? = nil,
        lastLocalSeenAt: Date? = nil,
        displayName: String? = nil,
        screenLocked: Bool? = nil
    ) {
        let existing = peerRuntimeStates[peerDeviceID] ?? DeviceRelayPeerRuntimeState()
        peerRuntimeStates[peerDeviceID] = existing.updating(
            lastRemoteSeenAt: lastRemoteSeenAt,
            lastLocalSeenAt: lastLocalSeenAt,
            displayName: Self.normalizedDeviceName(displayName),
            screenLocked: screenLocked
        )
    }

    private func screenLockedPayload(from message: DeviceRelayMessage) -> Bool? {
        guard let value = message.payload["screenLocked"]?.lowercased() else { return nil }
        if ["true", "1", "yes"].contains(value) { return true }
        if ["false", "0", "no"].contains(value) { return false }
        return nil
    }

    private static func randomLocalSecret() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64URLEncodedString()
    }

    private func appendLog(_ level: DeviceRelayLogEntry.Level, _ message: String) {
        if shouldHideLogMessage(message) {
            return
        }
        logLines.append(DeviceRelayLogEntry(level: level, message: message))
        if logLines.count > 200 {
            logLines.removeFirst(logLines.count - 200)
        }
    }

    private func shouldHideLogMessage(_ message: String) -> Bool {
        message.contains(DeviceRelayMessageType.relayPing.rawValue) ||
            message.contains(DeviceRelayMessageType.relayPong.rawValue)
    }

    private func isRemotePeerReachable(_ peer: DeviceRelayDevice, now: Date) -> Bool {
        guard connectionState == .connected else { return false }
        if let runtimeSeenAt = peerRuntimeStates[peer.deviceId]?.lastRemoteSeenAt,
           now.timeIntervalSince(runtimeSeenAt) <= Self.remotePeerOnlineTTL {
            return true
        }
        guard peer.online else { return false }
        guard let lastSeenAt = peer.lastSeenAt else { return false }
        let lastSeenDate = Date(timeIntervalSince1970: TimeInterval(lastSeenAt) / 1000)
        return now.timeIntervalSince(lastSeenDate) <= Self.remotePeerOnlineTTL
    }

    private static var remotePeerOnlineTTL: TimeInterval {
        max(DevBarCoreConstants.DeviceRelay.heartbeatInterval * 3, 75)
    }

    private func normalizedDeviceName(_ value: String?) -> String? {
        Self.normalizedDeviceName(value)
    }

    private static func normalizedDeviceName(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmed, !trimmed.isEmpty else { return nil }
        return trimmed
    }

    private func waitUntilConnected(timeout: TimeInterval) async throws {
        if connectionState == .connected { return }
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            try await Task.sleep(for: .milliseconds(150))
            if connectionState == .connected { return }
            if case let .failed(message) = connectionState {
                throw DeviceRelayError.serverError(message)
            }
        }
        throw DeviceRelayError.connectionTimeout
    }
}
