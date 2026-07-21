import Foundation
import Testing
@testable import DevBarCore

@Test
func openAIQuotaOfflineErrorUsesRecognizableReason() {
    let message = OpenAIQuotaViewModel.displayMessage(
        for: URLError(.notConnectedToInternet)
    )

    #expect(message == "openai_network_offline")
}

@Test
func openAIQuotaDecodeErrorExplainsPossibleProtocolChange() {
    let message = OpenAIQuotaViewModel.displayMessage(
        for: APIError.decodingError(DecodingError.dataCorrupted(
            .init(codingPath: [], debugDescription: "changed response")
        ))
    )

    #expect(message == "openai_protocol_changed")
}
