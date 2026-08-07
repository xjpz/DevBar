import Foundation
import Testing
@testable import DevBarCore

@Test func pushNotificationURLPolicyAcceptsAbsoluteWebURLs() throws {
    let secure = try #require(
        PushNotificationURLPolicy.validatedURL(from: "  https://ci.example.com/builds/123?tab=log#failure  ")
    )
    let local = try #require(
        PushNotificationURLPolicy.validatedURL(from: "http://192.168.1.20:8080/builds/123")
    )
    let uppercaseScheme = try #require(
        PushNotificationURLPolicy.validatedURL(from: "HTTPS://ci.example.com/builds/124")
    )

    #expect(secure.absoluteString == "https://ci.example.com/builds/123?tab=log#failure")
    #expect(local.absoluteString == "http://192.168.1.20:8080/builds/123")
    #expect(uppercaseScheme.scheme?.lowercased() == "https")
}

@Test func pushNotificationURLPolicyRejectsMissingOrDangerousURLs() {
    let invalidValues: [String?] = [
        nil,
        "",
        "   ",
        "/builds/123",
        "https:///builds/123",
        "ftp://ci.example.com/builds/123",
        "javascript:alert(1)",
        "https://user:password@ci.example.com/builds/123",
        "https://ci.example.com/builds/123\nnext",
    ]

    for value in invalidValues {
        #expect(PushNotificationURLPolicy.validatedURL(from: value) == nil)
    }
}

@Test func pushNotificationURLPolicyRejectsOversizedURLs() {
    let oversized = "https://example.com/" + String(repeating: "a", count: PushNotificationURLPolicy.maximumLength)

    #expect(PushNotificationURLPolicy.validatedURL(from: oversized) == nil)
}
