import DevBarCore
import Testing
@testable import DevBar

struct QuotaResetNotificationPolicyTests {
    @Test func openAITemporaryResetToZeroNotifiesWhenResetCycleAdvances() {
        let previous = item(percentage: 37, resetAt: 1_000)
        let current = item(percentage: 0, resetAt: 2_000)

        #expect(shouldNotify(provider: .openai, previous: previous, current: current))
    }

    @Test func openAIResetWithImmediateReuseNotifiesWhenResetCycleAdvances() {
        let previous = item(percentage: 37, resetAt: 1_000)
        let current = item(percentage: 2, resetAt: 2_000)

        #expect(shouldNotify(provider: .openai, previous: previous, current: current))
    }

    @Test func openAITemporaryResetToZeroFallsBackWhenResetTimeIsMissing() {
        let previous = item(percentage: 37)
        let current = item(percentage: 0)

        #expect(shouldNotify(provider: .openai, previous: previous, current: current))
    }

    @Test func openAIStayingAtZeroDoesNotNotifyAgain() {
        let previous = item(percentage: 0, resetAt: 2_000)
        let current = item(percentage: 0, resetAt: 2_000)

        #expect(!shouldNotify(provider: .openai, previous: previous, current: current))
    }

    @Test func openAIUsageIncreaseDoesNotNotify() {
        let previous = item(percentage: 37, resetAt: 1_000)
        let current = item(percentage: 40, resetAt: 1_000)

        #expect(!shouldNotify(provider: .openai, previous: previous, current: current))
    }

    @Test func initialSnapshotDoesNotNotify() {
        let current = item(percentage: 0, resetAt: 2_000)

        #expect(!shouldNotify(provider: .openai, previous: nil, current: current))
    }

    @Test func differentQuotaWindowsDoNotCrossNotify() {
        let previous = item(key: "openai.primary.18000", percentage: 37, resetAt: 1_000)
        let current = item(key: "openai.secondary.604800", percentage: 0, resetAt: 2_000)

        #expect(!shouldNotify(provider: .openai, previous: previous, current: current))
    }

    @Test func glmExhaustedQuotaRecoveryKeepsExistingBehavior() {
        let previous = item(key: "glm.tokens", percentage: 100)
        let current = item(key: "glm.tokens", percentage: 20)

        #expect(shouldNotify(provider: .glm, previous: previous, current: current))
    }

    @Test func glmTemporaryDropToZeroDoesNotAdoptOpenAIRule() {
        let previous = item(key: "glm.tokens", percentage: 37)
        let current = item(key: "glm.tokens", percentage: 0)

        #expect(!shouldNotify(provider: .glm, previous: previous, current: current))
    }

    private func shouldNotify(
        provider: QuotaProvider,
        previous: NotificationQuotaItem?,
        current: NotificationQuotaItem
    ) -> Bool {
        QuotaResetNotificationPolicy.shouldNotify(
            provider: provider,
            previous: previous,
            current: current
        )
    }

    private func item(
        key: String = "openai.primary.18000",
        percentage: Int,
        resetAt: Int? = nil
    ) -> NotificationQuotaItem {
        NotificationQuotaItem(
            key: key,
            name: key,
            percentage: percentage,
            resetAt: resetAt
        )
    }
}
