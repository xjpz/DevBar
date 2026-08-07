import Foundation

public extension Notification.Name {
    static let homeAssistantDiagnosticRecorded = Notification.Name(
        "cc.xjpz.DevBar.homeAssistantDiagnosticRecorded"
    )
}

/// Records privacy-safe Home Assistant failures in the shared diagnostic queue.
///
/// Request bodies and credentials are deliberately not accepted by this API. Response
/// bodies are reduced to their JSON shape, or to a short redacted preview when the
/// response is not JSON.
public final class HomeAssistantDiagnosticReporter: @unchecked Sendable {
    public static let shared = HomeAssistantDiagnosticReporter()

    private let diagnostics: any DiagnosticReporting
    private let deduplicationInterval: TimeInterval
    private let now: @Sendable () -> Date
    private let eventRecorded: @Sendable () -> Void
    private let lock = NSLock()
    private var lastRecordedAt: [String: Date] = [:]

    public init(
        diagnostics: any DiagnosticReporting = DiagnosticLogger.shared,
        deduplicationInterval: TimeInterval = 30,
        now: @escaping @Sendable () -> Date = { Date() },
        eventRecorded: @escaping @Sendable () -> Void = {
            NotificationCenter.default.post(name: .homeAssistantDiagnosticRecorded, object: nil)
        }
    ) {
        self.diagnostics = diagnostics
        self.deduplicationInterval = max(0, deduplicationInterval)
        self.now = now
        self.eventRecorded = eventRecorded
    }

    @discardableResult
    public func record(
        level: DiagnosticLogLevel = .warning,
        category: String,
        name: String,
        operation: String,
        endpoint: URL? = nil,
        httpStatus: Int? = nil,
        durationMs: Int64? = nil,
        error: Error? = nil,
        responseData: Data? = nil,
        contentType: String? = nil,
        details additionalDetails: [String: String] = [:]
    ) -> Bool {
        if let error, HomeAssistantErrorClassifier.isCancellation(error) { return false }

        let safeEndpoint = endpoint.flatMap(Self.sanitizedEndpoint)
        let errorType = error.map { String(reflecting: type(of: $0)) }
        let fingerprint = [
            category,
            name,
            operation,
            safeEndpoint ?? "-",
            httpStatus.map(String.init) ?? "-",
            errorType ?? "-",
        ].joined(separator: "|")
        let recordedAt = now()

        lock.lock()
        if let previous = lastRecordedAt[fingerprint] {
            let elapsed = recordedAt.timeIntervalSince(previous)
            if elapsed >= 0, elapsed < deduplicationInterval {
                lock.unlock()
                return false
            }
        }
        lastRecordedAt[fingerprint] = recordedAt
        if lastRecordedAt.count > 256 {
            let cutoff = recordedAt.addingTimeInterval(-max(deduplicationInterval * 2, 60))
            lastRecordedAt = lastRecordedAt.filter { $0.value >= cutoff }
        }
        lock.unlock()

        var details = additionalDetails
        details["operation"] = operation
        if let endpoint {
            details["endpointScheme"] = endpoint.scheme
            details["endpointHost"] = endpoint.host
            details["endpointPath"] = endpoint.path.isEmpty ? "/" : endpoint.path
        }
        if let contentType, !contentType.isEmpty { details["contentType"] = contentType }
        if let responseData {
            details["responseBytes"] = String(responseData.count)
            let payload = Self.payloadDetails(responseData)
            details.merge(payload) { _, new in new }
        }
        if let error {
            details.merge(Self.errorDetails(error)) { _, new in new }
        }

        diagnostics.record(DiagnosticLogEvent(
            occurredAt: recordedAt,
            level: level,
            category: category,
            name: name,
            message: "Home Assistant operation failed: \(operation)",
            platform: "unknown",
            endpoint: safeEndpoint,
            httpStatus: httpStatus,
            durationMs: durationMs,
            tags: ["home_assistant"],
            details: details
        ))
        eventRecorded()
        return true
    }

    public static func sanitizedEndpoint(_ url: URL) -> String? {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        components.user = nil
        components.password = nil
        components.query = nil
        components.fragment = nil
        return components.url?.absoluteString
    }

    public static func payloadDetails(_ data: Data) -> [String: String] {
        guard !data.isEmpty else { return ["payloadShape": "empty"] }
        if let json = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) {
            return ["payloadShape": jsonShape(json)]
        }
        let text = String(decoding: data.prefix(2_048), as: UTF8.self)
        return [
            "payloadShape": "non_json",
            "responsePreview": DiagnosticLogRedactor.redactedPreview(text, limit: 512),
        ]
    }

    public static func errorDetails(_ error: Error) -> [String: String] {
        var details = ["errorType": String(reflecting: type(of: error))]
        if let urlError = error as? URLError {
            details["urlErrorCode"] = String(urlError.code.rawValue)
        }
        if let decoding = decodingContext(error) {
            details.merge(decoding) { _, new in new }
        }
        return details
    }

    private static func decodingContext(_ error: Error) -> [String: String]? {
        guard let error = error as? DecodingError else { return nil }
        let context: DecodingError.Context
        let kind: String
        switch error {
        case .typeMismatch(_, let value):
            kind = "type_mismatch"
            context = value
        case .valueNotFound(_, let value):
            kind = "value_not_found"
            context = value
        case .keyNotFound(let key, let value):
            kind = "key_not_found:\(key.stringValue)"
            context = value
        case .dataCorrupted(let value):
            kind = "data_corrupted"
            context = value
        default:
            return nil
        }
        let path = context.codingPath.map(\.stringValue).joined(separator: ".")
        return [
            "decodingKind": kind,
            "codingPath": path.isEmpty ? "<root>" : path,
            "decodingDebug": DiagnosticLogRedactor.redactedPreview(context.debugDescription, limit: 512),
        ]
    }

    private static func jsonShape(_ value: Any, depth: Int = 0) -> String {
        guard depth < 2 else { return "nested" }
        if let object = value as? [String: Any] {
            let keys = object.keys.sorted()
            let shown = keys.prefix(24).joined(separator: ",")
            let suffix = keys.count > 24 ? ",..." : ""
            return "object(count=\(keys.count),keys=\(shown)\(suffix))"
        }
        if let array = value as? [Any] {
            guard let first = array.first else { return "array(count=0)" }
            return "array(count=\(array.count),first=\(jsonShape(first, depth: depth + 1)))"
        }
        if value is NSNull { return "null" }
        if value is String { return "string" }
        if value is NSNumber { return "number_or_boolean" }
        return "unknown"
    }
}

enum HomeAssistantWebSocketPayloadDecoder {
    static func decodeEnvelope(_ data: Data) throws -> [String: HomeAssistantJSONValue] {
        try JSONDecoder().decode([String: HomeAssistantJSONValue].self, from: data)
    }

    static func decodeState(_ value: HomeAssistantJSONValue) throws -> HomeAssistantState {
        let data = try JSONEncoder().encode(value)
        return try JSONDecoder().decode(HomeAssistantState.self, from: data)
    }
}
