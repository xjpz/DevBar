import Foundation
import Testing
@testable import DevBarCore

@Test
func hermesAPIClientNormalizesChatURLFromBaseURL() throws {
    let url = try #require(HermesAPIClient.chatURL(from: " https://hermes.example.com/api/ "))

    #expect(url.absoluteString == "https://hermes.example.com/api/chat/completions")
}

@Test
func hermesAPIClientKeepsExplicitChatCompletionsURL() throws {
    let url = try #require(HermesAPIClient.chatURL(from: "https://hermes.example.com/v1/chat/completions"))

    #expect(url.absoluteString == "https://hermes.example.com/v1/chat/completions")
}

@Test
func hermesAPIClientBuildsModelsCapabilitiesAndResponsesURLsFromAPIBase() throws {
    #expect(HermesAPIClient.modelsURL(from: "https://hermes.example.com/v1")?.absoluteString == "https://hermes.example.com/v1/models")
    #expect(HermesAPIClient.capabilitiesURL(from: "https://hermes.example.com/v1/chat/completions")?.absoluteString == "https://hermes.example.com/v1/capabilities")
    #expect(HermesAPIClient.responsesURL(from: "https://hermes.example.com/v1/")?.absoluteString == "https://hermes.example.com/v1/responses")
}

@Test
func hermesAPIClientRejectsInvalidBaseURL() {
    #expect(HermesAPIClient.chatURL(from: "not a url") == nil)
}

@Test
func hermesAPIClientUsesLongRunningRequestTimeouts() {
    #expect(HermesAPIClient.defaultRequestTimeout == 180)
    #expect(HermesAPIClient.defaultResourceTimeout == 300)
}

@Test
func hermesAPIClientDecodesOpenAICompatibleTextResponse() throws {
    let json = """
    {
      "choices": [
        {
          "message": {
            "role": "assistant",
            "content": "部署问题检查完成"
          }
        }
      ]
    }
    """.data(using: .utf8)!

    let response = try JSONDecoder().decode(HermesChatResponse.self, from: json)

    #expect(response.assistantContent == "部署问题检查完成")
}

@Test
func hermesAPIClientParsesSSETextDeltas() {
    let stream = """
    data: {"choices":[{"delta":{"content":"你好"}}]}

    data: {"choices":[{"delta":{"content":"，Hermes"}}]}

    data: [DONE]

    """

    #expect(HermesAPIClient.parseStreamDeltas(from: stream) == ["你好", "，Hermes"])
}

@Test
func hermesAPIClientIncludesModelAndOmitsProviderInChatRequestBody() async throws {
    let store = HermesAPIRequestStore()
    let session = URLSession(configuration: .hermesAPIMock(id: store.id))
    HermesAPIMockURLProtocol.register(id: store.id, responseBody: """
    {"choices":[{"message":{"role":"assistant","content":"ok"}}]}
    """.data(using: .utf8)!) { [store] request, body in
        store.request = request
        store.body = body
    }

    let client = HermesAPIClient(session: session)
    let content = try await client.sendMessage(
        baseURL: "https://hermes.example.test/v1",
        apiKey: "test-key",
        messages: [HermesChatRequestMessage(role: .user, content: "你好")],
        model: "hermes-agent",
        stream: false
    )

    #expect(content == "ok")
    #expect(store.request?.url?.absoluteString == "https://hermes.example.test/v1/chat/completions")
    #expect(store.request?.value(forHTTPHeaderField: "Authorization") == "Bearer test-key")
    let body = try #require(store.body)
    let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
    #expect(json?["model"] as? String == "hermes-agent")
    #expect(json?["provider"] == nil)
    #expect(json?["stream"] as? Bool == false)
}

@Test
func hermesAPIClientEncodesImageURLContentPartsInChatRequestBody() async throws {
    let store = HermesAPIRequestStore()
    let session = URLSession(configuration: .hermesAPIMock(id: store.id))
    HermesAPIMockURLProtocol.register(id: store.id, responseBody: """
    {"choices":[{"message":{"role":"assistant","content":"ok"}}]}
    """.data(using: .utf8)!) { [store] request, body in
        store.request = request
        store.body = body
    }

    let client = HermesAPIClient(session: session)
    let content = try await client.sendMessage(
        baseURL: "https://hermes.example.test/v1",
        apiKey: "test-key",
        messages: [
            HermesChatRequestMessage(
                role: .user,
                content: .parts([
                    .text("请分析这张图片"),
                    .imageURL("data:image/jpeg;base64,abc123")
                ])
            )
        ],
        model: "hermes-agent",
        stream: false
    )

    #expect(content == "ok")
    let body = try #require(store.body)
    let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
    let messages = try #require(json?["messages"] as? [[String: Any]])
    let contentParts = try #require(messages.first?["content"] as? [[String: Any]])
    #expect(contentParts.first?["type"] as? String == "text")
    #expect(contentParts.first?["text"] as? String == "请分析这张图片")
    #expect(contentParts.last?["type"] as? String == "image_url")
    let imageURL = try #require(contentParts.last?["image_url"] as? [String: Any])
    #expect(imageURL["url"] as? String == "data:image/jpeg;base64,abc123")
}

@Test
func hermesAPIClientDiscoversModels() async throws {
    let store = HermesAPIRequestStore()
    let session = URLSession(configuration: .hermesAPIMock(id: store.id))
    HermesAPIMockURLProtocol.register(id: store.id, responseBody: """
    {
      "object": "list",
      "data": [
        {"id": "hermes-agent", "object": "model"},
        {"id": "alice", "object": "model"}
      ]
    }
    """.data(using: .utf8)!) { [store] request, body in
        store.request = request
        store.body = body
    }

    let client = HermesAPIClient(session: session)
    let models = try await client.fetchModels(baseURL: "https://hermes.example.test/v1", apiKey: "test-key")

    #expect(models.map(\.id) == ["hermes-agent", "alice"])
    #expect(store.request?.url?.absoluteString == "https://hermes.example.test/v1/models")
    #expect(store.request?.httpMethod == "GET")
    #expect(store.request?.value(forHTTPHeaderField: "Authorization") == "Bearer test-key")
    #expect(store.body == nil)
}

@Test
func hermesAPIClientDiscoversCapabilities() async throws {
    let store = HermesAPIRequestStore()
    let session = URLSession(configuration: .hermesAPIMock(id: store.id))
    HermesAPIMockURLProtocol.register(id: store.id, responseBody: """
    {
      "object": "hermes.api_server.capabilities",
      "platform": "hermes-agent",
      "model": "hermes-agent",
      "auth": {"type": "bearer", "required": true},
      "features": {
        "chat_completions": true,
        "responses_api": true,
        "run_submission": true,
        "run_events_sse": true,
        "run_stop": true
      }
    }
    """.data(using: .utf8)!) { [store] request, _ in
        store.request = request
    }

    let client = HermesAPIClient(session: session)
    let capabilities = try await client.fetchCapabilities(baseURL: "https://hermes.example.test/v1", apiKey: "test-key")

    #expect(capabilities.model == "hermes-agent")
    #expect(capabilities.auth.required)
    #expect(capabilities.features.chatCompletions)
    #expect(capabilities.features.responsesAPI)
    #expect(capabilities.features.runEventsSSE)
    #expect(capabilities.features.runStop)
    #expect(store.request?.url?.absoluteString == "https://hermes.example.test/v1/capabilities")
}

@Test
func hermesAPIClientSendsNamedResponsesConversation() async throws {
    let store = HermesAPIRequestStore()
    let session = URLSession(configuration: .hermesAPIMock(id: store.id))
    HermesAPIMockURLProtocol.register(id: store.id, responseBody: """
    {
      "id": "resp_abc123",
      "object": "response",
      "status": "completed",
      "model": "hermes-agent",
      "output": [
        {
          "type": "message",
          "role": "assistant",
          "content": [
            {"type": "output_text", "text": "命名对话已继续"}
          ]
        }
      ]
    }
    """.data(using: .utf8)!) { [store] request, body in
        store.request = request
        store.body = body
    }

    let client = HermesAPIClient(session: session)
    let content = try await client.sendResponse(
        baseURL: "https://hermes.example.test/v1",
        apiKey: "test-key",
        input: "继续",
        model: "hermes-agent",
        conversation: "devbar-ios-00000000-0000-0000-0000-000000000001"
    )

    #expect(content == "命名对话已继续")
    #expect(store.request?.url?.absoluteString == "https://hermes.example.test/v1/responses")
    let body = try #require(store.body)
    let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
    #expect(json?["input"] as? String == "继续")
    #expect(json?["model"] as? String == "hermes-agent")
    #expect(json?["conversation"] as? String == "devbar-ios-00000000-0000-0000-0000-000000000001")
    #expect(json?["store"] as? Bool == true)
    #expect(json?["provider"] == nil)
}

@Test
func hermesAPIClientRecordsDiagnosticEventForHTTPFailure() async throws {
    let store = HermesAPIRequestStore()
    let diagnostics = HermesDiagnosticCapture()
    let session = URLSession(configuration: .hermesAPIMock(id: store.id))
    HermesAPIMockURLProtocol.register(
        id: store.id,
        statusCode: 503,
        responseBody: Data("{\"error\":{\"message\":\"Authorization: Bearer secret\"}}".utf8)
    ) { [store] request, body in
        store.request = request
        store.body = body
    }

    let client = HermesAPIClient(session: session, diagnostics: diagnostics)

    do {
        _ = try await client.sendMessage(
            baseURL: "https://hermes.example.test/v1",
            apiKey: "test-key",
            messages: [HermesChatRequestMessage(role: .user, content: "你好")],
            model: "hermes-agent",
            stream: false
        )
        Issue.record("Expected HTTP 503 to throw")
    } catch APIError.httpError(let code) {
        #expect(code == 503)
    } catch {
        Issue.record("Expected APIError.httpError, got \(error)")
    }

    let request = try #require(store.request)
    let requestId = try #require(request.value(forHTTPHeaderField: "X-Request-ID"))
    let event = try #require(diagnostics.events.first)

    #expect(requestId.isEmpty == false)
    #expect(event.level == .error)
    #expect(event.category == "hermes.api")
    #expect(event.name == "hermes_http_failed")
    #expect(event.requestId == requestId)
    #expect(event.endpoint == "chat/completions")
    #expect(event.httpStatus == 503)
    #expect(event.details["model"] == "hermes-agent")
    #expect(event.details["stream"] == "false")
    #expect(event.details["responsePreview"] == "<redacted:length=52>")
}

private final class HermesAPIRequestStore: @unchecked Sendable {
    let id = UUID().uuidString
    var request: URLRequest?
    var body: Data?
}

private final class HermesDiagnosticCapture: DiagnosticReporting, @unchecked Sendable {
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

private extension URLSessionConfiguration {
    static func hermesAPIMock(id: String) -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [HermesAPIMockURLProtocol.self]
        configuration.httpAdditionalHeaders = ["X-Test-Store-ID": id]
        return configuration
    }
}

private final class HermesAPIMockURLProtocol: URLProtocol, @unchecked Sendable {
    typealias Observer = @Sendable (URLRequest, Data?) -> Void

    private struct Response: @unchecked Sendable {
        let statusCode: Int
        let body: Data
        let observer: Observer?
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var responses: [String: Response] = [:]

    static func register(id: String, statusCode: Int = 200, responseBody: Data, observer: Observer? = nil) {
        lock.lock()
        defer { lock.unlock() }
        responses[id] = Response(statusCode: statusCode, body: responseBody, observer: observer)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let id = request.value(forHTTPHeaderField: "X-Test-Store-ID") else {
            client?.urlProtocol(self, didFailWithError: APIError.invalidResponse)
            return
        }
        Self.lock.lock()
        let response = Self.responses[id]
        Self.lock.unlock()

        guard let response, let url = request.url else {
            client?.urlProtocol(self, didFailWithError: APIError.invalidResponse)
            return
        }

        response.observer?(request, Self.bodyData(from: request))
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

    private static func bodyData(from request: URLRequest) -> Data? {
        if let httpBody = request.httpBody {
            return httpBody
        }
        guard let stream = request.httpBodyStream else {
            return nil
        }
        stream.open()
        defer { stream.close() }

        var data = Data()
        let bufferSize = 1024
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }

        while stream.hasBytesAvailable {
            let read = stream.read(buffer, maxLength: bufferSize)
            if read > 0 {
                data.append(buffer, count: read)
            } else {
                break
            }
        }
        return data.isEmpty ? nil : data
    }
}
