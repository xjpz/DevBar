import Foundation
import Testing
@testable import DevBarCore

@Test
func diagnosticsUploadServiceDeletesAcceptedEventsAfterSuccessfulUpload() async throws {
    let directory = try diagnosticsUploadTemporaryDirectory()
    let store = DiagnosticLogStore(directoryURL: directory)
    try store.append(DiagnosticLogEvent(
        eventId: "event-1",
        occurredAt: Date(timeIntervalSince1970: 1),
        level: .error,
        category: "hermes.api",
        name: "request_failed",
        message: "HTTP 503",
        platform: "ios",
        details: ["apiKey": "secret-key", "messageCount": "2"]
    ))
    try store.append(DiagnosticLogEvent(
        eventId: "event-2",
        occurredAt: Date(timeIntervalSince1970: 2),
        level: .warning,
        category: "app.lifecycle",
        name: "unclean_exit",
        message: "Previous exit was not clean",
        platform: "macos"
    ))

    let recorder = DiagnosticsUploadRequestRecorder(responseBody: """
    {
      "success": true,
      "code": 20000,
      "msg": "操作成功",
      "data": {
        "accepted": 2,
        "rejected": 0,
        "duplicate": 0
      }
    }
    """.data(using: .utf8)!)
    let service = DiagnosticsUploadService(
        baseURL: URL(string: "https://relay.example.test")!,
        session: recorder.session,
        store: store
    )

    let result = try await service.flush(deviceToken: "drt_v1.unit", limit: 10, maxBytes: 100_000)

    let request = try #require(recorder.lastRequest)
    let body = try #require(recorder.lastRequestBody)
    let object = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
    let events = try #require(object["events"] as? [[String: Any]])
    let firstDetails = try #require(events.first?["details"] as? [String: String])

    #expect(result.accepted == 2)
    #expect(result.rejected == 0)
    #expect(result.duplicate == 0)
    #expect(request.httpMethod == "POST")
    #expect(request.url?.absoluteString == "https://relay.example.test/api/devbar/diagnostics/logs")
    #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer drt_v1.unit")
    #expect(events.map { $0["eventId"] as? String } == ["event-1", "event-2"])
    #expect(firstDetails["apiKey"] == "<redacted:length=10>")
    #expect(try store.loadBatch(limit: 10, maxBytes: 100_000).isEmpty)
}

@Test
func diagnosticsUploadServiceKeepsEventsWhenUploadFails() async throws {
    let directory = try diagnosticsUploadTemporaryDirectory()
    let store = DiagnosticLogStore(directoryURL: directory)
    try store.append(DiagnosticLogEvent(
        eventId: "event-1",
        occurredAt: Date(timeIntervalSince1970: 1),
        level: .error,
        category: "hermes.api",
        name: "request_failed",
        message: "HTTP 503",
        platform: "ios"
    ))

    let recorder = DiagnosticsUploadRequestRecorder(
        statusCode: 503,
        responseBody: Data("{\"success\":false,\"code\":50300,\"msg\":\"unavailable\"}".utf8)
    )
    let service = DiagnosticsUploadService(
        baseURL: URL(string: "https://relay.example.test")!,
        session: recorder.session,
        store: store
    )

    await #expect(throws: DiagnosticsUploadServiceError.httpError(503)) {
        try await service.flush(deviceToken: "drt_v1.unit", limit: 10, maxBytes: 100_000)
    }
    #expect(try store.loadBatch(limit: 10, maxBytes: 100_000).map(\.eventId) == ["event-1"])
}

@Test
func diagnosticsUploadServiceReturnsEmptyResultWithoutNetworkWhenQueueIsEmpty() async throws {
    let recorder = DiagnosticsUploadRequestRecorder(responseBody: Data("{}".utf8))
    let store = DiagnosticLogStore(directoryURL: try diagnosticsUploadTemporaryDirectory())
    let service = DiagnosticsUploadService(
        baseURL: URL(string: "https://relay.example.test")!,
        session: recorder.session,
        store: store
    )

    let result = try await service.flush(deviceToken: "drt_v1.unit", limit: 10, maxBytes: 100_000)

    #expect(result.accepted == 0)
    #expect(recorder.lastRequest == nil)
}

private func diagnosticsUploadTemporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appending(path: "devbar-diagnostics-upload-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private final class DiagnosticsUploadRequestRecorder: @unchecked Sendable {
    private let id = UUID().uuidString
    let session: URLSession
    private let lock = NSLock()
    private var capturedRequest: URLRequest?
    private var capturedBody: Data?

    var lastRequest: URLRequest? {
        lock.lock()
        defer { lock.unlock() }
        return capturedRequest
    }

    var lastRequestBody: Data? {
        lock.lock()
        defer { lock.unlock() }
        return capturedBody
    }

    init(statusCode: Int = 200, responseBody: Data) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [DiagnosticsUploadMockURLProtocol.self]
        configuration.httpAdditionalHeaders = ["X-Diagnostics-Test-ID": id]
        session = URLSession(configuration: configuration)
        DiagnosticsUploadMockURLProtocol.register(id: id, statusCode: statusCode, responseBody: responseBody) { [weak self] request, body in
            self?.record(request: request, body: body)
        }
    }

    private func record(request: URLRequest, body: Data?) {
        lock.lock()
        capturedRequest = request
        capturedBody = body
        lock.unlock()
    }
}

private final class DiagnosticsUploadMockURLProtocol: URLProtocol, @unchecked Sendable {
    struct Response {
        let statusCode: Int
        let body: Data
        let capture: @Sendable (URLRequest, Data?) -> Void
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var responses: [String: Response] = [:]

    static func register(
        id: String,
        statusCode: Int,
        responseBody: Data,
        capture: @escaping @Sendable (URLRequest, Data?) -> Void
    ) {
        lock.lock()
        responses[id] = Response(statusCode: statusCode, body: responseBody, capture: capture)
        lock.unlock()
    }

    override class func canInit(with request: URLRequest) -> Bool {
        request.value(forHTTPHeaderField: "X-Diagnostics-Test-ID") != nil
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let id = request.value(forHTTPHeaderField: "X-Diagnostics-Test-ID") else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        Self.lock.lock()
        let response = Self.responses[id]
        Self.lock.unlock()
        guard let response, let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        response.capture(request, request.httpBody ?? request.httpBodyStream?.diagnosticsUploadData())
        let httpResponse = HTTPURLResponse(
            url: url,
            statusCode: response.statusCode,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: httpResponse, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: response.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private extension InputStream {
    func diagnosticsUploadData() -> Data {
        open()
        defer { close() }
        var data = Data()
        let bufferSize = 1_024
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }
        while hasBytesAvailable {
            let read = self.read(buffer, maxLength: bufferSize)
            if read <= 0 {
                break
            }
            data.append(buffer, count: read)
        }
        return data
    }
}
