import Foundation

public final class HomeAssistantRESTClient: Sendable {
    private let session: URLSession
    private let decoder = JSONDecoder()
    private let diagnostics: HomeAssistantDiagnosticReporter

    public init(
        session: URLSession = .shared,
        diagnostics: HomeAssistantDiagnosticReporter = .shared
    ) {
        self.session = session
        self.diagnostics = diagnostics
    }

    public func checkConnection(baseURL: URL, token: String) async throws {
        let request = try request(baseURL: baseURL, path: "/api/", token: token)
        _ = try await execute(request, operation: "check_connection")
    }

    public func fetchConfig(baseURL: URL, token: String) async throws -> HomeAssistantConfig {
        try await get(baseURL: baseURL, path: "/api/config", token: token, operation: "fetch_config")
    }

    public func fetchStates(baseURL: URL, token: String) async throws -> [HomeAssistantState] {
        try await get(baseURL: baseURL, path: "/api/states", token: token, operation: "fetch_states")
    }

    public func fetchServices(baseURL: URL, token: String) async throws -> [HomeAssistantService] {
        try await get(baseURL: baseURL, path: "/api/services", token: token, operation: "fetch_services")
    }

    @discardableResult
    public func callService(
        baseURL: URL,
        token: String,
        call: HomeAssistantServiceCall
    ) async throws -> [HomeAssistantState] {
        let path = "/api/services/\(call.domain)/\(call.service)"
        var request = try request(baseURL: baseURL, path: path, token: token)
        request.httpMethod = "POST"
        request.httpBody = try JSONEncoder().encode(ServiceBody(
            entityID: call.targetEntityID,
            data: call.data
        ))
        let operation = "call_service:\(call.domain).\(call.service)"
        let (data, response, durationMs) = try await execute(request, operation: operation)
        guard !data.isEmpty else { return [] }
        do {
            return try decoder.decode([HomeAssistantState].self, from: data)
        } catch {
            diagnostics.record(
                category: "home_assistant.rest",
                name: "response_decode_failed",
                operation: operation,
                endpoint: request.url,
                httpStatus: response.statusCode,
                durationMs: durationMs,
                error: error,
                responseData: data,
                contentType: response.value(forHTTPHeaderField: "Content-Type")
            )
            // Some Home Assistant service calls intentionally return no state list.
            return []
        }
    }

    private func get<Response: Decodable>(
        baseURL: URL,
        path: String,
        token: String,
        operation: String
    ) async throws -> Response {
        let request = try request(baseURL: baseURL, path: path, token: token)
        let (data, response, durationMs) = try await execute(request, operation: operation)
        do {
            return try decoder.decode(Response.self, from: data)
        } catch {
            diagnostics.record(
                category: "home_assistant.rest",
                name: "response_decode_failed",
                operation: operation,
                endpoint: request.url,
                httpStatus: response.statusCode,
                durationMs: durationMs,
                error: error,
                responseData: data,
                contentType: response.value(forHTTPHeaderField: "Content-Type")
            )
            throw HomeAssistantError.invalidResponse
        }
    }

    private func execute(
        _ request: URLRequest,
        operation: String
    ) async throws -> (Data, HTTPURLResponse, Int64) {
        let startedAt = Date()
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            diagnostics.record(
                category: "home_assistant.rest",
                name: "request_transport_failed",
                operation: operation,
                endpoint: request.url,
                durationMs: elapsedMilliseconds(since: startedAt),
                error: error
            )
            throw error
        }

        let durationMs = elapsedMilliseconds(since: startedAt)
        guard let httpResponse = response as? HTTPURLResponse else {
            diagnostics.record(
                category: "home_assistant.rest",
                name: "http_response_failed",
                operation: operation,
                endpoint: request.url,
                durationMs: durationMs,
                responseData: data
            )
            throw HomeAssistantError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            diagnostics.record(
                category: "home_assistant.rest",
                name: "http_response_failed",
                operation: operation,
                endpoint: request.url,
                httpStatus: httpResponse.statusCode,
                durationMs: durationMs,
                responseData: data,
                contentType: httpResponse.value(forHTTPHeaderField: "Content-Type")
            )
            if httpResponse.statusCode == 401 { throw HomeAssistantError.unauthorized }
            throw HomeAssistantError.invalidResponse
        }
        return (data, httpResponse, durationMs)
    }

    private func elapsedMilliseconds(since startedAt: Date) -> Int64 {
        Int64(max(0, Date().timeIntervalSince(startedAt) * 1_000).rounded())
    }

    private func request(baseURL: URL, path: String, token: String) throws -> URLRequest {
        let trimmedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedToken.isEmpty else { throw HomeAssistantError.emptyToken }
        guard let url = URL(string: path, relativeTo: baseURL)?.absoluteURL else {
            throw HomeAssistantError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        request.setValue("Bearer \(trimmedToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return request
    }

}

private struct ServiceBody: Encodable {
    let entityID: String
    let data: [String: HomeAssistantJSONValue]

    enum CodingKeys: String, CodingKey {
        case entityID = "entity_id"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: DynamicCodingKey.self)
        try container.encode(entityID, forKey: DynamicCodingKey("entity_id"))
        for (key, value) in data {
            try container.encode(value, forKey: DynamicCodingKey(key))
        }
    }
}

private struct DynamicCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int? = nil
    init(_ stringValue: String) { self.stringValue = stringValue }
    init?(stringValue: String) { self.init(stringValue) }
    init?(intValue: Int) { return nil }
}
