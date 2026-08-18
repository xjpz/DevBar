import Crypto
import Foundation

public struct HomeAssistantSnapshotCacheStore: @unchecked Sendable {
    public enum CacheError: Error, Equatable {
        case snapshotTooLarge
    }

    private let fileManager: FileManager
    private let directoryURL: URL
    private let maximumBytes: Int

    public init(
        directoryURL: URL? = nil,
        fileManager: FileManager = .default,
        maximumBytes: Int = DevBarCoreConstants.HomeAssistant.snapshotCacheMaximumBytes
    ) {
        self.fileManager = fileManager
        self.directoryURL = directoryURL
            ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent(DevBarCoreConstants.HomeAssistant.snapshotCacheDirectoryName, isDirectory: true)
        self.maximumBytes = maximumBytes
    }

    /// 优先用 externalURL 推导指纹（对已有用户保持原键不变），推导不出时回落到 internalURL。
    /// 只配了内网地址（或 externalURL 无法解析出 host）时也能得到稳定指纹，
    /// 避免显隐/布局设置因指纹为 nil 而静默不落盘或被清空。
    public static func instanceFingerprint(externalURL: String, internalURL: String) -> String? {
        instanceFingerprint(externalURL: externalURL)
            ?? instanceFingerprint(externalURL: internalURL)
    }

    public static func instanceFingerprint(externalURL: String) -> String? {
        let value = externalURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: value),
              let scheme = components.scheme?.lowercased(),
              let host = components.host?.lowercased(),
              !host.isEmpty else { return nil }
        components.scheme = scheme
        components.host = host
        components.path = ""
        components.query = nil
        components.fragment = nil
        guard let normalized = components.string else { return nil }
        return SHA256.hash(data: Data(normalized.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    public func load(instanceFingerprint: String) -> HomeAssistantSnapshotCacheEnvelope? {
        let url = fileURL(for: instanceFingerprint)
        guard let data = try? Data(contentsOf: url),
              let envelope = try? JSONDecoder().decode(HomeAssistantSnapshotCacheEnvelope.self, from: data),
              envelope.schemaVersion == DevBarCoreConstants.HomeAssistant.snapshotCacheSchemaVersion,
              envelope.instanceFingerprint == instanceFingerprint,
              HomeAssistantSnapshotProjection.isValidCacheSnapshot(envelope.snapshot) else {
            try? fileManager.removeItem(at: url)
            return nil
        }
        return envelope
    }

    public func save(snapshot: HomeAssistantSnapshot, instanceFingerprint: String) throws {
        let projected = HomeAssistantSnapshotProjection.cacheSnapshot(from: snapshot)
        let envelope = HomeAssistantSnapshotCacheEnvelope(
            schemaVersion: DevBarCoreConstants.HomeAssistant.snapshotCacheSchemaVersion,
            instanceFingerprint: instanceFingerprint,
            savedAt: .now,
            snapshot: projected
        )
        let data = try JSONEncoder().encode(envelope)
        guard data.count <= maximumBytes else { throw CacheError.snapshotTooLarge }
        try prepareDirectory()
        let url = fileURL(for: instanceFingerprint)
        try data.write(to: url, options: .atomic)
        excludeFromBackup(url)
#if os(iOS)
        try? fileManager.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: url.path
        )
#endif
    }

    public func savedAt(instanceFingerprint: String) -> Date? {
        load(instanceFingerprint: instanceFingerprint)?.savedAt
    }

    public func clear(instanceFingerprint: String) {
        try? fileManager.removeItem(at: fileURL(for: instanceFingerprint))
    }

    private func prepareDirectory() throws {
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        excludeFromBackup(directoryURL)
    }

    private func fileURL(for instanceFingerprint: String) -> URL {
        directoryURL.appendingPathComponent("snapshot-\(instanceFingerprint).json", isDirectory: false)
    }

    private func excludeFromBackup(_ url: URL) {
        var resourceURL = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? resourceURL.setResourceValues(values)
    }
}
