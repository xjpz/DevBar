import Foundation
import Testing
@testable import DevBarCore

@Test
func transferImportPreviewFlagsCredentialReplacementAndDisableConflict() {
    let payload = TransferPayload(
        exportedAt: Date(timeIntervalSince1970: 1_700_000_000),
        expiresAt: Date(timeIntervalSince1970: 4_100_000_000),
        deviceName: "My Mac",
        accountConfigs: [
            AccountConfig(provider: .glm, isEnabled: false, order: 1),
        ],
        providers: [
            ProviderTransferPayload(
                provider: .glm,
                credentials: ProviderTransferCredentials(token: "glm-token", cookieString: "cookie=value")
            ),
        ]
    )

    let preview = TransferImportPlanner.makePreview(
        payload: payload,
        localStates: [
            LocalProviderState(provider: .glm, isEnabled: true, hasCredential: true),
        ],
        existingConfigs: [
            AccountConfig(provider: .glm, isEnabled: true, order: 0),
        ]
    )

    #expect(preview.hasConflicts)
    #expect(preview.providerChanges.count == 1)
    #expect(preview.providerChanges[0].credentialAction == .replaceExisting)
    #expect(preview.providerChanges[0].configAction == .disable)
}

@Test
func transferImportPreviewTreatsAccountIdentifierChangeAsConflict() {
    let payload = TransferPayload(
        exportedAt: Date(timeIntervalSince1970: 1_700_000_000),
        expiresAt: Date(timeIntervalSince1970: 4_100_000_000),
        deviceName: "My Mac",
        accountConfigs: [
            AccountConfig(provider: .openai, isEnabled: true, order: 1),
        ],
        providers: [
            ProviderTransferPayload(
                provider: .openai,
                credentials: ProviderTransferCredentials(token: "openai-token"),
                accountId: "acct_123"
            ),
        ]
    )

    let preview = TransferImportPlanner.makePreview(
        payload: payload,
        localStates: [
            LocalProviderState(provider: .openai, isEnabled: false, hasCredential: false),
        ],
        existingConfigs: [
            AccountConfig(provider: .glm, isEnabled: true, order: 0),
            AccountConfig(provider: .openai, isEnabled: false, order: 1),
        ]
    )

    #expect(preview.hasConflicts)
    #expect(preview.providerChanges[0].credentialAction == .importNew)
    #expect(preview.providerChanges[0].configAction == .enable)
    #expect(preview.providerChanges[0].accountIdentifierChanged)
}
