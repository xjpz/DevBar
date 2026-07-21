import Testing
import DevBarCore
@testable import DevBar

struct CodexAuthTokenRefreshServiceTests {
    @Test func newerCodexAccessTokenIsUsedWithoutRefreshingAgain() throws {
        let credential = CodexAuthCredential(
            accessToken: "new-token",
            accountID: "account-1",
            hasRefreshToken: true
        )

        let decision = try CodexAuthTokenRefreshService.recoveryDecision(
            storedAccessToken: "expired-token",
            configuredAccountID: "account-1",
            codexCredential: credential
        )

        #expect(decision == .useCredential(credential))
    }

    @Test func matchingExpiredTokenRequestsCodexManagedRefresh() throws {
        let decision = try CodexAuthTokenRefreshService.recoveryDecision(
            storedAccessToken: "expired-token",
            configuredAccountID: "account-1",
            codexCredential: CodexAuthCredential(
                accessToken: "expired-token",
                accountID: "account-1",
                hasRefreshToken: true
            )
        )

        #expect(decision == .requestCodexRefresh)
    }

    @Test func differentCodexAccountIsRejected() {
        #expect(throws: CodexAuthTokenRefreshError.accountMismatch) {
            try CodexAuthTokenRefreshService.recoveryDecision(
                storedAccessToken: "expired-token",
                configuredAccountID: "account-1",
                codexCredential: CodexAuthCredential(
                    accessToken: "new-token",
                    accountID: "account-2",
                    hasRefreshToken: true
                )
            )
        }
    }

    @Test func missingRefreshTokenDoesNotAttemptCodexRefresh() {
        #expect(throws: CodexAuthTokenRefreshError.refreshTokenMissing) {
            try CodexAuthTokenRefreshService.recoveryDecision(
                storedAccessToken: "expired-token",
                configuredAccountID: "account-1",
                codexCredential: CodexAuthCredential(
                    accessToken: "expired-token",
                    accountID: "account-1",
                    hasRefreshToken: false
                )
            )
        }
    }
}
