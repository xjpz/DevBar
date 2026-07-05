import Foundation
import Testing
@testable import DevBarCore

@Test
func diagnosticRedactorReplacesSensitiveValues() {
    let redacted = DiagnosticLogRedactor.redact([
        "Authorization": "Bearer abc123",
        "apiKey": "secret-key",
        "cookie": "session=abc",
        "messageCount": "3",
        "nestedTokenHint": "hidden"
    ])

    #expect(redacted["Authorization"] == "<redacted:length=13>")
    #expect(redacted["apiKey"] == "<redacted:length=10>")
    #expect(redacted["cookie"] == "<redacted:length=11>")
    #expect(redacted["nestedTokenHint"] == "<redacted:length=6>")
    #expect(redacted["messageCount"] == "3")
}

@Test
func diagnosticLogEventEncodesStableFields() throws {
    let event = DiagnosticLogEvent(
        eventId: "event-1",
        occurredAt: Date(timeIntervalSince1970: 1_786_000_000),
        level: .error,
        category: "hermes.api",
        name: "chat_completions_failed",
        message: "Hermes HTTP 503",
        platform: "ios",
        deviceId: "iphone-unit",
        deviceName: "Unit iPhone",
        appVersion: "1.2.3",
        buildNumber: "456",
        osName: "iOS",
        osVersion: "26.0",
        traceId: "trace-1",
        requestId: "request-1",
        sessionId: "session-1",
        conversationId: "conversation-1",
        endpoint: "chat/completions",
        httpStatus: 503,
        durationMs: 1200,
        retryCount: 1,
        tags: ["hermes", "network"],
        details: ["apiKey": "secret-key", "model": "hermes-agent"]
    )

    let data = try JSONEncoder().encode(event)
    let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    let details = try #require(object["details"] as? [String: String])

    #expect(object["eventId"] as? String == "event-1")
    #expect(object["occurredAt"] as? Int64 == 1_786_000_000_000)
    #expect(object["level"] as? String == "error")
    #expect(object["httpStatus"] as? Int == 503)
    #expect(details["apiKey"] == "<redacted:length=10>")
    #expect(details["model"] == "hermes-agent")
}

@Test
func diagnosticLogStoreAppendsLoadsAndRemovesEvents() throws {
    let directory = try temporaryDirectory()
    let store = DiagnosticLogStore(directoryURL: directory, maxFileSizeBytes: 10_000)
    let first = DiagnosticLogEvent(
        eventId: "event-1",
        occurredAt: Date(timeIntervalSince1970: 1),
        level: .warning,
        category: "app.lifecycle",
        name: "unclean_exit",
        message: "Previous run did not shut down cleanly",
        platform: "macos"
    )
    let second = DiagnosticLogEvent(
        eventId: "event-2",
        occurredAt: Date(timeIntervalSince1970: 2),
        level: .error,
        category: "hermes.api",
        name: "request_failed",
        message: "HTTP 500",
        platform: "ios"
    )

    try store.append(first)
    try store.append(second)

    #expect(try store.loadBatch(limit: 10, maxBytes: 100_000).map(\.eventId) == ["event-1", "event-2"])

    try store.remove(eventIDs: ["event-1"])

    #expect(try store.loadBatch(limit: 10, maxBytes: 100_000).map(\.eventId) == ["event-2"])
}

@Test
func diagnosticLogStoreEnforcesFileCountLimit() throws {
    let directory = try temporaryDirectory()
    let store = DiagnosticLogStore(
        directoryURL: directory,
        maxFileSizeBytes: 250,
        maxTotalBytes: 100_000,
        maxFileCount: 1
    )

    for index in 0..<8 {
        try store.append(DiagnosticLogEvent(
            eventId: "event-\(index)",
            occurredAt: Date(timeIntervalSince1970: TimeInterval(index)),
            level: .error,
            category: "hermes.api",
            name: "request_failed",
            message: String(repeating: "x", count: 80),
            platform: "ios"
        ))
    }

    let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        .filter { $0.pathExtension == "jsonl" }

    #expect(files.count == 1)
    #expect(try store.loadBatch(limit: 20, maxBytes: 100_000).isEmpty == false)
}

private func temporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appending(path: "devbar-diagnostic-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}
