import CryptoKit
import Foundation

/// One instance per app. Owns short-lived authenticated sessions, not clipboard history.
@MainActor
public final class ClipboardSharingCoordinator {
    public var authorization: (() -> ClipboardFailure?)?
    public var hostHandler: ((ClipboardRequest) async throws -> ClipboardResponse)?
    private weak var relay: DeviceRelayManager?
    private var identity: () -> String? = { nil }
    private var pairSecret: (String) -> String? = { _ in nil }
    private var sender: (DeviceRelayMessage, DeviceRelaySendPermit) async throws -> Void = { _, _ in
        throw ClipboardFailure.unavailable
    }
    private var sessions: [String: Session] = [:]
    private var pending: [String: Pending] = [:]
    private var handshakes: [String: Task<Void, Error>] = [:]
    private var lastRequests: [String: [Date]] = [:]
    private var generation = UUID()

    private struct Session {
        var id: String
        var salt: Data
        var expiresAt: Date
        var sent: UInt64 = 0
        var replay = ClipboardReplayWindow()
    }
    private struct Pending {
        var peer: String
        var sessionID: String
        var continuation: CheckedContinuation<ClipboardPacket, Error>
        var timeout: Task<Void, Never>
    }

    public init() {}

    init(identity: @escaping () -> String?, pairSecret: @escaping (String) -> String?,
         sender: @escaping (DeviceRelayMessage, DeviceRelaySendPermit) async throws -> Void) {
        self.identity = identity; self.pairSecret = pairSecret; self.sender = sender
    }

    func receiveForTesting(_ message: DeviceRelayMessage) async { await receive(message) }

    public func attach(to relay: DeviceRelayManager) {
        self.relay = relay
        identity = { [weak relay] in relay?.localDeviceID }
        pairSecret = { [weak relay] peer in relay?.clipboardPairSecret(for: peer) }
        sender = { [weak relay] message, permit in
            guard let relay else { throw ClipboardFailure.unavailable }
            try await relay.send(message, permit: permit)
        }
        relay.clipboardMessageHandler = { [weak self] message in
            Task { @MainActor [weak self] in await self?.receive(message) }
        }
    }

    public func reset() {
        generation = UUID()
        sessions.removeAll()
        handshakes.values.forEach { $0.cancel() }
        handshakes.removeAll()
        let items = Array(pending.values)
        pending.removeAll()
        for item in items {
            item.timeout.cancel()
            item.continuation.resume(throwing: ClipboardFailure.cancelled)
        }
    }

    public func perform(_ request: ClipboardRequest, to peer: String) async throws -> ClipboardResponse {
        guard hostHandler == nil else { throw ClipboardFailure.invalidMessage }
        try Task.checkCancellation()
        if sessions[peer].map({ $0.expiresAt <= Date() }) ?? true {
            if let task = handshakes[peer] { try await task.value }
            else {
                let token = generation
                let task = Task { @MainActor in try await self.handshake(peer) }
                handshakes[peer] = task
                do { try await task.value; if token == generation { handshakes[peer] = nil } }
                catch { if token == generation { handshakes[peer] = nil }; throw error }
            }
        }
        guard let session = sessions[peer] else { throw ClipboardFailure.unavailable }
        let response = try await exchange(ClipboardPacket(kind: .request, request: request),
                                           peer: peer, sessionID: session.id, bootstrap: false)
        if let failure = response.failure { throw failure }
        guard response.kind == .response, let value = response.response else { throw ClipboardFailure.invalidMessage }
        return value
    }

    private func handshake(_ peer: String) async throws {
        let id = try ClipboardRandom.bytes().base64EncodedString()
        let clientNonce = try ClipboardRandom.bytes()
        let token = generation
        let response = try await exchange(ClipboardPacket(kind: .hello, nonce: clientNonce),
                                           peer: peer, sessionID: id, bootstrap: true)
        if let failure = response.failure { throw failure }
        guard token == generation, response.kind == .helloAck, let serverNonce = response.nonce,
              serverNonce.count == 32 else { throw ClipboardFailure.invalidMessage }
        sessions[peer] = Session(id: id, salt: clientNonce + serverNonce, expiresAt: Date().addingTimeInterval(300))
    }

    private func exchange(_ packet: ClipboardPacket, peer: String, sessionID: String,
                          bootstrap: Bool) async throws -> ClipboardPacket {
        let requestID = "clipboard-\(UUID().uuidString)"
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let timeout = Task { @MainActor [weak self] in
                    do { try await Task.sleep(for: .seconds(8)) } catch { return }
                    self?.finish(requestID, result: .failure(ClipboardFailure.timeout))
                }
                pending[requestID] = Pending(peer: peer, sessionID: sessionID, continuation: continuation, timeout: timeout)
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    do { try await post(packet, peer: peer, requestID: requestID, sessionID: sessionID, bootstrap: bootstrap) }
                    catch { finish(requestID, result: .failure(error)) }
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.finish(requestID, result: .failure(ClipboardFailure.cancelled)) }
        }
    }

    private func finish(_ id: String, result: Result<ClipboardPacket, Error>) {
        guard let item = pending.removeValue(forKey: id) else { return }
        item.timeout.cancel()
        item.continuation.resume(with: result)
    }

    private func post(_ packet: ClipboardPacket, peer: String, requestID: String,
                      sessionID: String, bootstrap: Bool) async throws {
        guard let local = identity(), let secret = pairSecret(peer) else { throw ClipboardFailure.rePair }
        var sequence: UInt64 = 0
        var salt = Data()
        if !bootstrap {
            guard var session = sessions[peer], session.id == sessionID, session.expiresAt > Date() else {
                throw ClipboardFailure.unavailable
            }
            session.sent += 1; sequence = session.sent; salt = session.salt
            sessions[peer] = session
        }
        let key = try ClipboardSharingCodec.key(secret: secret, from: local, to: peer, salt: salt)
        let encoded = try ClipboardSharingCodec.seal(packet, key: key, from: local, to: peer, requestID: requestID,
                                                    sessionID: sessionID, sequence: sequence, bootstrap: bootstrap)
        let token = generation
        let requiresHostAccess = packet.kind == .response || packet.kind == .helloAck
        let permit = DeviceRelaySendPermit { [weak self] in
            guard let self, self.generation == token, self.pairSecret(peer) != nil else { return false }
            return !requiresHostAccess || self.authorization?() == nil
        }
        try await sender(DeviceRelayMessage(type: .clipboardSecure, requestId: requestID, fromDeviceId: local,
                                            targetDeviceId: peer, payload: ["encoded": encoded]), permit)
    }

    private func receive(_ message: DeviceRelayMessage) async {
        guard let local = identity(), message.targetDeviceId == local,
              let peer = message.fromDeviceId, let secret = pairSecret(peer),
              let id = message.requestId, id.utf8.count <= 128,
              let encoded = message.payload["encoded"] else { return }
        // Invalid ciphertext is discarded without printing any part of the packet.
        do {
            let envelope = try ClipboardSharingCodec.envelope(encoded)
            var salt = Data()
            if !envelope.bootstrap {
                guard let session = sessions[peer], session.id == envelope.sessionID, session.expiresAt > Date() else {
                    if hostHandler != nil {
                        try? await post(ClipboardPacket(kind: .error, failure: authorization?() ?? .unavailable),
                                        peer: peer, requestID: id, sessionID: envelope.sessionID, bootstrap: true)
                    }
                    return
                }
                salt = session.salt
            }
            let key = try ClipboardSharingCodec.key(secret: secret, from: peer, to: local, salt: salt)
            let packet = try ClipboardSharingCodec.open(envelope, key: key, from: peer, to: local, requestID: id)
            if !envelope.bootstrap {
                guard var session = sessions[peer] else { return }
                try session.replay.accept(envelope.sequence)
                sessions[peer] = session
            }
            if let item = pending[id], item.peer == peer, item.sessionID == envelope.sessionID {
                guard packet.kind == .response || packet.kind == .helloAck || packet.kind == .error else { return }
                if packet.failure != nil { sessions[peer] = nil }
                finish(id, result: .success(packet))
                return
            }
            guard let hostHandler else { return }
            let now = Date()
            var requests = (lastRequests[peer] ?? []).filter { now.timeIntervalSince($0) < 1 }
            guard requests.count < 8 else {
                try await post(ClipboardPacket(kind: .error, failure: .rateLimited), peer: peer, requestID: id,
                               sessionID: envelope.sessionID, bootstrap: envelope.bootstrap)
                return
            }
            requests.append(now); lastRequests[peer] = requests
            if let failure = authorization?() {
                try await post(ClipboardPacket(kind: .error, failure: failure), peer: peer, requestID: id,
                               sessionID: envelope.sessionID, bootstrap: envelope.bootstrap)
                return
            }
            if packet.kind == .hello, envelope.bootstrap, let clientNonce = packet.nonce, clientNonce.count == 32 {
                let serverNonce = try ClipboardRandom.bytes()
                sessions = sessions.filter { $0.value.expiresAt > now }
                guard sessions.count < 8 || sessions[peer] != nil else { return }
                sessions[peer] = Session(id: envelope.sessionID, salt: clientNonce + serverNonce,
                                          expiresAt: now.addingTimeInterval(300))
                try await post(ClipboardPacket(kind: .helloAck, nonce: serverNonce), peer: peer, requestID: id,
                               sessionID: envelope.sessionID, bootstrap: true)
            } else if packet.kind == .request, !envelope.bootstrap, let request = packet.request {
                let token = generation
                let result: ClipboardPacket
                do { result = ClipboardPacket(kind: .response, response: try await hostHandler(request)) }
                catch { result = ClipboardPacket(kind: .error, failure: error as? ClipboardFailure ?? .storage) }
                guard token == generation, authorization?() == nil,
                      pairSecret(peer) != nil else { return }
                do {
                    try await post(result, peer: peer, requestID: id, sessionID: envelope.sessionID, bootstrap: false)
                } catch ClipboardFailure.tooLarge {
                    try await post(ClipboardPacket(kind: .error, failure: .tooLarge), peer: peer, requestID: id,
                                   sessionID: envelope.sessionID, bootstrap: false)
                }
            }
        } catch { /* Never log ciphertext, plaintext, search terms, or keys. */ }
    }
}
