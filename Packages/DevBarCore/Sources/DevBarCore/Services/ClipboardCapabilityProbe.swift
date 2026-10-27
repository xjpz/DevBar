import Foundation

public struct ClipboardPeerCapability: Equatable, Sendable {
    public let version: Int
    public let state: String?
}

/// A capability belongs to the reply to this request, not a CPU timestamp or an online flag.
@MainActor
final class ClipboardCapabilityProbe {
    private struct Pending {
        var peerID: String
        var localID: String
        var continuation: CheckedContinuation<ClipboardPeerCapability, Error>
        var timeout: Task<Void, Never>
    }
    private var pending: [String: Pending] = [:]
    var diagnosticURL: URL?

    func isPending(_ requestID: String) -> Bool { pending[requestID] != nil }

    func request(peerID: String, localID: String, timeout: Duration = .seconds(8),
                 send: @escaping (String) async throws -> Void) async throws -> ClipboardPeerCapability {
        let id = "clipboard-capability-\(UUID().uuidString)"
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                let timer = Task { @MainActor [weak self] in
                    do { try await Task.sleep(for: timeout) } catch { return }
                    self?.finish(id, result: .failure(ClipboardFailure.timeout))
                }
                pending[id] = Pending(peerID: peerID, localID: localID, continuation: continuation, timeout: timer)
                record(id, peerID: peerID, outcome: "requesting")
                Task { @MainActor [weak self] in
                    do { try await send(id) }
                    catch { self?.finish(id, result: .failure(error)) }
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.finish(id, result: .failure(ClipboardFailure.cancelled)) }
        }
    }

    func receive(_ message: DeviceRelayMessage) {
        guard message.type == .systemStatus, let id = message.requestId, let item = pending[id],
              message.fromDeviceId == item.peerID, message.targetDeviceId == item.localID else { return }
        guard let raw = message.payload["clipboardVersion"], let version = Int(raw), version == 1 else {
            // Only a matching, actual status reply can establish an unsupported peer.
            finish(id, result: .failure(ClipboardFailure.unsupported))
            return
        }
        finish(id, result: .success(ClipboardPeerCapability(version: version, state: message.payload["clipboardState"])))
    }

    private func finish(_ id: String, result: Result<ClipboardPeerCapability, Error>) {
        guard let item = pending.removeValue(forKey: id) else { return }
        item.timeout.cancel()
        switch result {
        case .success(let capability):
            record(id, peerID: item.peerID, outcome: "supported", version: capability.version)
        case .failure(let error):
            record(id, peerID: item.peerID, outcome: (error as? ClipboardFailure)?.rawValue ?? "connectionFailed")
        }
        item.continuation.resume(with: result)
    }

    /// Debug-only, one bounded metadata file. Never contains tokens, payloads, previews or search terms.
    private func record(_ id: String, peerID: String, outcome: String, version: Int? = nil) {
#if DEBUG
        guard let diagnosticURL else { return }
        let values: [String: String] = [
            "requestID": id, "peerID": String(peerID.prefix(128)), "outcome": outcome,
            "version": version.map(String.init) ?? "", "timestamp": ISO8601DateFormatter().string(from: Date()),
        ]
        do {
            let directory = diagnosticURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
            try JSONEncoder().encode(values).write(to: diagnosticURL, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: diagnosticURL.path)
        } catch { /* Diagnostics must never interrupt sharing or expose errors containing payloads. */ }
#endif
    }
}
