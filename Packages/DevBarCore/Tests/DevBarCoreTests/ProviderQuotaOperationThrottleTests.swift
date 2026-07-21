import Foundation
import Testing
@testable import DevBarCore

struct ProviderQuotaOperationThrottleTests {
    @Test func refreshIsDebouncedForAtLeastThirtySeconds() {
        var throttle = ProviderQuotaOperationThrottle(minimumInterval: 10)
        let start = Date(timeIntervalSince1970: 1_000)

        let first = throttle.shouldStartRefresh(at: start)
        let withinWindow = throttle.shouldStartRefresh(at: start.addingTimeInterval(29.999))
        let atBoundary = throttle.shouldStartRefresh(at: start.addingTimeInterval(30))

        #expect(throttle.minimumInterval == 30)
        #expect(first)
        #expect(!withinWindow)
        #expect(atBoundary)
    }

    @Test func quotaSyncIsDebouncedPerPeerAndAccount() {
        var throttle = ProviderQuotaOperationThrottle()
        let start = Date(timeIntervalSince1970: 2_000)

        let first = throttle.shouldStartSync(
            peerDeviceID: "iphone-1",
            accountID: "openai-1",
            at: start
        )
        let samePairWithinWindow = throttle.shouldStartSync(
            peerDeviceID: "iphone-1",
            accountID: "openai-1",
            at: start.addingTimeInterval(15)
        )
        let differentPeer = throttle.shouldStartSync(
            peerDeviceID: "iphone-2",
            accountID: "openai-1",
            at: start.addingTimeInterval(15)
        )
        let differentAccount = throttle.shouldStartSync(
            peerDeviceID: "iphone-1",
            accountID: "deepseek-1",
            at: start.addingTimeInterval(15)
        )
        let atBoundary = throttle.shouldStartSync(
            peerDeviceID: "iphone-1",
            accountID: "openai-1",
            at: start.addingTimeInterval(30)
        )

        #expect(first)
        #expect(!samePairWithinWindow)
        #expect(differentPeer)
        #expect(differentAccount)
        #expect(atBoundary)
    }

    @Test func clockRollbackStartsANewDebounceWindow() {
        var throttle = ProviderQuotaOperationThrottle()
        let start = Date(timeIntervalSince1970: 3_000)

        let first = throttle.shouldStartRefresh(at: start)
        let afterRollback = throttle.shouldStartRefresh(at: start.addingTimeInterval(-1))
        let withinResetWindow = throttle.shouldStartRefresh(at: start)

        #expect(first)
        #expect(afterRollback)
        #expect(!withinResetWindow)
    }
}
