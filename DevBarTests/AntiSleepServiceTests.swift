import Testing
@testable import DevBar

struct AntiSleepServiceTests {
    @Test func disabledNeverHoldsAssertion() {
        let snapshot = AntiSleepSnapshot(isEnabled: false, isPortableMac: false, isLidClosed: nil)

        #expect(AntiSleepService.shouldHoldAssertion(for: snapshot) == false)
    }

    @Test func desktopEnabledHoldsAssertion() {
        let snapshot = AntiSleepSnapshot(isEnabled: true, isPortableMac: false, isLidClosed: nil)

        #expect(AntiSleepService.shouldHoldAssertion(for: snapshot) == true)
    }

    @Test func portableOpenHoldsAssertion() {
        let snapshot = AntiSleepSnapshot(isEnabled: true, isPortableMac: true, isLidClosed: false)

        #expect(AntiSleepService.shouldHoldAssertion(for: snapshot) == true)
    }

    @Test func portableClosedReleasesAssertion() {
        let snapshot = AntiSleepSnapshot(isEnabled: true, isPortableMac: true, isLidClosed: true)

        #expect(AntiSleepService.shouldHoldAssertion(for: snapshot) == false)
    }

    @Test func portableUnknownLidStateHoldsAssertion() {
        let snapshot = AntiSleepSnapshot(isEnabled: true, isPortableMac: true, isLidClosed: nil)

        #expect(AntiSleepService.shouldHoldAssertion(for: snapshot) == true)
    }
}
