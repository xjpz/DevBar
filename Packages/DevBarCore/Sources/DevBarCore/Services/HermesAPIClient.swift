import Foundation

public final class HermesAPIClient: Sendable {
    public static let defaultRequestTimeout: TimeInterval = 180
    public static let defaultResourceTimeout: TimeInterval = 300

    private let session: URLSession
    private let decoder = JSONDecoder()

    public init(session: URLSession = HermesAPIClient.defaultSession()) {
        self.session = session
    }

    public static func defaultSession() -> URLSession {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = defaultRequestTimeout
        configuration.timeoutIntervalForResource = defaultResourceTimeout
        configuration.waitsForConnectivity = true
        return URLSession(configuration: configuration)
    }

    public func sendMessage(
        baseURL: String,
        apiKey: String,
        messages: [HermesChatRequestMessage],
        model: String? = nil,
        stream: Bool = false
    ) async throws -> String {
        var request = try makeRequest(
            baseURL: baseURL,
            apiKey: apiKey,
            messages: messages,
            model: model,
            stream: stream
        )
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        try Self.validate(response: response, data: data)
        let decoded = try decoder.decode(HermesChatResponse.self, from: data)
        guard !decoded.assistantContent.isEmpty else {
            throw APIError.invalidResponse
        }
        return decoded.assistantContent
    }

    public func streamMessage(
        baseURL: String,
        apiKey: String,
        messages: [HermesChatRequestMessage],
        model: String? = nil
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var request = try makeRequest(
                        baseURL: baseURL,
                        apiKey: apiKey,
                        messages: messages,
                        model: model,
                        stream: true
                    )
                    request.setValue("text/event-stream", forHTTPHeaderField: "Accept")

                    let (bytes, response) = try await session.bytes(for: request)
                    try Self.validate(response: response, data: nil)

                    for try await line in bytes.lines {
                        guard !Task.isCancelled else { break }
                        for delta in Self.parseStreamDeltas(fromLine: line) {
                            continuation.yield(delta)
                        }
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    public func fetchModels(baseURL: String, apiKey: String) async throws -> [HermesModel] {
        let request = try makeGETRequest(url: Self.modelsURL(from: baseURL), apiKey: apiKey)
        let (data, response) = try await session.data(for: request)
        try Self.validate(response: response, data: data)
        return try decoder.decode(HermesModelsResponse.self, from: data).data
    }

    public func fetchCapabilities(baseURL: String, apiKey: String) async throws -> HermesAPIServerCapabilities {
        let request = try makeGETRequest(url: Self.capabilitiesURL(from: baseURL), apiKey: apiKey)
        let (data, response) = try await session.data(for: request)
        try Self.validate(response: response, data: data)
        return try decoder.decode(HermesAPIServerCapabilities.self, from: data)
    }

    public func sendResponse(
        baseURL: String,
        apiKey: String,
        input: String,
        model: String? = nil,
        conversation: String
    ) async throws -> String {
        guard let url = Self.responsesURL(from: baseURL) else {
            throw APIError.invalidResponse
        }

        let authorization = BigModelAPIClient.normalizedBearerToken(apiKey)
        guard !authorization.isEmpty else {
            throw APIError.unauthorized
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = Self.defaultRequestTimeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(authorization, forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(HermesResponsesRequest(
            model: model,
            input: input,
            conversation: conversation,
            store: true
        ))

        let (data, response) = try await session.data(for: request)
        try Self.validate(response: response, data: data)
        let decoded = try decoder.decode(HermesResponsesResponse.self, from: data)
        guard !decoded.assistantContent.isEmpty else {
            throw APIError.invalidResponse
        }
        return decoded.assistantContent
    }

    public static func chatURL(from baseURL: String) -> URL? {
        endpointURL(from: baseURL, appending: "chat/completions")
    }

    public static func modelsURL(from baseURL: String) -> URL? {
        endpointURL(from: baseURL, appending: "models")
    }

    public static func capabilitiesURL(from baseURL: String) -> URL? {
        endpointURL(from: baseURL, appending: "capabilities")
    }

    public static func responsesURL(from baseURL: String) -> URL? {
        endpointURL(from: baseURL, appending: "responses")
    }

    private static func endpointURL(from baseURL: String, appending endpoint: String) -> URL? {
        let trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              var components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              components.host?.isEmpty == false else {
            return nil
        }

        var path = components.path
        while path.hasSuffix("/") {
            path.removeLast()
        }
        for knownEndpoint in ["chat/completions", "responses", "models", "capabilities"] {
            let suffix = "/\(knownEndpoint)"
            if path.hasSuffix(suffix) {
                path.removeLast(suffix.count)
                break
            }
        }
        if !path.hasSuffix("/\(endpoint)") {
            path += "/\(endpoint)"
        }
        components.path = path
        return components.url
    }

    public static func parseStreamDeltas(from text: String) -> [String] {
        text
            .split(whereSeparator: \.isNewline)
            .flatMap { parseStreamDeltas(fromLine: String($0)) }
    }

    public static func parseStreamDeltas(fromLine line: String) -> [String] {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let payload: String
        if trimmed.hasPrefix("data:") {
            payload = String(trimmed.dropFirst(5)).trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            payload = trimmed
        }

        guard payload != "[DONE]",
              let data = payload.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(HermesStreamResponse.self, from: data),
              let delta = decoded.deltaContent,
              !delta.isEmpty else {
            return []
        }
        return [delta]
    }

    private func makeRequest(
        baseURL: String,
        apiKey: String,
        messages: [HermesChatRequestMessage],
        model: String?,
        stream: Bool
    ) throws -> URLRequest {
        guard let url = Self.chatURL(from: baseURL) else {
            throw APIError.invalidResponse
        }

        let authorization = BigModelAPIClient.normalizedBearerToken(apiKey)
        guard !authorization.isEmpty else {
            throw APIError.unauthorized
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = Self.defaultRequestTimeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(authorization, forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(HermesChatRequest(
            messages: messages,
            model: model,
            stream: stream
        ))
        return request
    }

    private func makeGETRequest(url: URL?, apiKey: String) throws -> URLRequest {
        guard let url else {
            throw APIError.invalidResponse
        }

        let authorization = BigModelAPIClient.normalizedBearerToken(apiKey)
        guard !authorization.isEmpty else {
            throw APIError.unauthorized
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = Self.defaultRequestTimeout
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(authorization, forHTTPHeaderField: "Authorization")
        return request
    }

    private static func validate(response: URLResponse, data: Data?) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200..<300:
            return
        case 401, 403:
            throw APIError.unauthorized
        default:
            if let data, let raw = String(data: data, encoding: .utf8), !raw.isEmpty {
                print("[DevBar] Hermes HTTP \(httpResponse.statusCode): \(raw.prefix(300))")
            }
            throw APIError.httpError(httpResponse.statusCode)
        }
    }
}
