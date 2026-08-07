import Foundation
import Testing

struct IOSThemeSynchronizationTests {
    @Test func rootViewSeedsTheThemeManagerWithTheInitialSystemColorScheme() throws {
        let testFileURL = URL(fileURLWithPath: #filePath)
        let projectRoot = testFileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let appURL = projectRoot.appending(path: "DevBariOS/DevBariOSApp.swift")
        let source = try String(contentsOf: appURL, encoding: .utf8)

        let onAppear = try #require(source.range(of: ".onAppear {"))
        let onColorSchemeChange = try #require(
            source.range(
                of: ".onChange(of: systemColorScheme)",
                range: onAppear.upperBound..<source.endIndex
            )
        )
        let initialSynchronization = source[onAppear.lowerBound..<onColorSchemeChange.lowerBound]

        #expect(initialSynchronization.contains("themeManager.systemColorScheme = systemColorScheme"))
        #expect(initialSynchronization.contains("themeManager.updateBarAppearance()"))
    }
}
