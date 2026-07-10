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
        "smile-blue",
        "smile-blue-border",
    ])
}

@Test
func iosAppIconOptionsMapToAlternateIconNames() {
    #expect(IOSAppIconOption.default.alternateIconName == nil)
    #expect(IOSAppIconOption.dockBlue.alternateIconName == "AppIconDockBlue")
    #expect(IOSAppIconOption.lightBluePurple.alternateIconName == "AppIconLightBluePurple")
    #expect(IOSAppIconOption.frostedLilacGray.alternateIconName == "AppIconFrostedLilacGray")
    #expect(IOSAppIconOption.graphiteMono.alternateIconName == "AppIconGraphiteMono")
    #expect(IOSAppIconOption.smileBlue.alternateIconName == "AppIconSmileBlueV2")
    #expect(IOSAppIconOption.smileBlueBorder.alternateIconName == "AppIconSmileBlueBorder")
}

@Test
func iosAppIconOptionsMapToExpectedBundleIconNames() {
    #expect(IOSAppIconOption.default.expectedBundleIconName == "AppIcon")
    #expect(IOSAppIconOption.dockBlue.expectedBundleIconName == "AppIconDockBlue")
    #expect(IOSAppIconOption.lightBluePurple.expectedBundleIconName == "AppIconLightBluePurple")
    #expect(IOSAppIconOption.frostedLilacGray.expectedBundleIconName == "AppIconFrostedLilacGray")
    #expect(IOSAppIconOption.graphiteMono.expectedBundleIconName == "AppIconGraphiteMono")
    #expect(IOSAppIconOption.smileBlue.expectedBundleIconName == "AppIconSmileBlueV2")
    #expect(IOSAppIconOption.smileBlueBorder.expectedBundleIconName == "AppIconSmileBlueBorder")
}

@Test
func iosAppIconOptionsMapToPreviewAssetNames() {
    #expect(IOSAppIconOption.default.previewAssetName == "AppIconPreviewDefault")
    #expect(IOSAppIconOption.dockBlue.previewAssetName == "AppIconPreviewDockBlue")
    #expect(IOSAppIconOption.lightBluePurple.previewAssetName == "AppIconPreviewLightBluePurple")
    #expect(IOSAppIconOption.frostedLilacGray.previewAssetName == "AppIconPreviewFrostedLilacGray")
    #expect(IOSAppIconOption.graphiteMono.previewAssetName == "AppIconPreviewGraphiteMono")
    #expect(IOSAppIconOption.smileBlue.previewAssetName == "AppIconPreviewSmileBlue")
    #expect(IOSAppIconOption.smileBlueBorder.previewAssetName == "AppIconPreviewSmileBlueBorder")
}

@Test
func iosAppIconOptionsResolveCurrentAlternateIconName() {
    #expect(IOSAppIconOption.option(forAlternateIconName: nil) == .default)
    #expect(IOSAppIconOption.option(forAlternateIconName: "AppIconDockBlue") == .dockBlue)
    #expect(IOSAppIconOption.option(forAlternateIconName: "AppIconGraphiteMono") == .graphiteMono)
    // Legacy names from before the Smile Blue V2 refresh still resolve for anyone who had them set.
    #expect(IOSAppIconOption.option(forAlternateIconName: "AppIconSmileBlue") == .smileBlue)
    #expect(IOSAppIconOption.option(forAlternateIconName: "AppIconSmileBlueDark") == .smileBlue)
    #expect(IOSAppIconOption.option(forAlternateIconName: "AppIconSmileBlueV2") == .smileBlue)
    #expect(IOSAppIconOption.option(forAlternateIconName: "AppIconSmileBlueBorder") == .smileBlueBorder)
    #expect(IOSAppIconOption.option(forAlternateIconName: "UnknownIcon") == .default)
}
