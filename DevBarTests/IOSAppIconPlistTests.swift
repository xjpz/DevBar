import Foundation
import Testing

struct IOSAppIconPlistTests {
    @Test func alternateAppIconsUseCatalogNamesOnly() throws {
        let testFileURL = URL(fileURLWithPath: #filePath)
        let projectRoot = testFileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let infoPlistURL = projectRoot.appending(path: "DevBariOS/Info.plist")
        let infoPlistData = try Data(contentsOf: infoPlistURL)
        let plist = try #require(
            PropertyListSerialization.propertyList(
                from: infoPlistData,
                options: [],
                format: nil
            ) as? [String: Any]
        )
        let bundleIcons = try #require(plist["CFBundleIcons"] as? [String: Any])
        let alternateIcons = try #require(bundleIcons["CFBundleAlternateIcons"] as? [String: Any])

        for (iconName, iconValue) in alternateIcons {
            let icon = try #require(iconValue as? [String: Any])
            #expect(icon["CFBundleIconName"] as? String == iconName)
            #expect(icon["CFBundleIconFiles"] == nil)
        }
    }

    @Test func alternateAppIconSetsProvideDarkAppearanceVariants() throws {
        let testFileURL = URL(fileURLWithPath: #filePath)
        let projectRoot = testFileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let assetsURL = projectRoot.appending(path: "DevBariOS/Assets.xcassets")
        let iconSetURLs = try FileManager.default.contentsOfDirectory(
            at: assetsURL,
            includingPropertiesForKeys: nil
        )
        .filter {
            $0.pathExtension == "appiconset" && $0.deletingPathExtension().lastPathComponent != "AppIcon"
        }

        var findings: [String] = []

        for iconSetURL in iconSetURLs {
            let contentsURL = iconSetURL.appending(path: "Contents.json")
            let contentsData = try Data(contentsOf: contentsURL)
            let contents = try #require(
                JSONSerialization.jsonObject(with: contentsData) as? [String: Any]
            )
            let images = try #require(contents["images"] as? [[String: Any]])
            let referencedFilenames = Set(images.compactMap { $0["filename"] as? String })
            let actualFilenames = Set(
                try FileManager.default.contentsOfDirectory(
                    at: iconSetURL,
                    includingPropertiesForKeys: nil
                )
                .filter { $0.pathExtension == "png" }
                .map(\.lastPathComponent)
            )

            // Dark rendering must come from an in-catalog luminosity=dark appearance variant so the
            // system swaps the Home Screen icon automatically (no runtime setAlternateIconName).
            let hasDarkAppearanceVariant = images.contains { image in
                guard let appearances = image["appearances"] as? [[String: Any]] else { return false }
                return appearances.contains {
                    $0["appearance"] as? String == "luminosity" && $0["value"] as? String == "dark"
                }
            }
            let unassignedFilenames = actualFilenames.subtracting(referencedFilenames).sorted()

            if !hasDarkAppearanceVariant {
                findings.append("\(iconSetURL.lastPathComponent): missing luminosity=dark appearance variant")
            }
            if !unassignedFilenames.isEmpty {
                findings.append("\(iconSetURL.lastPathComponent): unassigned files \(unassignedFilenames)")
            }
        }

        #expect(findings.isEmpty, "App icon set findings: \(findings.joined(separator: "; "))")
    }
}
