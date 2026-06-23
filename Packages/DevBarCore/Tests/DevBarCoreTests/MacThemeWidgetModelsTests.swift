import Foundation
import Testing
@testable import DevBarCore

@Test func macThemeWidgetMergesStatusAndActionsIntoOnePage() {
    #expect(MacThemeWidgetPolicy.availablePages == [.macConsole, .quota])
}

@Test func macThemeWidgetUsesPlaceholderForDeferredMacMetrics() {
    let snapshot = MacStatusWidgetSnapshot(
        deviceID: "mac-1",
        deviceName: "Studio",
        isOnline: true,
        lastSeenAt: nil,
        screenState: .unknown,
        displayState: .unknown,
        keepAwakeState: .unknown,
        connectionMode: .relay,
        batteryPercent: nil,
        cpuPercent: nil,
        memoryPercent: nil,
        lastUpdated: Date(timeIntervalSince1970: 1_714_000_000)
    )

    #expect(MacThemeWidgetPolicy.percentText(snapshot.batteryPercent) == "--")
    #expect(MacThemeWidgetPolicy.percentText(snapshot.cpuPercent) == "--")
    #expect(MacThemeWidgetPolicy.percentText(snapshot.memoryPercent) == "--")
}

@Test func macThemeWidgetUserSnapshotDecodesLegacyPayloadWithoutAvatarFile() throws {
    let data = Data(#"{"displayName":"iPhone","avatarSymbol":"iphone.gen3"}"#.utf8)
    let snapshot = try JSONDecoder().decode(MacThemeWidgetUserSnapshot.self, from: data)

    #expect(snapshot.displayName == "iPhone")
    #expect(snapshot.avatarSymbol == "iphone.gen3")
    #expect(snapshot.avatarFileName == nil)
}

@Test func macThemeWidgetUserSnapshotRoundTripsAvatarFileName() throws {
    let snapshot = MacThemeWidgetUserSnapshot(
        displayName: "XJPZ",
        avatarSymbol: "person.crop.circle.fill",
        avatarFileName: "mac-theme-avatar.jpg"
    )

    let data = try JSONEncoder().encode(snapshot)
    let decoded = try JSONDecoder().decode(MacThemeWidgetUserSnapshot.self, from: data)

    #expect(decoded == snapshot)
}

@Test func macThemeWidgetAvatarStoreRoundTripsData() throws {
    let containerURL = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: containerURL, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: containerURL) }

    let store = MacThemeWidgetAvatarStore(containerURL: containerURL)
    let avatarData = Data([0x01, 0x02, 0x03])
    let fileName = try store.save(avatarData)

    #expect(fileName == DevBarCoreConstants.AppGroup.macThemeWidgetAvatarFileName)
    #expect(store.load(fileName: fileName) == avatarData)

    store.clear(fileName: fileName)
    #expect(store.load(fileName: fileName) == nil)
}
