import Foundation
import Testing

struct IOSHomeLocalizationTests {
    @Test func iPhoneHomeHasNoHardcodedChineseDisplayStrings() throws {
        let testFileURL = URL(fileURLWithPath: #filePath)
        let projectRoot = testFileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        let checkedFiles = [
            "DevBariOS/Views/IOSDashboardView.swift",
            "DevBariOS/ViewModels/IOSAppViewModel.swift",
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

    @Test func hermesChatBusyStateUsesThinkingCopyAndMessageRowsDoNotShowTimestamps() throws {
        let testFileURL = URL(fileURLWithPath: #filePath)
        let projectRoot = testFileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        let chatViewURL = projectRoot.appending(path: "DevBariOS/Views/IOSHermesChatView.swift")
        let chatViewSource = try String(contentsOf: chatViewURL, encoding: .utf8)
        #expect(!chatViewSource.contains("Text(Self.timeFormatter.string(from: message.createdAt))"))
        #expect(!chatViewSource.contains("private static let timeFormatter"))
        #expect(chatViewSource.contains("assistantActionButton(title: \"ios_common_copy\", systemImage: \"square.on.square\")"))
        #expect(chatViewSource.contains("VStack(alignment: .leading, spacing: 8)"))
        #expect(!chatViewSource.contains(".padding(.top, 2)\n                    .opacity(message.content.isEmpty ? 0 : 1)"))
        #expect(chatViewSource.contains("HermesThinkingStatusView(theme: theme)"))
        #expect(chatViewSource.contains("TimelineView(.periodic"))

        let localizationURL = projectRoot.appending(path: "DevBar/Resources/Localizable.xcstrings")
        let localizationData = try Data(contentsOf: localizationURL)
        let localization = try JSONSerialization.jsonObject(with: localizationData) as? [String: Any]
        let strings = try #require(localization?["strings"] as? [String: Any])
        let replying = try #require(strings["ios_hermes_replying"] as? [String: Any])
        let localizations = try #require(replying["localizations"] as? [String: Any])
        #expect(localizedValue(in: localizations, language: "zh-Hans") == "正在思考")
        #expect(localizedValue(in: localizations, language: "en") == "Thinking")
    }

    private func localizedValue(in localizations: [String: Any], language: String) -> String? {
        guard let languageEntry = localizations[language] as? [String: Any],
              let stringUnit = languageEntry["stringUnit"] as? [String: Any] else {
            return nil
        }
        return stringUnit["value"] as? String
    }
}
