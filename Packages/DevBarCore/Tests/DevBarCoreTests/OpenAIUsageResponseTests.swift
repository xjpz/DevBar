import Foundation
import Testing
@testable import DevBarCore

@Test
func openAIUsageResponseDecodesAvailableResetCredits() throws {
    let json = """
    {
      "plan_type": "plus",
      "rate_limit": {
        "allowed": true,
        "limit_reached": false,
        "primary_window": {
          "used_percent": 65,
          "limit_window_seconds": 18000,
          "reset_after_seconds": 15001,
          "reset_at": 1782055139
        }
      },
      "rate_limit_reset_credits": {
        "available_count": 1
      }
    }
    """.data(using: .utf8)!

    let response = try JSONDecoder().decode(OpenAIUsageResponse.self, from: json)

    #expect(response.availableResetCount == 1)
}

@Test
func openAIUsageResponseDisplaysProLiteAsPro() {
    let response = OpenAIUsageResponse(
        planType: "prolite",
        rateLimit: nil
    )

    #expect(response.planType == "prolite")
    #expect(response.displayPlanType == "Pro")
}
