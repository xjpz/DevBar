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

@Test
func transferPayloadCodecBuildsRelayURL() throws {
    let url = try TransferPayloadCodec.makeRelayURL(
        transferID: "tr_abc",
        readToken: "rt_read",
        encryptionKey: "ek_key"
    )

    #expect(url.absoluteString == "devbar://transfer/relay?id=tr_abc&token=rt_read#key=ek_key")
    #expect(TransferPayloadCodec.isRelayTransferURL(url.absoluteString))
}

@Test
func transferPayloadCodecRejectsRelayURLWithoutKey() async throws {
    let url = "devbar://transfer/relay?id=tr_abc&token=rt_read"

    await #expect(throws: TransferPayloadError.missingRelayParameters) {
        try await TransferPayloadCodec.decodeResolvingRelay(from: url)
    }
}
