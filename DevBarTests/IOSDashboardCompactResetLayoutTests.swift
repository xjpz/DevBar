import Foundation
import Testing

struct IOSDashboardCompactResetLayoutTests {
    @Test func resetTimeSharesTheQuotaHeaderAndFallsBackToAnIcon() throws {
        let testFileURL = URL(fileURLWithPath: #filePath)
        let projectRoot = testFileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let fileURL = projectRoot.appending(path: "DevBariOS/Views/IOSDashboardView.swift")
        let content = try String(contentsOf: fileURL, encoding: .utf8)

        #expect(content.contains("ViewThatFits(in: .horizontal)"))
        #expect(content.contains("quotaHeaderRow(resetStyle: .icon)"))
        #expect(content.contains("clock.arrow.trianglehead.counterclockwise.rotate.90"))
        #expect(!content.contains("case .text:"))
        #expect(content.contains(".font(theme.captionFont)"))
        #expect(content.contains(".foregroundStyle(theme.textSecondary)"))
    }

    @Test func openAIResetCreditsKeepTheLocalizedLabelInTheExistingContentRow() throws {
        let testFileURL = URL(fileURLWithPath: #filePath)
        let projectRoot = testFileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let fileURL = projectRoot.appending(path: "DevBariOS/Views/IOSDashboardView.swift")
        let content = try String(contentsOf: fileURL, encoding: .utf8)

        #expect(content.contains("resetCreditsRow(availableResetCount)"))
        #expect(content.contains("Text(openAIResetCreditsLabel)"))
        #expect(!content.contains("openAIResetCreditsAssetName(for: count)"))
    }

    @Test func greetingAndResetDateUseTheRefinedDashboardPresentation() throws {
        let testFileURL = URL(fileURLWithPath: #filePath)
        let projectRoot = testFileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let fileURL = projectRoot.appending(path: "DevBariOS/Views/IOSDashboardView.swift")
        let content = try String(contentsOf: fileURL, encoding: .utf8)

        #expect(content.contains(".system(.body, design: .monospaced).weight(.medium)"))
        #expect(content.contains("Calendar.current.isDateInToday(date)"))
        #expect(content.contains("compactResetText(limit.formattedResetTime)"))
        #expect(content.contains("dateStyle: dateStyle"))
    }
}
