import Foundation
import Testing
@testable import DevBarCore

@Test
func pushMessageDecodesWithoutSnippetAndUsesReadTime() throws {
    let data = Data("""
    {
      "id": 42,
      "messageId": "msg_push_42",
      "snippetId": null,
      "title": "构建完成",
      "preview": "构建已完成",
      "body": "构建已完成，可以开始审核。",
      "source": "device_push_api",
      "messageType": "push_text",
      "targetURL": "https://ci.example.com/build/42",
      "readTime": 0,
      "isRead": false,
      "createdAt": 1000
    }
    """.utf8)

    let message = try JSONDecoder().decode(DevBarMessage.self, from: data)

    #expect(message.snippetId == nil)
    #expect(message.messageId == "msg_push_42")
    #expect(message.messageType == "push_text")
    #expect(message.readTime == 0)
    #expect(!message.isRead)
}

@Test
func legacySnippetMessageDecodingRemainsCompatible() throws {
    let data = Data("""
    {
      "id": 7,
      "snippetId": 9,
      "title": "旧消息",
      "preview": null,
      "body": null,
      "source": "api",
      "isRead": true,
      "createdAt": 1234
    }
    """.utf8)

    let message = try JSONDecoder().decode(DevBarMessage.self, from: data)

    #expect(message.messageId == "msg_legacy_7")
    #expect(message.snippetId == 9)
    #expect(message.messageType == "snippet")
    #expect(message.readTime == 1234)
    #expect(message.isRead)
}

@Test
func messageReadProjectionUsesZeroAsUnreadSentinel() {
    var message = DevBarMessage(
        id: 1,
        messageId: "msg_1",
        snippetId: nil,
        title: "通知",
        preview: nil,
        body: nil,
        source: "device_push_api",
        messageType: "push_text",
        targetURL: nil,
        readTime: 0,
        createdAt: 1
    )

    #expect(!message.isRead)
    message.isRead = true
    #expect(message.readTime > 0)
    message.isRead = false
    #expect(message.readTime == 0)
}

@Test
func messageKindUsesStableServerTypeAndFallsBackForUnknownValues() {
    #expect(DevBarMessageKind(messageType: "news_digest") == .newsDigest)
    #expect(DevBarMessageKind(messageType: "tech_news") == .newsDigest)
    #expect(DevBarMessageKind(messageType: "snippet") == .snippet)
    #expect(DevBarMessageKind(messageType: "push_text") == .textPush)
    #expect(DevBarMessageKind(messageType: "system_notice") == .system)
    #expect(DevBarMessageKind(messageType: "future_type") == .unknown)
    #expect(DevBarMessageKind(messageType: "  NEWS_DIGEST  ") == .newsDigest)
}

@Test
func deviceBindingSendsBothAccountAndDeviceCredentials() async throws {
    let recorder = DevBarAccountRequestRecorder(responseBody: """
    {
      "data": {
        "deviceId": "iphone-unit",
        "linked": true,
        "claimedSnippets": 1,
        "claimedMessages": 2,
        "claimedPushKeys": 3
      }
    }
    """)
    let client = DevBarAccountAPIClient(
        baseURL: URL(string: "https://unit.example.com")!,
        session: recorder.session
    )

    let result = try await client.linkCurrentDevice(
        appToken: "app-session-unit",
        deviceToken: "relay-device-unit",
        deviceSecret: "relay-secret-unit"
    )

    let request = try #require(recorder.lastRequest)
    #expect(request.url?.path == DevBarCoreConstants.Account.deviceBindingPath)
    #expect(request.httpMethod == "POST")
    #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer app-session-unit")
    #expect(request.value(forHTTPHeaderField: "X-Device-Token") == "relay-device-unit")
    #expect(request.value(forHTTPHeaderField: "X-Device-Secret") == "relay-secret-unit")
    #expect(result.deviceId == "iphone-unit")
    #expect(result.claimedMessages == 2)
    #expect(result.claimedPushKeys == 3)
}

@Test
func accountDeletionUsesAuthenticatedDeleteEndpoint() async throws {
    let recorder = DevBarAccountRequestRecorder(responseBody: """
    {"code":0,"msg":"账户已注销","data":null}
    """)
    let client = DevBarAccountAPIClient(
        baseURL: URL(string: "https://unit.example.com")!,
        session: recorder.session
    )

    try await client.deleteAccount(token: "app-session-unit")

    let request = try #require(recorder.lastRequest)
    #expect(request.url?.path == DevBarCoreConstants.Account.deleteAccountPath)
    #expect(request.httpMethod == "DELETE")
    #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer app-session-unit")
    #expect(request.httpBody == nil)
}

@Test
func messageMutationReturnsAuthoritativeUnreadCount() async throws {
    let recorder = DevBarAccountRequestRecorder(responseBody: """
    {"code":0,"msg":"已标记为已读","data":{"affected":1,"unreadCount":4}}
    """)
    let client = DevBarAccountAPIClient(
        baseURL: URL(string: "https://unit.example.com")!,
        session: recorder.session
    )

    let result = try await client.setMessageRead(42, isRead: true, token: "app-session-unit")

    #expect(result.affected == 1)
    #expect(result.unreadCount == 4)
    let request = try #require(recorder.lastRequest)
    #expect(request.url?.path == "\(DevBarCoreConstants.Account.messagesPath)/42/read")
    #expect(request.httpMethod == "PUT")
}

private final class DevBarAccountRequestRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var capturedRequest: URLRequest?
    let session: URLSession

    var lastRequest: URLRequest? {
        lock.withLock { capturedRequest }
    }

    init(responseBody: String) {
        let id = UUID().uuidString
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [DevBarAccountMockURLProtocol.self]
        configuration.httpAdditionalHeaders = ["X-DevBar-Account-Test-ID": id]
        session = URLSession(configuration: configuration)
        DevBarAccountMockURLProtocol.register(id: id, responseBody: Data(responseBody.utf8)) { [weak self] request in
            self?.lock.withLock { self?.capturedRequest = request }
        }
    }
}

private final class DevBarAccountMockURLProtocol: URLProtocol, @unchecked Sendable {
    private struct Stub: @unchecked Sendable {
        let responseBody: Data
        let capture: @Sendable (URLRequest) -> Void
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var stubs: [String: Stub] = [:]

    static func register(id: String, responseBody: Data, capture: @escaping @Sendable (URLRequest) -> Void) {
        lock.withLock { stubs[id] = Stub(responseBody: responseBody, capture: capture) }
    }

    override class func canInit(with request: URLRequest) -> Bool {
        request.value(forHTTPHeaderField: "X-DevBar-Account-Test-ID") != nil
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let id = request.value(forHTTPHeaderField: "X-DevBar-Account-Test-ID"),
              let stub = Self.lock.withLock({ Self.stubs[id] }),
              let url = request.url,
              let response = HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
              )
        else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        stub.capture(request)
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: stub.responseBody)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
