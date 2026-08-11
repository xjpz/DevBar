import Testing
@testable import DevBarCore

@Test
func agentWatcherIsDisabledOnMac() {
    #if os(macOS)
    #expect(!DevBarCoreConstants.Features.agentWatcherEnabled)
    #else
    #expect(DevBarCoreConstants.Features.agentWatcherEnabled)
    #endif
}
