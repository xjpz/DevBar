import Foundation

public enum DiagnosticLogLevel: String, Codable, Sendable, CaseIterable {
    case debug
    case info
    case warning
    case error
    case fatal
}

public struct DiagnosticLogEvent: Codable, Equatable, Identifiable, Sendable {
    public var id: String { eventId }

    public var eventId: String
    public var occurredAt: Date
    public var level: DiagnosticLogLevel
    public var category: String
    public var name: String
    public var message: String
    public var platform: String
    public var deviceId: String?
    public var deviceName: String?
    public var appVersion: String?
    public var buildNumber: String?
    public var osName: String?
    public var osVersion: String?
    public var traceId: String?
    public var requestId: String?
    public var sessionId: String?
    public var conversationId: String?
    public var endpoint: String?
    public var httpStatus: Int?
    public var durationMs: Int64?
    public var retryCount: Int
    public var tags: [String]
    public var details: [String: String]

    public init(
        eventId: String = UUID().uuidString,
        occurredAt: Date = Date(),
        level: DiagnosticLogLevel,
        category: String,
        name: String,
        message: String,
        platform: String,
        deviceId: String? = nil,
        deviceName: String? = nil,
        appVersion: String? = nil,
        buildNumber: String? = nil,
        osName: String? = nil,
        osVersion: String? = nil,
        traceId: String? = nil,
        requestId: String? = nil,
        sessionId: String? = nil,
        conversationId: String? = nil,
        endpoint: String? = nil,
        httpStatus: Int? = nil,
        durationMs: Int64? = nil,
        retryCount: Int = 0,
        tags: [String] = [],
        details: [String: String] = [:]
    ) {
        self.eventId = eventId
        self.occurredAt = occurredAt
        self.level = level
        self.category = category
        self.name = name
        self.message = message
        self.platform = platform
        self.deviceId = deviceId
        self.deviceName = deviceName
        self.appVersion = appVersion
        self.buildNumber = buildNumber
        self.osName = osName
        self.osVersion = osVersion
        self.traceId = traceId
        self.requestId = requestId
        self.sessionId = sessionId
        self.conversationId = conversationId
        self.endpoint = endpoint
        self.httpStatus = httpStatus
        self.durationMs = durationMs
        self.retryCount = retryCount
        self.tags = tags
        self.details = DiagnosticLogRedactor.redact(details)
    }

    private enum CodingKeys: String, CodingKey {
        case eventId
        case occurredAt
        case level
        case category
        case name
        case message
        case platform
        case deviceId
        case deviceName
        case appVersion
        case buildNumber
        case osName
        case osVersion
        case traceId
        case requestId
        case sessionId
        case conversationId
        case endpoint
        case httpStatus
        case durationMs
        case retryCount
        case tags
        case details
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        eventId = try container.decode(String.self, forKey: .eventId)
        let occurredAtMillis = try container.decode(Int64.self, forKey: .occurredAt)
        occurredAt = Date(timeIntervalSince1970: TimeInterval(occurredAtMillis) / 1_000)
        level = try container.decode(DiagnosticLogLevel.self, forKey: .level)
        category = try container.decode(String.self, forKey: .category)
        name = try container.decode(String.self, forKey: .name)
        message = try container.decode(String.self, forKey: .message)
        platform = try container.decode(String.self, forKey: .platform)
        deviceId = try container.decodeIfPresent(String.self, forKey: .deviceId)
        deviceName = try container.decodeIfPresent(String.self, forKey: .deviceName)
        appVersion = try container.decodeIfPresent(String.self, forKey: .appVersion)
        buildNumber = try container.decodeIfPresent(String.self, forKey: .buildNumber)
        osName = try container.decodeIfPresent(String.self, forKey: .osName)
        osVersion = try container.decodeIfPresent(String.self, forKey: .osVersion)
        traceId = try container.decodeIfPresent(String.self, forKey: .traceId)
        requestId = try container.decodeIfPresent(String.self, forKey: .requestId)
        sessionId = try container.decodeIfPresent(String.self, forKey: .sessionId)
        conversationId = try container.decodeIfPresent(String.self, forKey: .conversationId)
        endpoint = try container.decodeIfPresent(String.self, forKey: .endpoint)
        httpStatus = try container.decodeIfPresent(Int.self, forKey: .httpStatus)
        durationMs = try container.decodeIfPresent(Int64.self, forKey: .durationMs)
        retryCount = try container.decodeIfPresent(Int.self, forKey: .retryCount) ?? 0
        tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
        details = DiagnosticLogRedactor.redact(try container.decodeIfPresent([String: String].self, forKey: .details) ?? [:])
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(eventId, forKey: .eventId)
        try container.encode(Int64((occurredAt.timeIntervalSince1970 * 1_000).rounded()), forKey: .occurredAt)
        try container.encode(level, forKey: .level)
        try container.encode(category, forKey: .category)
        try container.encode(name, forKey: .name)
        try container.encode(message, forKey: .message)
        try container.encode(platform, forKey: .platform)
        try container.encodeIfPresent(deviceId, forKey: .deviceId)
        try container.encodeIfPresent(deviceName, forKey: .deviceName)
        try container.encodeIfPresent(appVersion, forKey: .appVersion)
        try container.encodeIfPresent(buildNumber, forKey: .buildNumber)
        try container.encodeIfPresent(osName, forKey: .osName)
        try container.encodeIfPresent(osVersion, forKey: .osVersion)
        try container.encodeIfPresent(traceId, forKey: .traceId)
        try container.encodeIfPresent(requestId, forKey: .requestId)
        try container.encodeIfPresent(sessionId, forKey: .sessionId)
        try container.encodeIfPresent(conversationId, forKey: .conversationId)
        try container.encodeIfPresent(endpoint, forKey: .endpoint)
        try container.encodeIfPresent(httpStatus, forKey: .httpStatus)
        try container.encodeIfPresent(durationMs, forKey: .durationMs)
        try container.encode(retryCount, forKey: .retryCount)
        try container.encode(tags, forKey: .tags)
        try container.encode(DiagnosticLogRedactor.redact(details), forKey: .details)
    }
}

public enum DiagnosticLogRedactor {
    private static let sensitiveFragments = [
        "token",
        "authorization",
        "apikey",
        "api_key",
        "cookie",
        "secret",
        "ticket",
    ]

    public static func redact(_ values: [String: String]) -> [String: String] {
        values.reduce(into: [:]) { result, pair in
            if isSensitiveKey(pair.key) {
                if pair.value.hasPrefix("<redacted:length=") {
                    result[pair.key] = pair.value
                } else {
                    result[pair.key] = "<redacted:length=\(pair.value.count)>"
                }
            } else {
                result[pair.key] = pair.value
            }
        }
    }

    public static func redactedPreview(_ value: String, limit: Int = 1_000) -> String {
        let compact = value.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmed = compact.count > limit ? String(compact.prefix(limit)) + "...<truncated>" : compact
        return isSensitiveInline(trimmed) ? "<redacted:length=\(trimmed.count)>" : trimmed
    }

    private static func isSensitiveKey(_ key: String) -> Bool {
        let normalized = key.replacingOccurrences(of: "-", with: "_").lowercased()
        return sensitiveFragments.contains { normalized.contains($0) }
    }

    private static func isSensitiveInline(_ value: String) -> Bool {
        let lowercased = value.lowercased()
        return lowercased.contains("authorization:") ||
            lowercased.contains("bearer ") ||
            lowercased.contains("api_key") ||
            lowercased.contains("apikey")
    }
}
