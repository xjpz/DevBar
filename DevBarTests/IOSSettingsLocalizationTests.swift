import Foundation
import Testing

struct IOSSettingsLocalizationTests {
    @Test func iPhoneSettingsHasNoHardcodedChineseDisplayStrings() throws {
        let testFileURL = URL(fileURLWithPath: #filePath)
        let projectRoot = testFileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        let checkedFiles = [
            "DevBariOS/Views/IOSSettingsView.swift",
        ]

        let cjkStringPattern = /"[^"\n]*[\u{4E00}-\u{9FFF}][^"\n]*"/
        var findings: [String] = []

        for relativePath in checkedFiles {
            let fileURL = projectRoot.appending(path: relativePath)
            let content = try String(contentsOf: fileURL, encoding: .utf8)
            for match in content.matches(of: cjkStringPattern) {
                findings.append("\(relativePath): \(match.output)")
            }
        }

        #expect(findings.isEmpty, "Hardcoded Chinese display strings: \(findings.joined(separator: "; "))")
    }
}
