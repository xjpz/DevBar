import Testing
@testable import DevBarCore

@MainActor
private func clipboardCapabilityReply(_ id: String, from: String = "mac", to: String = "phone",
                                      fields: [String: String]) -> DeviceRelayMessage {
    DeviceRelayMessage(type: .systemStatus, requestId: id, fromDeviceId: from, targetDeviceId: to, payload: fields)
}

@Test @MainActor func clipboardCapabilityDoesNotDependOnCPUMetrics() async throws {
    let probe = ClipboardCapabilityProbe()
    let capability = try await probe.request(peerID: "mac", localID: "phone") { id in
        probe.receive(clipboardCapabilityReply(id, fields: ["clipboardVersion": "1", "clipboardState": "ready"]))
    }
    #expect(capability.version == 1)
    #expect(capability.state == "ready")
}

@Test @MainActor func clipboardCapabilityIgnoresUnrelatedStatusAndOtherPeers() async throws {
    let probe = ClipboardCapabilityProbe()
    let capability = try await probe.request(peerID: "mac", localID: "phone") { id in
        probe.receive(clipboardCapabilityReply("unrelated-status", fields: [:]))
        probe.receive(clipboardCapabilityReply(id, from: "other-mac", fields: [:]))
        probe.receive(clipboardCapabilityReply(id, to: "other-phone", fields: [:]))
        probe.receive(clipboardCapabilityReply(id, fields: ["clipboardVersion": "1", "clipboardState": "ready"]))
    }
    #expect(capability.version == 1)
}

@Test @MainActor func clipboardCapabilitySilenceIsTimeoutNotUnsupported() async {
    let probe = ClipboardCapabilityProbe()
    await #expect(throws: ClipboardFailure.timeout) {
        try await probe.request(peerID: "mac", localID: "phone", timeout: .milliseconds(10)) { _ in }
    }
}

@Test @MainActor func clipboardCapabilityActualLegacyReplyIsUnsupported() async {
    let probe = ClipboardCapabilityProbe()
    await #expect(throws: ClipboardFailure.unsupported) {
        try await probe.request(peerID: "mac", localID: "phone") { id in
            probe.receive(clipboardCapabilityReply(id, fields: ["cpuPercent": "10"]))
        }
    }
}

@Test @MainActor func clipboardCapabilityConnectionFailureIsNotAnUpgradeRequirement() async {
    let probe = ClipboardCapabilityProbe()
    await #expect(throws: ClipboardFailure.unavailable) {
        try await probe.request(peerID: "mac", localID: "phone") { _ in throw ClipboardFailure.unavailable }
    }
}

@Test @MainActor func clipboardCapabilityRecoversWhenMacSharingIsEnabled() async throws {
    let probe = ClipboardCapabilityProbe()
    let disabled = try await probe.request(peerID: "mac", localID: "phone") { id in
        probe.receive(clipboardCapabilityReply(id, fields: ["clipboardVersion": "1", "clipboardState": "disabled"]))
    }
    #expect(disabled.state == "disabled")
    let ready = try await probe.request(peerID: "mac", localID: "phone") { id in
        probe.receive(clipboardCapabilityReply(id, fields: ["clipboardVersion": "1", "clipboardState": "ready"]))
    }
    #expect(ready.state == "ready")
}
