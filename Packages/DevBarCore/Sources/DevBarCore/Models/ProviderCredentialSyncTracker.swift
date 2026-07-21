import Foundation

public struct ProviderCredentialSyncTracker: Sendable {
    private var acknowledgedRevisions: [Key: Int] = [:]
    private var pendingByRequestID: [String: PendingSend] = [:]

    public init() {}

    public func shouldSend(
        peerDeviceID: String,
        accountID: String,
        provider: QuotaProvider,
        revision: Int
    ) -> Bool {
        acknowledgedRevisions[
            Key(peerDeviceID: peerDeviceID, accountID: accountID, provider: provider),
            default: 0
        ] < revision
    }

    public mutating func recordSend(
        requestID: String,
        peerDeviceID: String,
        accountID: String,
        provider: QuotaProvider,
        revision: Int
    ) {
        pendingByRequestID = pendingByRequestID.filter {
            $0.value.peerDeviceID != peerDeviceID
                || $0.value.accountID != accountID
                || $0.value.provider != provider
        }
        pendingByRequestID[requestID] = PendingSend(
            peerDeviceID: peerDeviceID,
            accountID: accountID,
            provider: provider,
            revision: revision
        )
    }

    @discardableResult
    public mutating func recordAcknowledgement(
        requestID: String,
        peerDeviceID: String,
        acknowledgement: DeviceRelayProviderSyncAck
    ) -> Bool {
        guard let pending = pendingByRequestID.removeValue(forKey: requestID),
              pending.peerDeviceID == peerDeviceID,
              pending.accountID == acknowledgement.accountID,
              pending.provider == acknowledgement.provider,
              pending.revision == acknowledgement.revision else {
            return false
        }
        guard acknowledgement.status == "applied" || acknowledgement.status == "stale" else {
            return false
        }

        let key = Key(
            peerDeviceID: peerDeviceID,
            accountID: acknowledgement.accountID,
            provider: acknowledgement.provider
        )
        acknowledgedRevisions[key] = max(
            acknowledgedRevisions[key, default: 0],
            acknowledgement.revision
        )
        return true
    }

    private struct Key: Hashable, Sendable {
        let peerDeviceID: String
        let accountID: String
        let provider: QuotaProvider
    }

    private struct PendingSend: Sendable {
        let peerDeviceID: String
        let accountID: String
        let provider: QuotaProvider
        let revision: Int
    }
}
