import Foundation
import Testing

struct ProviderCredentialRelayReliabilityTests {
    @Test func macTracksCredentialAcknowledgementsAndReplaysOnReconnect() throws {
        let content = try source("DevBar/ViewModels/AppViewModel.swift")

        #expect(content.contains("case .providerSyncAck:"))
        #expect(content.contains("providerCredentialSyncTracker.recordAcknowledgement("))
        #expect(content.contains("providerCredentialSyncTracker.recordSend("))
        #expect(content.contains("$0.syncPolicy.quotaSyncEnabled || $0.syncPolicy.credentialSyncEnabled"))
        #expect(content.contains("await sendProviderCredentialIfNeeded("))
    }

    @Test func iPhoneExplainsCredentialRejectionsInsteadOfSilentlyDroppingThem() throws {
        let content = try source("DevBariOS/ViewModels/IOSAppViewModel.swift")

        #expect(content.contains("status: \"missing_account\""))
        #expect(content.contains("status: \"disabled\""))
        #expect(content.contains("status: saved ? \"applied\" : \"failed\""))
    }

    private func source(_ relativePath: String) throws -> String {
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: projectRoot.appending(path: relativePath),
            encoding: .utf8
        )
    }
}
