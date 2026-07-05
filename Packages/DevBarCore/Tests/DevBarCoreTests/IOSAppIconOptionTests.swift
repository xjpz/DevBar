import Testing
@testable import DevBarCore

@Test
func iosAppIconOptionsExposeDefaultAndApprovedAlternatesInOrder() {
    #expect(IOSAppIconOption.allCases.map(\.id) == [
        "default",
        "dock-blue",
        "light-blue-purple",
        "frosted-lilac-gray",
        "graphite-mono",
    ])
}

@Test
func iosAppIconOptionsMapToAlternateIconNames() {
    #expect(IOSAppIconOption.default.alternateIconName == nil)
    #expect(IOSAppIconOption.dockBlue.alternateIconName == "AppIconDockBlue")
    #expect(IOSAppIconOption.lightBluePurple.alternateIconName == "AppIconLightBluePurple")
    #expect(IOSAppIconOption.frostedLilacGray.alternateIconName == "AppIconFrostedLilacGray")
    #expect(IOSAppIconOption.graphiteMono.alternateIconName == "AppIconGraphiteMono")
}

@Test
func iosAppIconOptionsMapToPreviewAssetNames() {
    #expect(IOSAppIconOption.default.previewAssetName == "AppIconPreviewDefault")
    #expect(IOSAppIconOption.dockBlue.previewAssetName == "AppIconPreviewDockBlue")
    #expect(IOSAppIconOption.lightBluePurple.previewAssetName == "AppIconPreviewLightBluePurple")
    #expect(IOSAppIconOption.frostedLilacGray.previewAssetName == "AppIconPreviewFrostedLilacGray")
    #expect(IOSAppIconOption.graphiteMono.previewAssetName == "AppIconPreviewGraphiteMono")
}

@Test
func iosAppIconOptionsResolveCurrentAlternateIconName() {
    #expect(IOSAppIconOption.option(forAlternateIconName: nil) == .default)
    #expect(IOSAppIconOption.option(forAlternateIconName: "AppIconDockBlue") == .dockBlue)
    #expect(IOSAppIconOption.option(forAlternateIconName: "AppIconGraphiteMono") == .graphiteMono)
    #expect(IOSAppIconOption.option(forAlternateIconName: "UnknownIcon") == .default)
}
