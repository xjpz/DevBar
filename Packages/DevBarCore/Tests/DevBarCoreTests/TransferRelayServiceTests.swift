import Foundation
import Testing
@testable import DevBarCore

@Test
func relayFetchUsesAuthorizationHeaderOnly() async throws {
    let recorder = TransferRelayRequestRecorder(
        responseBody: """
        {
          "ciphertext": "AA",
          "nonce": "AA",
          "tag": "AA"
        }
        """.data(using: .utf8)!
    )
    let service = TransferRelayService(
        baseURL: URL(string: "https://relay.example.test")!,
        session: recorder.session
    )
    let url = try TransferPayloadCodec.makeRelayURL(
        transferID: "tr_unit",
        readToken: "rt_secret",
        encryptionKey: "ek_secret"
    )

    do {
        _ = try await service.resolveRelayTransfer(from: url)
    } catch {
        // Expected: the fixture is intentionally not decryptable. This test only verifies transport shape.
    }

    let request = try #require(await recorder.lastRequest)
    #expect(request.url?.absoluteString == "https://relay.example.test/api/devbar/transfers/tr_unit")
    #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer rt_secret")
    #expect(request.value(forHTTPHeaderField: "X-DevBar-Transfer-Token") == nil)
    #expect(request.value(forHTTPHeaderField: "X-Transfer-Token") == nil)
    #expect(request.url?.absoluteString.contains("ek_secret") == false)
    #expect(request.url?.absoluteString.contains("rt_secret") == false)
}

@Test
func relayCreateUploadsOnlyTokenHashAndCiphertext() async throws {
    let recorder = TransferRelayRequestRecorder(
        responseBody: """
        {
          "transfer_id": "tr_unit"
        }
        """.data(using: .utf8)!
    )
    let service = TransferRelayService(
        baseURL: URL(string: "https://relay.example.test")!,
        session: recorder.session
    )
    let payload = TransferPayload(
        exportedAt: Date(timeIntervalSince1970: 1_700_000_000),
        expiresAt: Date(timeIntervalSince1970: 4_100_000_000),
        deviceName: "Unit Mac",
        accountConfigs: [
            AccountConfig(provider: .glm, isEnabled: true, order: 0),
            AccountConfig(provider: .openai, isEnabled: true, order: 1),
            AccountConfig(provider: .mimo, isEnabled: true, order: 2),
        ],
        providers: [
            ProviderTransferPayload(
                provider: .glm,
                credentials: ProviderTransferCredentials(token: largeToken(prefix: "glm"))
            ),
            ProviderTransferPayload(
                provider: .openai,
                credentials: ProviderTransferCredentials(token: largeToken(prefix: "openai"))
            ),
            ProviderTransferPayload(
                provider: .mimo,
                credentials: ProviderTransferCredentials(token: largeToken(prefix: "mimo"))
            ),
        ]
    )

    let result = try await service.makeTransferQRCode(
        for: payload,
        client: TransferRelayClientInfo(platform: "macos")
    )

    let request = try #require(await recorder.lastRequest)
    let body = try #require(await recorder.lastRequestBody)
    let bodyObject = try #require(
        JSONSerialization.jsonObject(with: body) as? [String: Any]
    )

    #expect(result.url.absoluteString.hasPrefix("devbar://transfer/relay?id=tr_unit&token=rt_"))
    #expect(result.url.absoluteString.contains("#key=ek_"))
    #expect(request.httpMethod == "POST")
    #expect(request.url?.absoluteString == "https://relay.example.test/api/devbar/transfers")
    #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
    #expect((bodyObject["read_token_hash"] as? String)?.hasPrefix("sha256:") == true)
    #expect(bodyObject["ciphertext"] as? String != nil)
    #expect(bodyObject["nonce"] as? String != nil)
    #expect(bodyObject["tag"] as? String != nil)
    #expect(bodyObject["read_token"] == nil)
    #expect(bodyObject["encryption_key"] == nil)
    #expect((bodyObject["read_token_hash"] as? String)?.contains("rt_") == false)
}

private func largeToken(prefix: String) -> String {
    (0..<240)
        .map { "\(prefix)_\($0)_\(UUID().uuidString)" }
        .joined(separator: ".")
}

private final class TransferRelayRequestRecorder: @unchecked Sendable {
    private let requestStore = CapturedRequestStore()
    let session: URLSession

    var lastRequest: URLRequest? {
        get async {
            requestStore.request
        }
    }

    var lastRequestBody: Data? {
        get async {
            requestStore.body
        }
    }

    init(responseBody: Data, statusCode: Int = 200) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [TransferRelayMockURLProtocol.self]
        let id = UUID()
        configuration.httpAdditionalHeaders = ["X-Test-Recorder-ID": id.uuidString]
        TransferRelayMockURLProtocol.register(
            recorderID: id.uuidString,
            responseBody: responseBody,
            statusCode: statusCode,
            capture: { [requestStore] request, body in
                requestStore.request = request
                requestStore.body = body
            }
        )
        self.session = URLSession(configuration: configuration)
    }

    private final class CapturedRequestStore: @unchecked Sendable {
        private let lock = NSLock()
        private var storedRequest: URLRequest?
        private var storedBody: Data?

        var request: URLRequest? {
            get {
                lock.withLock { storedRequest }
            }
            set {
                lock.withLock { storedRequest = newValue }
            }
        }

        var body: Data? {
            get {
                lock.withLock { storedBody }
            }
            set {
                lock.withLock { storedBody = newValue }
            }
        }
    }
}

private final class TransferRelayMockURLProtocol: URLProtocol, @unchecked Sendable {
    private struct Stub: Sendable {
        let responseBody: Data
        let statusCode: Int
        let capture: @Sendable (URLRequest, Data?) -> Void
    }

    private static let store = StubStore()

    static func register(
        recorderID: String,
        responseBody: Data,
        statusCode: Int,
        capture: @escaping @Sendable (URLRequest, Data?) -> Void
    ) {
        store.set(
            Stub(
                responseBody: responseBody,
                statusCode: statusCode,
                capture: capture
            ),
            for: recorderID
        )
    }

    override class func canInit(with request: URLRequest) -> Bool {
        request.value(forHTTPHeaderField: "X-Test-Recorder-ID") != nil
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let recorderID = request.value(forHTTPHeaderField: "X-Test-Recorder-ID"),
              let stub = Self.store.stub(for: recorderID),
              let url = request.url,
              let response = HTTPURLResponse(
                url: url,
                statusCode: stub.statusCode,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
              ) else {
            client?.urlProtocol(self, didFailWithError: TransferPayloadError.invalidRelayResponse)
            return
        }

        stub.capture(request, requestBodyData())
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: stub.responseBody)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private func requestBodyData() -> Data? {
        if let httpBody = request.httpBody {
            return httpBody
        }
        guard let stream = request.httpBodyStream else {
            return nil
        }

        stream.open()
        defer { stream.close() }

        var data = Data()
        let bufferSize = 8_192
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }

        while stream.hasBytesAvailable {
            let count = stream.read(buffer, maxLength: bufferSize)
            if count > 0 {
                data.append(buffer, count: count)
            } else {
                break
            }
        }
        return data
    }

    private final class StubStore: @unchecked Sendable {
        private let lock = NSLock()
        private var stubs: [String: Stub] = [:]

        func set(_ stub: Stub, for recorderID: String) {
            lock.withLock {
                stubs[recorderID] = stub
            }
        }

        func stub(for recorderID: String) -> Stub? {
            lock.withLock {
                stubs[recorderID]
            }
        }
    }
}
