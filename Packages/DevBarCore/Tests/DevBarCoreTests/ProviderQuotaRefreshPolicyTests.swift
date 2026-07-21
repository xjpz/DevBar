import Foundation
import Testing
@testable import DevBarCore

struct ProviderQuotaRefreshPolicyTests {
    @Test func evaluatesFreshnessPerProvider() {
        let now = Date(timeIntervalSince1970: 10_000)
        let providers = ProviderQuotaRefreshPolicy.providersNeedingRefresh(
            [.openai, .deepseek, .mimo],
            latestRefreshByProvider: [
                .openai: now.addingTimeInterval(-30),
                .deepseek: now.addingTimeInterval(-181),
            ],
            interval: 180,
            now: now
        )

        #expect(!providers.contains(.openai))
        #expect(providers.contains(.deepseek))
        #expect(providers.contains(.mimo))
    }

    @Test func respectsConfiguredIntervalAndExactBoundary() {
        let now = Date(timeIntervalSince1970: 20_000)
        let latest: [QuotaProvider: Date] = [
            .glm: now.addingTimeInterval(-299),
            .openai: now.addingTimeInterval(-300),
        ]
        let providers = ProviderQuotaRefreshPolicy.providersNeedingRefresh(
            [.glm, .openai],
            latestRefreshByProvider: latest,
            interval: 300,
            now: now
        )

        #expect(!providers.contains(.glm))
        #expect(providers.contains(.openai))
    }

    @Test func neverSettingDisablesAutomaticRefresh() {
        let providers = ProviderQuotaRefreshPolicy.providersNeedingRefresh(
            QuotaProvider.allCases,
            latestRefreshByProvider: [:],
            interval: 0
        )

        #expect(providers.isEmpty)
    }

    @Test func nextDelayUsesEarliestProviderExpiry() {
        let now = Date(timeIntervalSince1970: 30_000)
        let delay = ProviderQuotaRefreshPolicy.nextRefreshDelay(
            [.openai, .deepseek],
            latestRefreshByProvider: [
                .openai: now.addingTimeInterval(-179),
                .deepseek: now.addingTimeInterval(-60),
            ],
            latestAttemptByProvider: [:],
            interval: 180,
            now: now
        )

        #expect(delay == 1)
    }

    @Test func failedAttemptBacksOffByConfiguredInterval() {
        let now = Date(timeIntervalSince1970: 40_000)
        let delay = ProviderQuotaRefreshPolicy.nextRefreshDelay(
            [.openai],
            latestRefreshByProvider: [:],
            latestAttemptByProvider: [.openai: now.addingTimeInterval(-30)],
            interval: 300,
            now: now
        )

        #expect(delay == 270)
    }
}
