import Foundation
import Testing
@testable import DevBarCore

@Test func macThemeWidgetMergesStatusAndActionsIntoOnePage() {
    #expect(MacThemeWidgetPolicy.availablePages == [.quota, .macConsole])
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
