import Foundation
import Testing
@testable import DevBarCore

@Test func pushRegistrationUsesBearerTokenAndExpectedBody() async throws {
    let recorder = PushRequestRecorder(responseBody: """
    {"success":true,"code":20000,"data":{"registered":true,"relayDeviceId":"iphone-unit","environment":"development"}}
    """)
    let service = PushNotificationService(baseURL: URL(string: "https://relay.example")!, session: recorder.session)

    let response = try await service.register(
        .init(pushToken: "apns-token", bundleId: "cc.xjpz.DevBariOS", environment: .development, locale: "zh-Hans"),
        deviceToken: "relay-token"
    )

    #expect(response.registered)
    #expect(response.relayDeviceId == "iphone-unit")
    #expect(await recorder.lastRequest?.url?.path == "/api/devbar/push/register")
    #expect(await recorder.lastRequest?.value(forHTTPHeaderField: "Authorization") == "Bearer relay-token")
    let body = try #require(await recorder.lastRequestBody)
    let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: String])
    #expect(json["pushToken"] == "apns-token")
    #expect(json["environment"] == "development")
}

@Test func pushPreferencesDecodeNestedEnvelope() async throws {
    let recorder = PushRequestRecorder(responseBody: """
    {"success":true,"code":20000,"data":{"relayDeviceId":"iphone-unit","pushEnabled":true,"agentWatcherEnabled":false,"summaryEnabled":true,"iconUrl":"https://cdn.example.com/icon.png"}}
    """)
    let service = PushNotificationService(baseURL: URL(string: "https://relay.example")!, session: recorder.session)

    let preferences = try await service.fetchPreferences(deviceToken: "relay-token")

    #expect(preferences.relayDeviceId == "iphone-unit")
    #expect(!preferences.agentWatcherEnabled)
    #expect(preferences.iconUrl == "https://cdn.example.com/icon.png")
    #expect(await recorder.lastRequest?.httpMethod == "GET")
}

@Test func pushToStartRegistrationUsesExpectedPathAndBody() async throws {
    let recorder = PushRequestRecorder(responseBody: """
    {"success":true,"code":20000,"data":{"registered":true,"activityType":"devbar_live_message"}}
    """)
    let service = PushNotificationService(baseURL: URL(string: "https://relay.example")!, session: recorder.session)

    let response = try await service.registerLiveActivityPushToStart(
        .init(
            activityType: .devBarLiveMessage,
            pushToStartToken: "start-token",
            bundleId: "cc.xjpz.DevBar",
            environment: .development,
            minimumIOSVersion: "17.2"
        ),
        deviceToken: "relay-token"
    )

    #expect(response.registered)
    #expect(response.activityType == .devBarLiveMessage)
    #expect(await recorder.lastRequest?.url?.path == "/api/devbar/push/live-activities/push-to-start")
    #expect(await recorder.lastRequest?.value(forHTTPHeaderField: "Authorization") == "Bearer relay-token")
    let body = try #require(await recorder.lastRequestBody)
    let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: String])
    #expect(json["activityType"] == "devbar_live_message")
    #expect(json["pushToStartToken"] == "start-token")
    #expect(json["bundleId"] == "cc.xjpz.DevBar")
}

@Test func liveActivityRegistrationUsesExpectedPathAndBody() async throws {
    let recorder = PushRequestRecorder(responseBody: """
    {"success":true,"code":20000,"data":{"registered":true,"activityId":"activity-unit"}}
    """)
    let service = PushNotificationService(baseURL: URL(string: "https://relay.example")!, session: recorder.session)

    let response = try await service.registerLiveActivity(
        .init(
            activityId: "activity-unit",
            activityType: .devBarLiveMessage,
            activityPushToken: "update-token",
            bundleId: "cc.xjpz.DevBar",
            environment: .development,
            startedBy: .local
        ),
        deviceToken: "relay-token"
    )

    #expect(response.registered)
    #expect(response.activityId == "activity-unit")
    #expect(await recorder.lastRequest?.url?.path == "/api/devbar/push/live-activities")
    let body = try #require(await recorder.lastRequestBody)
    let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: String])
    #expect(json["activityPushToken"] == "update-token")
    #expect(json["startedBy"] == "local")
}

@Test func liveMessageSendUsesRemoteStartAndFallbackFlags() async throws {
    let recorder = PushRequestRecorder(responseBody: """
    {"success":true,"code":20000,"data":{"delivery":"live_activity","activityId":"activity-unit","startedBy":"remote","fallbackSent":false}}
    """)
    let service = PushNotificationService(baseURL: URL(string: "https://relay.example")!, session: recorder.session)

    let response = try await service.sendLiveMessage(
        .init(
            targetDeviceId: "iphone-unit",
            message: "构建完成，可以审核了",
            source: "Codex",
            projectName: "DevBar",
            eventId: "evt-unit",
            allowRemoteStart: true,
            fallbackNotification: true
        ),
        deviceToken: "relay-token"
    )

    #expect(response.delivery == .liveActivity)
    #expect(response.startedBy == .remote)
    #expect(response.fallbackSent == false)
    #expect(await recorder.lastRequest?.url?.path == "/api/devbar/push/live-message")
    let body = try #require(await recorder.lastRequestBody)
    let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
    #expect(json["message"] as? String == "构建完成，可以审核了")
    #expect(json["allowRemoteStart"] as? Bool == true)
    #expect(json["fallbackNotification"] as? Bool == true)
}

@Test func smsAlertSendUsesExpectedPathAndShortcutPayload() async throws {
    let recorder = PushRequestRecorder(responseBody: """
    {"success":true,"code":20000,"data":{"eventId":"sms-unit","targetDeviceId":"mac-unit","delivery":"relay_forwarded","fallbackSent":false,"duplicate":false}}
    """)
    let service = PushNotificationService(baseURL: URL(string: "https://relay.example")!, session: recorder.session)

    let response = try await service.sendSMSAlert(
        .init(
            targetDeviceId: "mac-unit",
            messageText: "您的验证码是 123456",
            sender: "955xx",
            matchedKeyword: "验证码",
            notificationTitle: "银行验证码",
            receivedAt: 1_780_660_000_000,
            dedupKey: "sms-dedup-unit",
            fallbackNotification: true
        ),
        deviceToken: "relay-token"
    )

    #expect(response.delivery == .relayForwarded)
    #expect(response.eventId == "sms-unit")
    #expect(response.targetDeviceId == "mac-unit")
    #expect(response.fallbackSent == false)
    #expect(response.duplicate == false)
    #expect(await recorder.lastRequest?.url?.path == "/api/devbar/push/sms-alert")
    #expect(await recorder.lastRequest?.value(forHTTPHeaderField: "Authorization") == "Bearer relay-token")
    let body = try #require(await recorder.lastRequestBody)
    let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
    #expect(json["messageText"] as? String == "您的验证码是 123456")
    #expect(json["sender"] as? String == "955xx")
    #expect(json["matchedKeyword"] as? String == "验证码")
    #expect(json["notificationTitle"] as? String == "银行验证码")
    #expect(json["targetDeviceId"] as? String == "mac-unit")
    #expect(json["dedupKey"] as? String == "sms-dedup-unit")
    #expect(json["fallbackNotification"] as? Bool == true)
}

private final class PushRequestRecorder: @unchecked Sendable {
    private let store = Store()
    let session: URLSession

    var lastRequest: URLRequest? { get async { store.request } }
    var lastRequestBody: Data? { get async { store.body } }

    init(responseBody: String) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [PushMockURLProtocol.self]
        let id = UUID().uuidString
        configuration.httpAdditionalHeaders = ["X-Test-Push-Recorder-ID": id]
        PushMockURLProtocol.register(id: id, responseBody: Data(responseBody.utf8)) { [store] request in
            store.request = request
            store.body = request.httpBody ?? request.httpBodyStream?.readAllData()
        }
        session = URLSession(configuration: configuration)
    }

    private final class Store: @unchecked Sendable {
        private let lock = NSLock()
        private var storedRequest: URLRequest?
        private var storedBody: Data?

        var request: URLRequest? {
            get { lock.withLock { storedRequest } }
            set { lock.withLock { storedRequest = newValue } }
        }

        var body: Data? {
            get { lock.withLock { storedBody } }
            set { lock.withLock { storedBody = newValue } }
        }
    }
}

private extension InputStream {
    func readAllData() -> Data {
        open()
        defer { close() }

        var data = Data()
        let bufferSize = 1_024
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }

        while hasBytesAvailable {
            let count = read(buffer, maxLength: bufferSize)
            guard count > 0 else { break }
            data.append(buffer, count: count)
        }
        return data
    }
}

private final class PushMockURLProtocol: URLProtocol, @unchecked Sendable {
    private struct Stub: @unchecked Sendable {
        let responseBody: Data
        let capture: @Sendable (URLRequest) -> Void
    }

    private static let store = StubStore()

    static func register(id: String, responseBody: Data, capture: @escaping @Sendable (URLRequest) -> Void) {
        store.set(Stub(responseBody: responseBody, capture: capture), for: id)
    }

    override class func canInit(with request: URLRequest) -> Bool {
        request.value(forHTTPHeaderField: "X-Test-Push-Recorder-ID") != nil
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let id = request.value(forHTTPHeaderField: "X-Test-Push-Recorder-ID"),
              let stub = Self.store.stub(for: id),
              let url = request.url,
              let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)
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

    private final class StubStore: @unchecked Sendable {
        private let lock = NSLock()
        private var stubs: [String: Stub] = [:]

        func set(_ stub: Stub, for id: String) {
            lock.withLock { stubs[id] = stub }
        }

        func stub(for id: String) -> Stub? {
            lock.withLock { stubs[id] }
        }
    }
}
