import Foundation
import Testing
@testable import DevBarCore

@Test
func mimoUsageParsesMonthlyTokenWindow() throws {
    let data = """
    {
      "code": 0,
      "message": "",
      "data": {
        "monthUsage": {
          "percent": 0.1661,
          "items": [{
            "name": "month_total_token",
            "used": 265741632,
            "limit": 1600000000,
            "percent": 0.1661
          }]
        }
      }
    }
    """.data(using: .utf8)!

    let response = try JSONDecoder().decode(MimoUsageResponse.self, from: data)
    let item = try #require(response.usageItems.first)

    #expect(item.name == "month_total_token")
    #expect(item.usedValue == 265_741_632)
    #expect(item.limitValue == 1_600_000_000)
    #expect(item.remainingValue == 1_334_258_368)
    #expect(item.percentage == 17)
    #expect(response.quotaRows.count == 1)
}

@Test
func mimoUsageAcceptsStringNumbers() throws {
    let data = """
    {
      "code": 0,
      "data": {
        "monthUsage": {
          "items": [{
            "name": "month_total_token",
            "used": "250",
            "limit": "1000"
          }]
        }
      }
    }
    """.data(using: .utf8)!

    let response = try JSONDecoder().decode(MimoUsageResponse.self, from: data)
    let item = try #require(response.usageItems.first)

    #expect(item.usedValue == 250)
    #expect(item.limitValue == 1_000)
    #expect(item.percentage == 25)
}

@Test
func mimoPlanDetailParsesPlanNameAndPeriodEnd() throws {
    let data = """
    {
      "code": 0,
      "message": "",
      "data": {
        "planCode": "pro",
        "planName": "Pro",
        "currentPeriodEnd": "2026-05-30 23:59:59",
        "expired": false,
        "enableAutoRenew": false,
        "autoRenewDiscount": "0.77",
        "hasAutoRenewSubscribed": false
      }
    }
    """.data(using: .utf8)!

    let response = try JSONDecoder().decode(MimoPlanDetailResponse.self, from: data)
    let detail = try #require(response.data)

    #expect(detail.planName == "Pro")
    #expect(detail.currentPeriodEnd == "2026-05-30 23:59:59")
    #expect(detail.currentPeriodEndDate != nil)
}

@MainActor
@Test
func mimoPlanDetailDailyRefreshDecision() throws {
    let suiteName = "DevBarCoreTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defaults.removePersistentDomain(forName: suiteName)
    let viewModel = MimoQuotaViewModel(cacheStore: UserDefaultsQuotaCacheStore(defaults: defaults))
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    #expect(viewModel.shouldFetchPlanDetail(now: now))

    viewModel.detailLastFetchedAt = now.addingTimeInterval(-23 * 60 * 60)
    #expect(!viewModel.shouldFetchPlanDetail(now: now))

    viewModel.detailLastFetchedAt = now.addingTimeInterval(-25 * 60 * 60)
    #expect(viewModel.shouldFetchPlanDetail(now: now))
}

@Test
func mimoServiceTokenNormalizesFullCookie() {
    let token = MimoAPIClient.normalizedServiceToken(
        from: "foo=bar; serviceToken=\"abc123\"; another=value"
    )

    #expect(token == "abc123")
    #expect(MimoAPIClient.normalizedServiceToken(from: " plain-token ") == "plain-token")
    #expect(MimoAPIClient.normalizedServiceToken(from: "serviceToken=\"abc123") == "abc123")
    #expect(MimoAPIClient.cookieHeaderValue(for: token) == "serviceToken=\"abc123\"")
}

@Test
func mimoCookieHeaderPreservesBrowserCookie() {
    let cookie = """
    serviceToken="/vjQa88K2JeX+vuUvl6J6Mnsz549RsYr2ThHTVPKLhYGjQoYwDZ6pgn9YX7z1Va5GWMkgyGqoyCdKKw=="; api-platform_serviceToken="yVHEDQlNiFT1sk9ziPPq8fX39z2idDPwg="; userId=3966; api-platform_slh="xeTjaz9uLpVZFo="; api-platform_ph="RD634SJBg=="
    """

    #expect(
        MimoAPIClient.normalizedServiceToken(from: cookie)
            == "/vjQa88K2JeX+vuUvl6J6Mnsz549RsYr2ThHTVPKLhYGjQoYwDZ6pgn9YX7z1Va5GWMkgyGqoyCdKKw=="
    )
    #expect(
        MimoAPIClient.cookieHeaderValue(for: cookie)
            == #"serviceToken="/vjQa88K2JeX+vuUvl6J6Mnsz549RsYr2ThHTVPKLhYGjQoYwDZ6pgn9YX7z1Va5GWMkgyGqoyCdKKw=="; api-platform_serviceToken="yVHEDQlNiFT1sk9ziPPq8fX39z2idDPwg="; userId=3966; api-platform_slh="xeTjaz9uLpVZFo="; api-platform_ph="RD634SJBg==""#
    )
}
