import Foundation
import Testing

struct LocalizationResourceTests {
    @Test func macEnglishLocalizationHasNoChineseFallbacks() throws {
        let testFileURL = URL(fileURLWithPath: #filePath)
        let projectRoot = testFileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let catalogURL = projectRoot
            .appendingPathComponent("DevBar")
            .appendingPathComponent("Resources")
            .appendingPathComponent("Localizable.xcstrings")
        let data = try Data(contentsOf: catalogURL)
        let catalog = try JSONDecoder().decode(StringCatalog.self, from: data)
        let cjkPattern = /[\u{4E00}-\u{9FFF}]/

        let problematicKeys = catalog.strings.compactMap { key, entry -> String? in
            guard key.contains(cjkPattern) else { return nil }
            guard let english = entry.localizations?["en"]?.stringUnit?.value,
                  !english.contains(cjkPattern) else {
                return key
            }
            return nil
        }

        #expect(problematicKeys.isEmpty, "Missing or Chinese English localizations: \(problematicKeys.prefix(20).joined(separator: ", "))")
    }
}

private struct StringCatalog: Decodable {
    let strings: [String: StringCatalogEntry]
}

private struct StringCatalogEntry: Decodable {
    let localizations: [String: StringCatalogLocalization]?
}

private struct StringCatalogLocalization: Decodable {
    let stringUnit: StringCatalogStringUnit?
}

private struct StringCatalogStringUnit: Decodable {
    let value: String
}
