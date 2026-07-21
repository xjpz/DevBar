import Testing
@testable import DevBarCore

struct ProviderCredentialSyncTrackerTests {
    @Test func retriesUntilAppliedAcknowledgementReachesCredentialRevision() {
        var tracker = ProviderCredentialSyncTracker()

        #expect(tracker.shouldSend(peerDeviceID: "iphone-1", accountID: "openai-1", provider: .openai, revision: 2))

        let failed = DeviceRelayProviderSyncAck(
            accountID: "openai-1",
            provider: .openai,
            status: "failed",
            revision: 2
        )
        tracker.recordSend(
            requestID: "credential-failed",
            peerDeviceID: "iphone-1",
            accountID: "openai-1",
            provider: .openai,
            revision: 2
        )
        let failedCompleted = tracker.recordAcknowledgement(
            requestID: "credential-failed",
            peerDeviceID: "iphone-1",
            acknowledgement: failed
        )
        #expect(!failedCompleted)
        #expect(tracker.shouldSend(peerDeviceID: "iphone-1", accountID: "openai-1", provider: .openai, revision: 2))

        let applied = DeviceRelayProviderSyncAck(
            accountID: "openai-1",
            provider: .openai,
            status: "applied",
            revision: 2
        )
        tracker.recordSend(
            requestID: "credential-applied",
            peerDeviceID: "iphone-1",
            accountID: "openai-1",
            provider: .openai,
            revision: 2
        )
        let appliedCompleted = tracker.recordAcknowledgement(
            requestID: "credential-applied",
            peerDeviceID: "iphone-1",
            acknowledgement: applied
        )
        #expect(appliedCompleted)
        #expect(!tracker.shouldSend(peerDeviceID: "iphone-1", accountID: "openai-1", provider: .openai, revision: 2))
        #expect(tracker.shouldSend(peerDeviceID: "iphone-1", accountID: "openai-1", provider: .openai, revision: 3))
    }

    @Test func acknowledgementIsScopedByPeerAndAccount() {
        var tracker = ProviderCredentialSyncTracker()
        let acknowledgement = DeviceRelayProviderSyncAck(
            accountID: "openai-1",
            provider: .openai,
            status: "stale",
            revision: 4
        )

        tracker.recordSend(
            requestID: "credential-stale",
            peerDeviceID: "iphone-1",
            accountID: "openai-1",
            provider: .openai,
            revision: 4
        )
        let staleCompleted = tracker.recordAcknowledgement(
            requestID: "credential-stale",
            peerDeviceID: "iphone-1",
            acknowledgement: acknowledgement
        )
        #expect(staleCompleted)
        #expect(!tracker.shouldSend(peerDeviceID: "iphone-1", accountID: "openai-1", provider: .openai, revision: 4))
        #expect(tracker.shouldSend(peerDeviceID: "iphone-2", accountID: "openai-1", provider: .openai, revision: 4))
        #expect(tracker.shouldSend(peerDeviceID: "iphone-1", accountID: "openai-2", provider: .openai, revision: 4))
        #expect(tracker.shouldSend(peerDeviceID: "iphone-1", accountID: "openai-1", provider: .glm, revision: 4))
    }

    @Test func ignoresAcknowledgementsForAccountAndQuotaMessages() {
        var tracker = ProviderCredentialSyncTracker()
        tracker.recordSend(
            requestID: "credential-request",
            peerDeviceID: "iphone-1",
            accountID: "openai-1",
            provider: .openai,
            revision: 2
        )
        let unrelated = DeviceRelayProviderSyncAck(
            accountID: "openai-1",
            provider: .openai,
            status: "applied",
            revision: 999
        )

        let unrelatedCompleted = tracker.recordAcknowledgement(
            requestID: "account-upsert-request",
            peerDeviceID: "iphone-1",
            acknowledgement: unrelated
        )
        #expect(!unrelatedCompleted)
        #expect(tracker.shouldSend(peerDeviceID: "iphone-1", accountID: "openai-1", provider: .openai, revision: 2))
    }
}
