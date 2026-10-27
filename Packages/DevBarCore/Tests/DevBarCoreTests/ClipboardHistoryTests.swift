import CryptoKit
import Foundation
import Testing
@testable import DevBarCore

@Test func clipboardPreservesCodeAndOnlyCoalescesAdjacentCopies() throws {
    var state = ClipboardHistorySnapshot()
    let code = "  let 中文 = 1\n\tprint(中文)\n"
    let now = Date()
    let captured = state.capture(code, now: now)
    #expect(captured)
    let id = try #require(state.entries.first?.id)
    state.capture(code, now: now.addingTimeInterval(1))
    #expect(state.entries.count == 1)
    #expect(state.entries[0].id == id)
    #expect(state.entries[0].text == code)
    #expect(state.entries[0].copyCount == 2)
    state.capture("https://developer.apple.com", now: now.addingTimeInterval(2))
    #expect(state.entries[0].kind == .url)
    state.capture(code, now: now.addingTimeInterval(3))
    #expect(state.entries.count == 3)
}

@Test func clipboardRejectsSensitiveMarkersFilesAndEncodedOversize() {
    #expect(ClipboardContentPolicy.acceptedKind(text: "password", types: ["org.nspasteboard.ConcealedType"]) == nil)
    #expect(ClipboardContentPolicy.acceptedKind(text: "name.txt", types: ["public.file-url"]) == nil)
    #expect(ClipboardContentPolicy.acceptedKind(text: "file:///private/test.txt") == nil)
    #expect(ClipboardContentPolicy.acceptedKind(text: "-----BEGIN RSA PRIVATE KEY-----") == nil)
    #expect(ClipboardContentPolicy.acceptedKind(text: "Authorization: Bearer secret") == nil)
    #expect(ClipboardContentPolicy.acceptedKind(text: String(repeating: "中", count: 11_000)) == nil)
    #expect(ClipboardContentPolicy.acceptedKind(text: String(repeating: "\u{0}", count: 32_000)) == nil)
    #expect(ClipboardContentPolicy.acceptedKind(text: String(repeating: "x", count: 32 * 1024)) == .text)
}

@Test func clipboardRetentionAndPinLimitAreIndependent() throws {
    var state = ClipboardHistorySnapshot()
    let now = Date()
    for number in 0..<100 {
        state.capture("pin \(number)", now: now.addingTimeInterval(Double(number)))
        try state.setPinned(state.entries[0].id, pinned: true, now: now)
    }
    state.capture("pin overflow", now: now.addingTimeInterval(100))
    #expect(throws: ClipboardFailure.pinLimit) { try state.setPinned(state.entries[0].id, pinned: true) }
    for number in 0..<510 { state.capture("item \(number)", now: now.addingTimeInterval(Double(101 + number))) }
    #expect(state.entries.count == 600)
    state.prune(now: now.addingTimeInterval(8 * 86_400))
    #expect(state.entries.count == 100)
    #expect(state.entries.allSatisfy { $0.isPinned })
    let epoch = state.epoch
    state.clear(includingPinned: true)
    #expect(state.epoch != epoch)
    #expect(state.entries.isEmpty)
}

@Test func clipboardPaginationRefusesMixedSnapshotsAndChangedDetails() throws {
    var state = ClipboardHistorySnapshot()
    for number in 0..<31 { state.capture("item \(number)") }
    let page = try state.respond(to: ClipboardRequest(.list))
    #expect(page.summaries.count == 30)
    #expect(page.nextOffset == 30)
    let summary = try #require(page.summaries.first)
    let second = try state.respond(to: ClipboardRequest(.list, offset: 30, epoch: page.epoch,
        revision: page.revision, cursor: page.nextCursor))
    #expect(second.summaries.count == 1)
    #expect(throws: ClipboardFailure.staleCursor) {
        try state.respond(to: ClipboardRequest(.list, query: "changed search", offset: 30,
            epoch: page.epoch, revision: page.revision, cursor: page.nextCursor))
    }
    state.remove(summary.id)
    #expect(throws: ClipboardFailure.staleCursor) {
        try state.respond(to: ClipboardRequest(.list, offset: 30, epoch: page.epoch, revision: page.revision))
    }
    #expect(throws: ClipboardFailure.notFound) {
        try state.respond(to: ClipboardRequest(.detail, epoch: page.epoch, revision: summary.revision, itemID: summary.id))
    }
}

private final class ClipboardMemoryKeys: ClipboardKeyStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String: Data] = [:]
    func load(_ account: String) throws -> Data? { lock.lock(); defer { lock.unlock() }; return storage[account] }
    func save(_ data: Data, account: String) throws { lock.lock(); defer { lock.unlock() }; storage[account] = data }
    func remove(_ account: String) throws { lock.lock(); defer { lock.unlock() }; storage[account] = nil }
}

@Test func clipboardDiskIsEncryptedAndMissingKeyNeverOverwritesHistory() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let keys = ClipboardMemoryKeys()
    let file = ClipboardEncryptedFile(url: directory.appendingPathComponent("history.sealed"), account: "test", keys: keys)
    let store = ClipboardHistoryStore(file: file)
    let text = "confidential clipboard content \(UUID())"
    try await store.capture(text)
    let ciphertext = try Data(contentsOf: file.url)
    #expect(ciphertext.range(of: Data(text.utf8)) == nil)
    let reopened = ClipboardHistoryStore(file: file)
    #expect(try await reopened.snapshot().entries.first?.text == text)
    try keys.remove("test")
    let missing = ClipboardHistoryStore(file: file)
    await #expect(throws: ClipboardFailure.storage) { try await missing.capture("must not replace") }
    #expect(try Data(contentsOf: file.url) == ciphertext)
    #expect(try keys.load("test") == nil)
}

@Test func clipboardBadCiphertextDoesNotEraseFile() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let keys = ClipboardMemoryKeys()
    let file = ClipboardEncryptedFile(url: directory.appendingPathComponent("history.sealed"), account: "test", keys: keys)
    let store = ClipboardHistoryStore(file: file)
    try await store.capture("kept")
    var damaged = try Data(contentsOf: file.url)
    damaged[damaged.count - 1] ^= 1
    try damaged.write(to: file.url)
    let reopened = ClipboardHistoryStore(file: file)
    await #expect(throws: (any Error).self) { try await reopened.snapshot() }
    #expect(try Data(contentsOf: file.url) == damaged)
}

@Test func clipboardOfflineCacheExpiresAndReconciliationCannotResurrectDeletes() throws {
    let now = Date()
    var history = ClipboardHistorySnapshot()
    history.capture("kept", now: now)
    var cache = ClipboardCacheSnapshot(sourceID: "mac", epoch: history.epoch, ownerID: "phone")
    let entry = try #require(history.entries.first)
    cache.entries = [ClipboardCachedEntry(entry: entry, cachedAt: now)]
    cache.prune(now: now.addingTimeInterval(86_400))
    #expect(cache.entries.isEmpty)
    cache.entries = [ClipboardCachedEntry(entry: entry, cachedAt: now)]
    cache.reconcile(sourceID: "mac", epoch: history.epoch, manifest: [:])
    #expect(cache.entries.isEmpty)
    cache.entries = [ClipboardCachedEntry(entry: entry, cachedAt: now)]
    cache.reconcile(sourceID: "new-mac", epoch: UUID(), manifest: [entry.id.uuidString: entry.revision])
    #expect(cache.entries.isEmpty)
}

@Test func clipboardAEADRejectsTamperingWrongPeerAndReplay() throws {
    let secret = try ClipboardRandom.bytes().base64EncodedString()
    let key = try ClipboardSharingCodec.key(secret: secret, from: "mac", to: "phone")
    let packet = ClipboardPacket(kind: .request, request: ClipboardRequest(.list, query: "private query"))
    let encoded = try ClipboardSharingCodec.seal(packet, key: key, from: "mac", to: "phone",
        requestID: "request", sessionID: "session", sequence: 1, bootstrap: false)
    var envelope = try ClipboardSharingCodec.envelope(encoded)
    #expect(try ClipboardSharingCodec.open(envelope, key: key, from: "mac", to: "phone", requestID: "request").request == packet.request)
    #expect(throws: (any Error).self) {
        try ClipboardSharingCodec.open(envelope, key: key, from: "impostor", to: "phone", requestID: "request")
    }
    #expect(throws: (any Error).self) {
        try ClipboardSharingCodec.open(envelope, key: SymmetricKey(size: .bits256),
            from: "mac", to: "phone", requestID: "request")
    }
    envelope.sealed[envelope.sealed.count - 1] ^= 1
    #expect(throws: (any Error).self) {
        try ClipboardSharingCodec.open(envelope, key: key, from: "mac", to: "phone", requestID: "request")
    }
    var replay = ClipboardReplayWindow()
    try replay.accept(2); try replay.accept(1)
    #expect(throws: ClipboardFailure.invalidMessage) { try replay.accept(2) }
    try replay.accept(200)
    #expect(throws: ClipboardFailure.invalidMessage) { try replay.accept(3) }
}

@Test func clipboardColdOfflineCacheStillRequiresTheSamePhoneIdentity() {
    let cache = ClipboardCacheSnapshot(sourceID: "mac", epoch: UUID(), ownerID: "phone")
    #expect(cache.isUsable(ownerID: "phone", pairedSourceID: nil, pairingKnown: false))
    #expect(cache.isUsable(ownerID: "phone", pairedSourceID: "mac", pairingKnown: true))
    #expect(!cache.isUsable(ownerID: nil, pairedSourceID: nil, pairingKnown: false))
    #expect(!cache.isUsable(ownerID: "other-phone", pairedSourceID: "mac", pairingKnown: true))
    #expect(!cache.isUsable(ownerID: "phone", pairedSourceID: nil, pairingKnown: true))
    #expect(!cache.isUsable(ownerID: "phone", pairedSourceID: "other-mac", pairingKnown: true))
}

@Test @MainActor func clipboardPacketsBypassGeneralRelayHistory() {
    let manager = DeviceRelayManager()
    var delivered = false
    manager.clipboardMessageHandler = { _ in delivered = true }
    manager.handleMessageForTesting(DeviceRelayMessage(type: .clipboardSecure, payload: ["encoded": "ciphertext"]))
    #expect(delivered)
    #expect(manager.receivedMessages.isEmpty)
}

@Test @MainActor func clipboardLoopbackHandshakeListDetailAndRevocation() async throws {
    let secret = try ClipboardRandom.bytes().base64EncodedString()
    var state = ClipboardHistorySnapshot()
    state.capture("code\n  indentation")
    let expected = state
    var denied: ClipboardFailure?
    var host: ClipboardSharingCoordinator!
    var client: ClipboardSharingCoordinator!
    host = ClipboardSharingCoordinator(identity: { "mac" }, pairSecret: { $0 == "phone" ? secret : nil }) { message, permit in
        guard permit.isValid else { throw ClipboardFailure.cancelled }
        await client.receiveForTesting(message)
    }
    client = ClipboardSharingCoordinator(identity: { "phone" }, pairSecret: { $0 == "mac" ? secret : nil }) { message, permit in
        guard permit.isValid else { throw ClipboardFailure.cancelled }
        await host.receiveForTesting(message)
    }
    host.authorization = { denied }
    host.hostHandler = { request in try expected.respond(to: request) }
    let page = try await client.perform(ClipboardRequest(.list), to: "mac")
    let summary = try #require(page.summaries.first)
    let detail = try await client.perform(ClipboardRequest(.detail, epoch: page.epoch,
        revision: summary.revision, itemID: summary.id), to: "mac")
    #expect(detail.entry?.text == "code\n  indentation")
    denied = .locked
    await #expect(throws: ClipboardFailure.locked) { try await client.perform(ClipboardRequest(.revision), to: "mac") }
    host.reset(); client.reset()
}

@Test @MainActor func clipboardRevocationInvalidatesAResponseWaitingToSend() async throws {
    let secret = try ClipboardRandom.bytes().base64EncodedString()
    var host: ClipboardSharingCoordinator!
    var client: ClipboardSharingCoordinator!
    var sends = 0
    var blocked = false
    host = ClipboardSharingCoordinator(identity: { "mac" }, pairSecret: { _ in secret }) { message, permit in
        sends += 1
        if sends == 2 {
            // Simulate a connection wait, during which the user disables sharing.
            await Task.yield()
            host.reset()
            blocked = !permit.isValid
            client.reset()
        }
        guard permit.isValid else { throw ClipboardFailure.cancelled }
        await client.receiveForTesting(message)
    }
    client = ClipboardSharingCoordinator(identity: { "phone" }, pairSecret: { _ in secret }) { message, permit in
        guard permit.isValid else { throw ClipboardFailure.cancelled }
        await host.receiveForTesting(message)
    }
    host.authorization = { nil }
    host.hostHandler = { _ in ClipboardResponse(epoch: UUID(), revision: 0) }
    await #expect(throws: ClipboardFailure.cancelled) {
        try await client.perform(ClipboardRequest(.list), to: "mac")
    }
    #expect(blocked)
}

@Test @MainActor func clipboardSendPermitRejectsBeforeConnecting() async {
    let relay = DeviceRelayManager()
    let permit = DeviceRelaySendPermit { false }
    await #expect(throws: ClipboardFailure.cancelled) {
        try await relay.send(DeviceRelayMessage(type: .clipboardSecure), permit: permit)
    }
    #expect(relay.logLines.isEmpty)
}
