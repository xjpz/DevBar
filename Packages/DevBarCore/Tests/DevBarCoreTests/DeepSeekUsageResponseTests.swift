import Foundation
import Testing
@testable import DevBarCore

@Test
func deepSeekUsageDecodesLatestNumericUsageResponse() throws {
    let json = """
    {
      "code": 0,
      "msg": "",
      "data": {
        "biz_code": 0,
        "biz_msg": "",
        "biz_data": {
          "current_token": 10000000,
          "monthly_usage": 0,
          "total_usage": 0,
          "normal_wallets": [
            {
              "currency": "CNY",
              "balance": "4.6800989600000000",
              "token_estimation": "1560032"
            }
          ],
          "bonus_wallets": [
            {
              "currency": "CNY",
              "balance": "0",
              "token_estimation": "0"
            }
          ],
          "total_available_token_estimation": "1560032",
          "monthly_costs": [
            {
              "currency": "CNY",
              "amount": "0"
            }
          ],
          "monthly_token_usage": 0,
          "total_costs": [
            {
              "currency": "CNY",
              "amount": "5.3319558400000000"
            }
          ]
        }
      }
    }
    """.data(using: .utf8)!

    let response = try JSONDecoder().decode(DeepSeekUsageResponse.self, from: json)
    let usage = try #require(response.data?.bizData)

    #expect(usage.currentToken == 10_000_000)
    #expect(usage.monthlyUsage == 0)
    #expect(usage.monthlyTokenUsageValue == 0)
    #expect(usage.totalAvailableTokens == 1_560_032)
    #expect(abs(usage.totalBalanceCNY - 4.68009896) < 0.00000001)
    #expect(usage.monthlyCostCNY == 0)
    #expect(abs(usage.totalCostCNY - 5.33195584) < 0.00000001)
    #expect(usage.displayedCostCNY == 0)
}

@Test
func deepSeekUsageDisplaysCondensedOverdrawnResponse() throws {
    let json = """
    {
      "code": 0,
      "msg": "",
      "data": {
        "biz_code": 0,
        "biz_msg": "",
        "biz_data": {
          "normal_wallets": [
            {
              "currency": "CNY",
              "balance": "-0.0591191600000000",
              "token_estimation": "0"
            }
          ],
          "bonus_wallets": [
            {
              "currency": "CNY",
              "balance": "0",
              "token_estimation": "0"
            }
          ],
          "total_costs": [
            {
              "currency": "CNY",
              "amount": "20.0711739600000000"
            }
          ]
        }
      }
    }
    """.data(using: .utf8)!

    let response = try JSONDecoder().decode(DeepSeekUsageResponse.self, from: json)
    let usage = try #require(response.data?.bizData)

    #expect(abs(usage.totalBalanceCNY + 0.05911916) < 0.00000001)
    #expect(abs(usage.totalCostCNY - 20.07117396) < 0.00000001)
    #expect(abs(usage.displayedCostCNY - 20.07117396) < 0.00000001)
    #expect(usage.totalAvailableTokens == 0)
    #expect(usage.quotaRows.count == 1)
    #expect(usage.quotaRows[0].percentage == 100)
    #expect(usage.quotaRows[0].unitDescription == "¥20.0712 / ¥20.01")
}

@Test
func deepSeekUsageSumsWalletTokenEstimatesWhenAggregateIsMissing() throws {
    let json = """
    {
      "code": 0,
      "data": {
        "biz_data": {
          "normal_wallets": [
            { "currency": "CNY", "balance": "1", "token_estimation": "1200" }
          ],
          "bonus_wallets": [
            { "currency": "CNY", "balance": "0", "token_estimation": "300" }
          ]
        }
      }
    }
    """.data(using: .utf8)!

    let response = try JSONDecoder().decode(DeepSeekUsageResponse.self, from: json)
    let usage = try #require(response.data?.bizData)

    #expect(usage.totalAvailableTokens == 1_500)
}

@Test
func deepSeekUsageStillDecodesLegacyStringUsageValues() throws {
    let json = """
    {
      "code": 0,
      "data": {
        "biz_data": {
          "monthly_usage": "12",
          "monthly_token_usage": "34"
        }
      }
    }
    """.data(using: .utf8)!

    let response = try JSONDecoder().decode(DeepSeekUsageResponse.self, from: json)
    let usage = try #require(response.data?.bizData)

    #expect(usage.monthlyUsage == 12)
    #expect(usage.monthlyTokenUsageValue == 34)
}

@Test
func deepSeekUsageRejectsUnsupportedUsageValueTypes() throws {
    let json = """
    {
      "code": 0,
      "data": {
        "biz_data": {
          "monthly_usage": { "value": 12 }
        }
      }
    }
    """.data(using: .utf8)!

    #expect(throws: DecodingError.self) {
        try JSONDecoder().decode(DeepSeekUsageResponse.self, from: json)
    }
}
