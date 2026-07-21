import Foundation
import Testing
@testable import DevBarCore

@Test
func codexAuthFileLoaderReadsAccessRefreshAndAccountMetadata() throws {
    let data = Data(
        """
        {
          "auth_mode": "chatgpt",
          "tokens": {
            "access_token": " access-token ",
            "refresh_token": "refresh-token",
            "account_id": " account-1 "
          }
        }
        """.utf8
    )

    let credential = try CodexAuthFileLoader.decodeOpenAICredential(from: data)

    #expect(credential.accessToken == "access-token")
    #expect(credential.accountID == "account-1")
    #expect(credential.hasRefreshToken)
}
