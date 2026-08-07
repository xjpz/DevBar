import Foundation
import Testing
@testable import DevBarCore

@Suite("Home Assistant diagnostics")
struct HomeAssistantDiagnosticsTests {
    @Test("REST HTTP failures retain status and only a structural payload summary")
    func restHTTPFailureIsRecordedWithoutPayloadValues() async throws {
        let capture = HomeAssistantDiagnosticCapture()
        let reporter = HomeAssistantDiagnosticReporter(
            diagnostics: capture,
            deduplicationInterval: 0,
            eventRecorded: {}
        )
        let mock = HomeAssistantRESTMock.response(
            statusCode: 503,
            body: Data(#"{"error":{"message":"private instance detail"}}"#.utf8)
        )
        let client = HomeAssistantRESTClient(session: mock.session, diagnostics: reporter)

        do {
            try await client.checkConnection(
                baseURL: URL(string: "https://ha.example.test/root?access_token=secret")!,
                token: "long-lived-secret"
            )
            Issue.record("Expected HTTP 503 to throw")
        } catch HomeAssistantError.invalidResponse {
            // Expected.
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        let event = try #require(capture.events.first)
        #expect(event.category == "home_assistant.rest")
        #expect(event.name == "http_response_failed")
        #expect(event.httpStatus == 503)
        #expect(event.endpoint == "https://ha.example.test/api/")
        #expect(event.details["payloadShape"] == "object(count=1,keys=error)")
        #expect(event.details.values.joined().contains("private instance detail") == false)
        #expect(event.details.values.joined().contains("long-lived-secret") == false)
    }

    @Test("REST decode failures retain the coding path and response shape")
    func restDecodeFailureIsRecorded() async throws {
        let capture = HomeAssistantDiagnosticCapture()
        let reporter = HomeAssistantDiagnosticReporter(
            diagnostics: capture,
            deduplicationInterval: 0,
            eventRecorded: {}
        )
        let mock = HomeAssistantRESTMock.response(
            statusCode: 200,
            body: Data(#"{"entity_id":"light.one"}"#.utf8)
        )
        let client = HomeAssistantRESTClient(session: mock.session, diagnostics: reporter)

        do {
            _ = try await client.fetchStates(
                baseURL: URL(string: "https://ha.example.test")!,
                token: "secret"
            )
            Issue.record("Expected an invalid response")
        } catch HomeAssistantError.invalidResponse {
            // Expected.
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        let event = try #require(capture.events.first)
        #expect(event.name == "response_decode_failed")
        #expect(event.details["decodingKind"] == "type_mismatch")
        #expect(event.details["codingPath"] == "<root>")
        #expect(event.details["payloadShape"] == "object(count=1,keys=entity_id)")
    }

    @Test("REST transport failures retain URL error codes")
    func restTransportFailureIsRecorded() async throws {
        let capture = HomeAssistantDiagnosticCapture()
        let reporter = HomeAssistantDiagnosticReporter(
            diagnostics: capture,
            deduplicationInterval: 0,
            eventRecorded: {}
        )
        let mock = HomeAssistantRESTMock.failure(URLError(.notConnectedToInternet))
        let client = HomeAssistantRESTClient(session: mock.session, diagnostics: reporter)

        do {
            try await client.checkConnection(
                baseURL: URL(string: "https://ha.example.test")!,
                token: "secret"
            )
            Issue.record("Expected transport failure")
        } catch {
            // Expected.
        }

        let event = try #require(capture.events.first)
        #expect(event.name == "request_transport_failed")
        #expect(event.details["urlErrorCode"] == String(URLError.notConnectedToInternet.rawValue))
    }

    @Test("Repeated diagnostics are coalesced and trigger upload once")
    func repeatedEventsAreDeduplicated() {
        let capture = HomeAssistantDiagnosticCapture()
        let notifications = HomeAssistantNotificationCounter()
        let reporter = HomeAssistantDiagnosticReporter(
            diagnostics: capture,
            deduplicationInterval: 30,
            eventRecorded: { notifications.increment() }
        )
        let endpoint = URL(string: "wss://ha.example.test/api/websocket?token=secret")!

        reporter.record(
            category: "home_assistant.websocket",
            name: "websocket_message_decode_failed",
            operation: "receive_envelope",
            endpoint: endpoint,
            error: HomeAssistantError.invalidResponse,
            responseData: Data("not-json".utf8)
        )
        reporter.record(
            category: "home_assistant.websocket",
            name: "websocket_message_decode_failed",
            operation: "receive_envelope",
            endpoint: endpoint,
            error: HomeAssistantError.invalidResponse,
            responseData: Data("not-json-again".utf8)
        )

        #expect(capture.events.count == 1)
        #expect(notifications.value == 1)
        #expect(capture.events.first?.endpoint == "wss://ha.example.test/api/websocket")
        #expect(capture.events.first?.details["responsePreview"] == "not-json")
    }

    @Test("Malformed WebSocket envelopes and state events fail independently")
    func malformedWebSocketPayloadsAreDetectable() throws {
        #expect(throws: DecodingError.self) {
            _ = try HomeAssistantWebSocketPayloadDecoder.decodeEnvelope(Data("not-json".utf8))
        }

        let malformedState = HomeAssistantJSONValue.object([
            "entity_id": .string("light.one"),
            "attributes": .object([:]),
        ])
        #expect(throws: DecodingError.self) {
            _ = try HomeAssistantWebSocketPayloadDecoder.decodeState(malformedState)
        }

        let validEnvelope = try HomeAssistantWebSocketPayloadDecoder.decodeEnvelope(
            Data(#"{"type":"event","event":{"data":{}}}"#.utf8)
        )
        #expect(validEnvelope["type"]?.stringValue == "event")
    }
}

private final class HomeAssistantDiagnosticCapture: DiagnosticReporting, @unchecked Sendable {
    private let lock = NSLock()
    private var capturedEvents: [DiagnosticLogEvent] = []

    var events: [DiagnosticLogEvent] {
        lock.lock()
        defer { lock.unlock() }
        return capturedEvents
    }

    func record(_ event: DiagnosticLogEvent) {
        lock.lock()
        capturedEvents.append(event)
        lock.unlock()
    }
}

private final class HomeAssistantNotificationCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }

    func increment() {
        lock.lock()
        count += 1
        lock.unlock()
    }
}

private struct HomeAssistantRESTMock {
    let session: URLSession

    static func response(statusCode: Int, body: Data) -> HomeAssistantRESTMock {
        make(.response(statusCode: statusCode, body: body))
    }

    static func failure(_ error: Error) -> HomeAssistantRESTMock {
        make(.failure(error as NSError))
    }

    private static func make(_ result: HomeAssistantRESTMockURLProtocol.Result) -> HomeAssistantRESTMock {
        let id = UUID().uuidString
        HomeAssistantRESTMockURLProtocol.register(id: id, result: result)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [HomeAssistantRESTMockURLProtocol.self]
        configuration.httpAdditionalHeaders = ["X-Home-Assistant-Test-ID": id]
        return HomeAssistantRESTMock(session: URLSession(configuration: configuration))
    }
}

private final class HomeAssistantRESTMockURLProtocol: URLProtocol, @unchecked Sendable {
    enum Result: @unchecked Sendable {
        case response(statusCode: Int, body: Data)
        case failure(NSError)
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var results: [String: Result] = [:]

    static func register(id: String, result: Result) {
        lock.lock()
        results[id] = result
        lock.unlock()
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let id = request.value(forHTTPHeaderField: "X-Home-Assistant-Test-ID") else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        Self.lock.lock()
        let result = Self.results.removeValue(forKey: id)
        Self.lock.unlock()
        guard let result, let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        switch result {
        case .response(let statusCode, let body):
            let response = HTTPURLResponse(
                url: url,
                statusCode: statusCode,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
        case .failure(let error):
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
