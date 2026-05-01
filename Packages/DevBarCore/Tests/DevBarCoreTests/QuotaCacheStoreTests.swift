import Foundation
import Testing
@testable import DevBarCore

@Test
func quotaCacheStoreRoundTripsSnapshots() throws {
    let suiteName = "DevBarCoreTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defaults.removePersistentDomain(forName: suiteName)

    let store = UserDefaultsQuotaCacheStore(defaults: defaults)
    let glmSnapshot = GLMQuotaCacheSnapshot(
        quotaData: QuotaData(
            limits: [
                QuotaLimit(
                    type: "TOKENS_LIMIT",
                    unit: 3,
                    number: 5,
                    usage: 2,
                    currentValue: 2,
                    remaining: 3,
                    percentage: 40,
                    nextResetTime: 1_710_000_000_000,
                    usageDetails: []
                ),
            ],
            level: "pro"
        ),
        subscription: Subscription(
            subscriptionId: "sub_1",
            productName: "GLM Pro",
            description: "Test",
            status: "VALID",
            valid: "Y",
            autoRenew: 1,
            actualPrice: 99,
            renewPrice: 99,
            currentPeriod: 1,
            nextRenewTime: "2026-12-31 00:00:00",
            billingCycle: "MONTH",
            paymentType: "CARD"
        ),
        lastUpdated: Date(timeIntervalSince1970: 1_700_000_000)
    )
    let openAISnapshot = OpenAIQuotaCacheSnapshot(
        usageResponse: OpenAIUsageResponse(
            planType: "pro",
            rateLimit: OpenAIRateLimit(
                allowed: true,
                limitReached: false,
                primaryWindow: OpenAIUsageWindow(
                    usedPercent: 25,
                    limitWindowSeconds: 10_800,
                    resetAfterSeconds: 600,
                    resetAt: 1_700_000_000
                ),
                secondaryWindow: nil
            )
        ),
        lastUpdated: Date(timeIntervalSince1970: 1_700_000_500)
    )
    let mimoSnapshot = MimoQuotaCacheSnapshot(
        usageResponse: MimoUsageResponse(
            code: 0,
            message: "",
            data: MimoUsageData(
                monthUsage: MimoMonthUsage(
                    percent: FlexibleDouble(0.25),
                    items: [
                        MimoUsageItem(
                            name: "month_total_token",
                            used: FlexibleInt(250),
                            limit: FlexibleInt(1_000),
                            percent: FlexibleDouble(0.25)
                        ),
                    ]
                )
            )
        ),
        planDetail: MimoPlanDetail(
            planCode: "pro",
            planName: "Pro",
            currentPeriodEnd: "2026-05-30 23:59:59",
            expired: false
        ),
        lastUpdated: Date(timeIntervalSince1970: 1_700_001_000),
        detailLastFetchedAt: Date(timeIntervalSince1970: 1_700_001_500)
    )

    store.saveGLMSnapshot(glmSnapshot)
    store.saveOpenAISnapshot(openAISnapshot)
    store.saveMimoSnapshot(mimoSnapshot)

    #expect(store.loadGLMSnapshot() == glmSnapshot)
    #expect(store.loadOpenAISnapshot() == openAISnapshot)
    #expect(store.loadMimoSnapshot() == mimoSnapshot)

    store.clearGLMSnapshot()
    store.clearOpenAISnapshot()
    store.clearMimoSnapshot()

    #expect(store.loadGLMSnapshot() == nil)
    #expect(store.loadOpenAISnapshot() == nil)
    #expect(store.loadMimoSnapshot() == nil)
}

@MainActor
@Test
func quotaViewModelsRestoreCachedSnapshotsOnInit() {
    let suiteName = "DevBarCoreTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)

    let store = UserDefaultsQuotaCacheStore(defaults: defaults)
    let glmLastUpdated = Date(timeIntervalSince1970: 1_700_100_000)
    let openAILastUpdated = Date(timeIntervalSince1970: 1_700_100_500)

    store.saveGLMSnapshot(
        GLMQuotaCacheSnapshot(
            quotaData: QuotaData(limits: [], level: "plus"),
            subscription: Subscription(
                subscriptionId: "sub_cached",
                productName: "GLM Plus",
                description: "Cached",
                status: "VALID",
                valid: "Y",
                autoRenew: 1,
                actualPrice: 59,
                renewPrice: 59,
                currentPeriod: 1,
                nextRenewTime: "2026-11-30 00:00:00",
                billingCycle: "MONTH",
                paymentType: "CARD"
            ),
            lastUpdated: glmLastUpdated
        )
    )
    store.saveOpenAISnapshot(
        OpenAIQuotaCacheSnapshot(
            usageResponse: OpenAIUsageResponse(
                planType: "team",
                rateLimit: OpenAIRateLimit(
                    allowed: true,
                    limitReached: false,
                    primaryWindow: OpenAIUsageWindow(
                        usedPercent: 60,
                        limitWindowSeconds: 86_400,
                        resetAfterSeconds: 1_200,
                        resetAt: 1_700_100_500
                    ),
                    secondaryWindow: nil
                )
            ),
            lastUpdated: openAILastUpdated
        )
    )

    let quotaViewModel = QuotaViewModel(cacheStore: store)
    let openAIQuotaViewModel = OpenAIQuotaViewModel(cacheStore: store)
    let mimoLastUpdated = Date(timeIntervalSince1970: 1_700_101_000)
    let mimoDetailFetchedAt = Date(timeIntervalSince1970: 1_700_101_500)
    store.saveMimoSnapshot(
        MimoQuotaCacheSnapshot(
            usageResponse: MimoUsageResponse(
                code: 0,
                message: "",
                data: MimoUsageData(monthUsage: MimoMonthUsage(percent: nil, items: []))
            ),
            planDetail: MimoPlanDetail(
                planCode: "pro",
                planName: "Pro",
                currentPeriodEnd: "2026-05-30 23:59:59",
                expired: false
            ),
            lastUpdated: mimoLastUpdated,
            detailLastFetchedAt: mimoDetailFetchedAt
        )
    )
    let mimoQuotaViewModel = MimoQuotaViewModel(cacheStore: store)

    #expect(quotaViewModel.quotaData?.level == "plus")
    #expect(quotaViewModel.subscription?.subscriptionId == "sub_cached")
    #expect(quotaViewModel.lastUpdated == glmLastUpdated)
    #expect(openAIQuotaViewModel.usageResponse?.planType == "team")
    #expect(openAIQuotaViewModel.lastUpdated == openAILastUpdated)
    #expect(mimoQuotaViewModel.planDetail?.planName == "Pro")
    #expect(mimoQuotaViewModel.lastUpdated == mimoLastUpdated)
    #expect(mimoQuotaViewModel.detailLastFetchedAt == mimoDetailFetchedAt)
}
