import Foundation
import Testing

struct IOSDashboardQuotaErrorPresentationTests {
    @Test func syncedOpenAIAndDeepSeekQuotaKeepRefreshErrorsVisible() throws {
        let testFileURL = URL(fileURLWithPath: #filePath)
        let projectRoot = testFileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let fileURL = projectRoot.appending(path: "DevBariOS/Views/IOSDashboardView.swift")
        let content = try String(contentsOf: fileURL, encoding: .utf8)

        #expect(content.contains("errorMessage: String? = nil"))
        #expect(content.contains("refreshWarning(errorMessage)"))
        #expect(occurrences(
            of: "syncedQuotaContent(snapshot, errorMessage: appViewModel.openAIQuotaViewModel.errorMessage)",
            in: content
        ) == 2)
        #expect(occurrences(
            of: "syncedQuotaContent(snapshot, errorMessage: appViewModel.deepSeekQuotaViewModel.errorMessage)",
            in: content
        ) == 2)
    }

    private func occurrences(of needle: String, in text: String) -> Int {
        text.components(separatedBy: needle).count - 1
    }
}
