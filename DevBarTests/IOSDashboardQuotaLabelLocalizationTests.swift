import Foundation
import Testing

struct IOSDashboardQuotaLabelLocalizationTests {
    @Test func iPhoneDashboardQuotaRowsDoNotDisplayRawProviderLabels() throws {
        let testFileURL = URL(fileURLWithPath: #filePath)
        let projectRoot = testFileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let fileURL = projectRoot.appending(path: "DevBariOS/Views/IOSDashboardView.swift")
        let content = try String(contentsOf: fileURL, encoding: .utf8)

        #expect(!content.contains("title: row.name"))
        #expect(!content.contains("title: limit.displayName"))
        #expect(content.contains("localizedQuotaTitle("))
    }
}
