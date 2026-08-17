import Foundation
import Testing

@testable import DevBarCore

@Test
func parsesValidRemoteLinkAndExtractsDesktopName() {
    let raw = "https://zcode.z.ai/remote/v4?sid=d_LneUR4Wvb4oX&hash=QlHTssMqq2B%2BUhU%3D&t=1786957722108&mid=0d7a7450-b42e-141953e8dd80&name=xjpzdeMacBook-Pro.local&app_version=3.7.7"

    let link = ZCodeRemoteLink(rawValue: raw)

    #expect(link != nil)
    #expect(link?.desktopName == "xjpzdeMacBook-Pro.local")
    #expect(link?.url.host == "zcode.z.ai")
}

@Test
func trimsWhitespaceAndNewlinesFromCopiedLink() {
    let raw = """
    \n  https://zcode.z.ai/remote/v4?sid=abc&hash=def%3D  \n
    """

    let link = ZCodeRemoteLink(rawValue: raw)

    #expect(link != nil)
    #expect(link?.desktopName == nil)
}

@Test
func rejectsNonHTTPSScheme() {
    #expect(ZCodeRemoteLink(rawValue: "http://zcode.z.ai/remote/v4?sid=abc&hash=def") == nil)
}

@Test
func rejectsForeignHost() {
    #expect(ZCodeRemoteLink(rawValue: "https://zcode.z.ai.evil.com/remote/v4?sid=abc&hash=def") == nil)
    #expect(ZCodeRemoteLink(rawValue: "https://example.com/remote/v4?sid=abc&hash=def") == nil)
}

@Test
func rejectsNonRemotePath() {
    #expect(ZCodeRemoteLink(rawValue: "https://zcode.z.ai/docs?sid=abc&hash=def") == nil)
    #expect(ZCodeRemoteLink(rawValue: "https://zcode.z.ai/remoteover/v4?sid=abc&hash=def") == nil)
}

@Test
func acceptsFutureRemotePathVersions() {
    #expect(ZCodeRemoteLink(rawValue: "https://zcode.z.ai/remote/v9?sid=abc&hash=def") != nil)
}

@Test
func rejectsMissingOrEmptyCredentials() {
    #expect(ZCodeRemoteLink(rawValue: "https://zcode.z.ai/remote/v4?sid=abc") == nil)
    #expect(ZCodeRemoteLink(rawValue: "https://zcode.z.ai/remote/v4?hash=def") == nil)
    #expect(ZCodeRemoteLink(rawValue: "https://zcode.z.ai/remote/v4?sid=&hash=def") == nil)
    #expect(ZCodeRemoteLink(rawValue: "https://zcode.z.ai/remote/v4?sid=abc&hash=") == nil)
}

@Test
func rejectsGarbageInput() {
    #expect(ZCodeRemoteLink(rawValue: "") == nil)
    #expect(ZCodeRemoteLink(rawValue: "hello world") == nil)
    #expect(ZCodeRemoteLink(rawValue: "https://zcode.z.ai") == nil)
}

@Test
func maskedDescriptionNeverContainsCredentials() {
    let raw = "https://zcode.z.ai/remote/v4?sid=d_LneUR4Wvb4oX&hash=QlHTssMqq2B%2BUhU%3D"
    let link = ZCodeRemoteLink(rawValue: raw)

    #expect(link?.maskedDescription == "https://zcode.z.ai/remote/…")
}
