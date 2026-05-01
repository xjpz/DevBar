import Foundation
import Testing
@testable import DevBarCore

@Test
func transferPayloadCodecRoundTripsPayload() throws {
    let payload = TransferPayload(
        exportedAt: Date(timeIntervalSince1970: 1_700_000_000),
        expiresAt: Date(timeIntervalSince1970: 4_100_000_000),
        deviceName: "My Mac",
        accountConfigs: [
            AccountConfig(provider: .glm, isEnabled: true, order: 0),
            AccountConfig(provider: .openai, isEnabled: true, order: 1),
        ],
        providers: [
            ProviderTransferPayload(
                provider: .glm,
                credentials: ProviderTransferCredentials(token: "glm-token", cookieString: "cookie=value")
            ),
            ProviderTransferPayload(
                provider: .openai,
                credentials: ProviderTransferCredentials(token: "openai-token"),
                accountId: "acct_123"
            ),
        ]
    )

    let url = try TransferPayloadCodec.makeURL(for: payload)
    let decoded = try TransferPayloadCodec.decode(from: url)

    #expect(decoded == payload)
}

@Test
func transferPayloadCodecRejectsExpiredPayload() throws {
    let payload = TransferPayload(
        exportedAt: Date(timeIntervalSince1970: 1_700_000_000),
        expiresAt: Date(timeIntervalSince1970: 1_700_000_100),
        deviceName: "Old Mac",
        accountConfigs: [AccountConfig(provider: .glm, isEnabled: true, order: 0)],
        providers: [
            ProviderTransferPayload(
                provider: .glm,
                credentials: ProviderTransferCredentials(token: "glm-token")
            ),
        ]
    )

    let url = try TransferPayloadCodec.makeURL(for: payload)

    #expect(throws: TransferPayloadError.expired) {
        try TransferPayloadCodec.decode(from: url)
    }
}
