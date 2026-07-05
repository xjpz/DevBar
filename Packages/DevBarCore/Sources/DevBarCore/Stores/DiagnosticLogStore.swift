import Foundation

public final class DiagnosticLogStore: @unchecked Sendable {
    private let directoryURL: URL
    private let fileManager: FileManager
    private let maxFileSizeBytes: Int
    private let maxTotalBytes: Int
    private let maxFileCount: Int
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(
        directoryURL: URL,
        fileManager: FileManager = .default,
        maxFileSizeBytes: Int = 512 * 1_024,
        maxTotalBytes: Int = 10 * 1_024 * 1_024,
        maxFileCount: Int = 20
    ) {
        self.directoryURL = directoryURL
        self.fileManager = fileManager
        self.maxFileSizeBytes = maxFileSizeBytes
        self.maxTotalBytes = maxTotalBytes
        self.maxFileCount = maxFileCount
    }

    public static func defaultDirectoryURL() -> URL {
        if let appGroupURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: DevBarCoreConstants.AppGroup.groupID
        ) {
            return appGroupURL
                .appending(path: "Library/Application Support", directoryHint: .isDirectory)
                .appending(path: "Diagnostics", directoryHint: .isDirectory)
        }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "DevBar/Diagnostics", directoryHint: .isDirectory)
    }

    public func append(_ event: DiagnosticLogEvent) throws {
        try ensureDirectory()
        let data = try encoder.encode(event)
        let line = data + Data([0x0a])
        let fileURL = try activeFileURL(additionalBytes: line.count)
        if fileManager.fileExists(atPath: fileURL.path) {
            let handle = try FileHandle(forWritingTo: fileURL)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: line)
        } else {
            try line.write(to: fileURL, options: .atomic)
        }
        try enforceLimits()
    }

    public func loadBatch(limit: Int, maxBytes: Int) throws -> [DiagnosticLogEvent] {
        guard limit > 0, maxBytes > 0 else { return [] }
        var events: [DiagnosticLogEvent] = []
        var bytes = 0
        for fileURL in try sortedLogFiles() {
            let data = try Data(contentsOf: fileURL)
            for line in data.split(separator: 0x0a) {
                guard events.count < limit else { return events }
                let lineBytes = line.count + 1
                guard bytes + lineBytes <= maxBytes || events.isEmpty else { return events }
                if let event = try? decoder.decode(DiagnosticLogEvent.self, from: Data(line)) {
                    events.append(event)
                    bytes += lineBytes
                }
            }
        }
        return events
    }

    public func remove(eventIDs: Set<String>) throws {
        guard !eventIDs.isEmpty else { return }
        for fileURL in try sortedLogFiles() {
            let data = try Data(contentsOf: fileURL)
            var keptLines: [Data] = []
            for line in data.split(separator: 0x0a) {
                let lineData = Data(line)
                if let event = try? decoder.decode(DiagnosticLogEvent.self, from: lineData),
                   eventIDs.contains(event.eventId) {
                    continue
                }
                keptLines.append(lineData)
            }
            if keptLines.isEmpty {
                try? fileManager.removeItem(at: fileURL)
            } else {
                let output = keptLines.reduce(into: Data()) { partial, line in
                    partial.append(line)
                    partial.append(0x0a)
                }
                try output.write(to: fileURL, options: .atomic)
            }
        }
    }

    public func enforceLimits() throws {
        var files = try sortedLogFiles()
        while files.count > maxFileCount {
            try? fileManager.removeItem(at: files.removeFirst())
        }
        var totalSize = 0
        for fileURL in files {
            totalSize += try fileSize(fileURL)
        }
        while totalSize > maxTotalBytes, let first = files.first {
            let size = try fileSize(first)
            try? fileManager.removeItem(at: first)
            files.removeFirst()
            totalSize -= size
        }
    }

    private func ensureDirectory() throws {
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        var mutableURL = directoryURL
        try? mutableURL.setResourceValues(resourceValues)
    }

    private func activeFileURL(additionalBytes: Int) throws -> URL {
        let files = try sortedLogFiles()
        if let last = files.last,
           (try fileSize(last)) + additionalBytes <= maxFileSizeBytes {
            return last
        }
        let timestamp = Int64(Date().timeIntervalSince1970 * 1_000)
        return directoryURL.appending(path: "diagnostic-\(timestamp)-\(UUID().uuidString).jsonl")
    }

    private func sortedLogFiles() throws -> [URL] {
        guard fileManager.fileExists(atPath: directoryURL.path) else { return [] }
        return try fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.creationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        )
        .filter { $0.pathExtension == "jsonl" }
        .sorted { left, right in
            left.lastPathComponent < right.lastPathComponent
        }
    }

    private func fileSize(_ url: URL) throws -> Int {
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        return values.fileSize ?? 0
    }
}
