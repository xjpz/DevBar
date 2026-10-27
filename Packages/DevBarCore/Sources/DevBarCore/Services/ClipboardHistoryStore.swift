import CryptoKit
import Foundation
import Security

public protocol ClipboardKeyStoring: Sendable {
    func load(_ account: String) throws -> Data?
    func save(_ data: Data, account: String) throws
    func remove(_ account: String) throws
}

public struct ClipboardKeychain: ClipboardKeyStoring {
    public init() {}
    private func query(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "cc.xjpz.DevBar.clipboard",
         kSecAttrAccount as String: account,
         kSecAttrSynchronizable as String: false]
    }

    public func load(_ account: String) throws -> Data? {
        var query = query(account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data, data.count == 32 else {
            throw ClipboardFailure.storage
        }
        return data
    }

    public func save(_ data: Data, account: String) throws {
        var query = query(account)
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        // Never delete or replace an existing key on a read/access failure.
        guard SecItemAdd(query as CFDictionary, nil) == errSecSuccess else { throw ClipboardFailure.storage }
    }

    public func remove(_ account: String) throws {
        let status = SecItemDelete(query(account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw ClipboardFailure.storage }
    }
}

public enum ClipboardRandom {
    public static func bytes(count: Int = 32) throws -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        guard SecRandomCopyBytes(kSecRandomDefault, count, &bytes) == errSecSuccess else {
            throw ClipboardFailure.storage
        }
        return Data(bytes)
    }
}

/// Only ciphertext is persisted. All calls belong to a store actor, never a view's body.
public struct ClipboardEncryptedFile: Sendable {
    public let url: URL
    private let account: String
    private let keys: any ClipboardKeyStoring

    public init(url: URL, account: String, keys: any ClipboardKeyStoring = ClipboardKeychain()) {
        self.url = url; self.account = account; self.keys = keys
    }

    public static func applicationFile(_ name: String) -> ClipboardEncryptedFile {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DevBarClipboard", isDirectory: true)
        return ClipboardEncryptedFile(url: directory.appendingPathComponent("\(name).sealed"), account: name)
    }

    public func read<Value: Decodable>(_ type: Value.Type) throws -> Value? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        guard let key = try keys.load(account) else { throw ClipboardFailure.storage }
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard let size = attributes[.size] as? NSNumber, size.intValue <= 32 * 1024 * 1024 else {
            throw ClipboardFailure.storage
        }
        let encrypted = try Data(contentsOf: url)
        let box = try AES.GCM.SealedBox(combined: encrypted)
        let data = try AES.GCM.open(box, using: SymmetricKey(data: key),
                                    authenticating: Data("DevBar.clipboard.file.v1.\(account)".utf8))
        return try JSONDecoder().decode(type, from: data)
    }

    public func write<Value: Encodable>(_ value: Value) throws {
        let key: Data
        if let saved = try keys.load(account) { key = saved }
        else {
            guard !FileManager.default.fileExists(atPath: url.path) else { throw ClipboardFailure.storage }
            key = try ClipboardRandom.bytes()
            try keys.save(key, account: account)
        }
        let box = try AES.GCM.seal(JSONEncoder().encode(value), using: SymmetricKey(data: key),
                                    authenticating: Data("DevBar.clipboard.file.v1.\(account)".utf8))
        guard let encrypted = box.combined else { throw ClipboardFailure.storage }
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        var excludedDirectory = directory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try excludedDirectory.setResourceValues(values)
        try encrypted.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        var excludedFile = url
        try excludedFile.setResourceValues(values)
    }

    public func remove() throws {
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
        try keys.remove(account)
    }
}

public actor ClipboardHistoryStore {
    private let file: ClipboardEncryptedFile
    private var state = ClipboardHistorySnapshot()
    private var loaded = false

    public init(file: ClipboardEncryptedFile = .applicationFile("history")) { self.file = file }

    private func load() throws {
        guard !loaded else { return }
        if let saved = try file.read(ClipboardHistorySnapshot.self) {
            guard saved.schemaVersion == 1, saved.entries.count <= 600,
                  Set(saved.entries.map(\.id)).count == saved.entries.count,
                  saved.entries.filter(\.isPinned).count <= 100,
                  saved.entries.allSatisfy({ $0.byteCount <= ClipboardContentPolicy.maximumBytes }) else {
                throw ClipboardFailure.storage
            }
            state = saved
        }
        loaded = true
    }

    private func update(_ mutation: (inout ClipboardHistorySnapshot) throws -> Void) throws {
        try load()
        var next = state
        try mutation(&next)
        if next != state {
            try file.write(next)
            state = next
        }
    }

    public func snapshot(now: Date = Date()) throws -> ClipboardHistorySnapshot {
        try update { $0.prune(now: now) }
        return state
    }

    public func capture(_ text: String, now: Date = Date()) throws {
        try update { $0.capture(text, now: now) }
    }
    public func setPinned(_ id: UUID, pinned: Bool) throws { try update { try $0.setPinned(id, pinned: pinned) } }
    public func remove(_ id: UUID) throws { try update { $0.remove(id) } }
    public func clear(includingPinned: Bool) throws { try update { $0.clear(includingPinned: includingPinned) } }
    public func markCopied(_ id: UUID) throws { try update { try $0.markCopied(id) } }
    public func respond(to request: ClipboardRequest) throws -> ClipboardResponse {
        try snapshot().respond(to: request)
    }
}

public struct ClipboardCachedEntry: Codable, Equatable, Sendable {
    public var entry: ClipboardEntry
    public var cachedAt: Date
    public init(entry: ClipboardEntry, cachedAt: Date) { self.entry = entry; self.cachedAt = cachedAt }
}

public struct ClipboardCacheSnapshot: Codable, Equatable, Sendable {
    public var ownerID: String
    public var sourceID: String
    public var epoch: UUID
    public var entries: [ClipboardCachedEntry] = []

    public init(sourceID: String, epoch: UUID, ownerID: String = "") {
        self.sourceID = sourceID; self.epoch = epoch; self.ownerID = ownerID
    }

    public func isUsable(ownerID: String?, pairedSourceID: String?, pairingKnown: Bool) -> Bool {
        guard let ownerID, self.ownerID == ownerID else { return false }
        return sourceID == pairedSourceID || (pairedSourceID == nil && !pairingKnown)
    }

    public mutating func prune(now: Date = Date()) {
        entries.removeAll {
            $0.cachedAt.addingTimeInterval(86_400) <= now ||
            ($0.entry.expiresAt.map { $0 <= now } ?? false)
        }
        entries.sort { $0.cachedAt > $1.cachedAt }
        entries = Array(entries.prefix(50))
    }

    public mutating func reconcile(sourceID: String, epoch: UUID, manifest: [String: Int]) {
        if self.sourceID != sourceID || self.epoch != epoch { entries = [] }
        self.sourceID = sourceID; self.epoch = epoch
        entries.removeAll { manifest[$0.entry.id.uuidString] != $0.entry.revision }
        prune()
    }
}

public actor ClipboardCacheStore {
    private let file: ClipboardEncryptedFile
    public init(file: ClipboardEncryptedFile = .applicationFile("phone-cache")) { self.file = file }

    public func load() throws -> ClipboardCacheSnapshot? {
        guard var state = try file.read(ClipboardCacheSnapshot.self) else { return nil }
        guard state.entries.count <= 50, Set(state.entries.map { $0.entry.id }).count == state.entries.count,
              state.entries.allSatisfy({ $0.entry.byteCount <= ClipboardContentPolicy.maximumBytes }) else {
            throw ClipboardFailure.storage
        }
        state.prune()
        try file.write(state)
        return state
    }
    public func save(_ state: ClipboardCacheSnapshot) throws { try file.write(state) }
    public func clear() throws { try file.remove() }
}
