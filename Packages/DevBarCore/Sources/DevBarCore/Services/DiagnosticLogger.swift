import Foundation

public protocol DiagnosticReporting: Sendable {
    func record(_ event: DiagnosticLogEvent)
}

public final class DiagnosticLogger: DiagnosticReporting, @unchecked Sendable {
    public static let shared = DiagnosticLogger()

    private let lock = NSLock()
    private var store: DiagnosticLogStore
    private var platform = "unknown"
    private var deviceId: String?
    private var deviceName: String?
    private var appVersion: String?
    private var buildNumber: String?
    private var osName: String?
    private var osVersion: String?

    public init(store: DiagnosticLogStore = DiagnosticLogStore(directoryURL: DiagnosticLogStore.defaultDirectoryURL())) {
        self.store = store
    }

    public func configure(
        store: DiagnosticLogStore? = nil,
        platform: String,
        deviceId: String? = nil,
        deviceName: String? = nil,
        appVersion: String? = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
        buildNumber: String? = Bundle.main.infoDictionary?["CFBundleVersion"] as? String,
        osName: String? = nil,
        osVersion: String? = ProcessInfo.processInfo.operatingSystemVersionString
    ) {
        lock.lock()
        defer { lock.unlock() }
        if let store {
            self.store = store
        }
        self.platform = platform
        self.deviceId = deviceId
        self.deviceName = deviceName
        self.appVersion = appVersion
        self.buildNumber = buildNumber
        self.osName = osName
        self.osVersion = osVersion
    }

    public func record(_ event: DiagnosticLogEvent) {
        lock.lock()
        let enriched = enrich(event)
        let currentStore = store
        lock.unlock()
        try? currentStore.append(enriched)
    }

    public func record(
        level: DiagnosticLogLevel,
        category: String,
        name: String,
        message: String,
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
        record(DiagnosticLogEvent(
            level: level,
            category: category,
            name: name,
            message: message,
            platform: platform,
            traceId: traceId,
            requestId: requestId,
            sessionId: sessionId,
            conversationId: conversationId,
            endpoint: endpoint,
            httpStatus: httpStatus,
            durationMs: durationMs,
            retryCount: retryCount,
            tags: tags,
            details: details
        ))
    }

    private func enrich(_ event: DiagnosticLogEvent) -> DiagnosticLogEvent {
        DiagnosticLogEvent(
            eventId: event.eventId,
            occurredAt: event.occurredAt,
            level: event.level,
            category: event.category,
            name: event.name,
            message: event.message,
            platform: event.platform == "unknown" ? platform : event.platform,
            deviceId: event.deviceId ?? deviceId,
            deviceName: event.deviceName ?? deviceName,
            appVersion: event.appVersion ?? appVersion,
            buildNumber: event.buildNumber ?? buildNumber,
            osName: event.osName ?? osName,
            osVersion: event.osVersion ?? osVersion,
            traceId: event.traceId,
            requestId: event.requestId,
            sessionId: event.sessionId,
            conversationId: event.conversationId,
            endpoint: event.endpoint,
            httpStatus: event.httpStatus,
            durationMs: event.durationMs,
            retryCount: event.retryCount,
            tags: event.tags,
            details: event.details
        )
    }
}
