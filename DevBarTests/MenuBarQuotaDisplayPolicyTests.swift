import Testing
@testable import DevBar

struct MenuBarQuotaDisplayPolicyTests {
    @Test func openAIErrorDoesNotReplaceCachedQuotaRows() {
        #expect(MenuBarQuotaDisplayPolicy.shouldShowError(rowCount: 1, errorMessage: "Loading failed") == false)
    }

    @Test func openAIErrorShowsWhenNoCachedQuotaRowsExist() {
        #expect(MenuBarQuotaDisplayPolicy.shouldShowError(rowCount: 0, errorMessage: "Loading failed") == true)
    }

    @Test func missingErrorDoesNotShowError() {
        #expect(MenuBarQuotaDisplayPolicy.shouldShowError(rowCount: 0, errorMessage: nil) == false)
    }
}
