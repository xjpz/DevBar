import Combine
import DevBarCore
import Foundation
import UIKit

@MainActor
final class IOSClipboardViewModel: ObservableObject {
    @Published private(set) var summaries: [ClipboardSummary] = []
    @Published var detail: ClipboardEntry?
    @Published private(set) var error: String?
    @Published private(set) var offline = false
    @Published private(set) var loading = false
    @Published private(set) var nextOffset: Int?
    @Published private(set) var updatedAt: Date?
    @Published private(set) var copiedID: UUID?
    @Published private(set) var detailRequests = 0
    @Published private(set) var cacheEnabled = UserDefaults.standard.object(forKey: "clipboard.cacheEnabled") as? Bool ?? true
    private let sharing = ClipboardSharingCoordinator()
    private let cacheStore = ClipboardCacheStore()
    private var cache: ClipboardCacheSnapshot?
    private weak var relay: DeviceRelayManager?
    private var observers = Set<AnyCancellable>()
    private var generation = UUID()
    private var active = false
    private var query = ""
    private var pinnedOnly = false
    private var epoch: UUID?
    private var revision: Int?
    private var cursor: String?
    private var lastPeerRefresh = Date.distantPast
    private var lastIdentity: String?
    private var lastPeerID: String?

    var peer: DeviceRelayDevice? { relay?.peers.first { $0.deviceType == .mac } }
    var connectionKey: String {
        guard let relay, let peer else { return "clipboard_not_paired" }
        return switch relay.connectionStatus(for: peer) {
        case .local: "clipboard_connection_local"
        case .remote: "clipboard_connection_remote"
        case .offline: "clipboard_connection_offline"
        }
    }

    func attach(relay: DeviceRelayManager) {
        self.relay = relay
        lastIdentity = relay.localDeviceID
        lastPeerID = relay.peers.first { $0.deviceType == .mac }?.deviceId
        sharing.attach(to: relay)
        relay.$peers.map { $0.first { $0.deviceType == .mac }?.deviceId }.removeDuplicates().dropFirst().sink { [weak self] id in
            guard let self else { return }
            let previous = self.lastPeerID; self.lastPeerID = id
            // Initial discovery is not an identity change. Validate persisted cache after setup.
            guard previous != nil, previous != id else { return }
            Task { @MainActor in await self.identityChanged() }
        }.store(in: &observers)
        relay.$localDeviceID.removeDuplicates().dropFirst().sink { [weak self] id in
            guard let self else { return }
            let previous = self.lastIdentity; self.lastIdentity = id
            guard previous != nil, previous != id else { return }
            Task { @MainActor in await self.identityChanged() }
        }.store(in: &observers)
        relay.$hasLoadedPeers.removeDuplicates().dropFirst().sink { [weak self] loaded in
            Task { @MainActor in
                guard let self, loaded, self.peer == nil else { return }
                await self.identityChanged()
            }
        }.store(in: &observers)
        relay.$clipboardPeerStates.sink { [weak self] states in
            guard let self, let peer = self.peer, let state = states[peer.deviceId], state != "ready" else { return }
            Task { @MainActor in
                self.error = (ClipboardFailure(rawValue: state) ?? .unavailable).localizedDescription
                await self.discardCache()
                self.summaries = []; self.detail = nil
                self.sharing.reset()
            }
        }.store(in: &observers)
    }

    private func identityChanged() async {
        sharing.reset(); generation = UUID()
        summaries = []; detail = nil; epoch = nil; revision = nil; nextOffset = nil
        await discardCache()
    }

    func setCacheEnabled(_ value: Bool) async {
        cacheEnabled = value
        UserDefaults.standard.set(value, forKey: "clipboard.cacheEnabled")
        if !value { await discardCache() }
    }

    func discardCache() async {
        cache = nil
        if offline { summaries = []; detail = nil }
        do { try await cacheStore.clear() }
        catch { self.error = ClipboardFailure.storage.localizedDescription }
    }

    func stop() {
        active = false; generation = UUID(); sharing.reset()
        summaries = []; detail = nil; copiedID = nil; loading = false
        // Keep only encrypted disk cache while backgrounded. No cleartext clipboard history in UI memory.
        cache = nil
    }

    func run(query: String, pinnedOnly: Bool) async {
        // Setup publishes the local Keychain identity before awaiting the relay network call.
        // Until then, keep the encrypted file intact rather than treating it as another owner.
        guard relay?.localDeviceID != nil else { return }
        let token = UUID(); generation = token; active = true
        self.query = String(query.prefix(250)); self.pinnedOnly = pinnedOnly
        sharing.reset()
        if cacheEnabled {
            do {
                if let saved = try await cacheStore.load(),
                   saved.isUsable(ownerID: relay?.localDeviceID, pairedSourceID: peer?.deviceId,
                                  pairingKnown: relay?.hasLoadedPeers ?? true) { cache = saved }
                else { await discardCache() }
            } catch { self.error = ClipboardFailure.storage.localizedDescription }
        }
        guard token == generation, !Task.isCancelled else { return }
        await refresh()
        while active, generation == token, !Task.isCancelled {
            do { try await Task.sleep(for: .seconds(5)) } catch { break }
            guard generation == token, !Task.isCancelled else { break }
            await refresh(checkRevisionOnly: true)
        }
    }

    func refresh(checkRevisionOnly: Bool = false, loadMore: Bool = false) async {
        guard active, !loading, let relay else { return }
        guard let peer else { showOfflineCache(); return }
        let token = generation
        loading = true
        defer { loading = false }
        do {
            // Also refresh pairing/revocation knowledge while this feature is foregrounded.
            if Date().timeIntervalSince(lastPeerRefresh) >= 30 {
                await relay.refreshPeers(); lastPeerRefresh = Date()
            }
            try Task.checkCancellation()
            // A cached disabled state must not prevent probing after the user enables sharing on Mac.
            let capability = try await relay.fetchClipboardCapability(targetDeviceID: peer.deviceId)
            if let state = capability.state, state != "ready" {
                throw ClipboardFailure(rawValue: state) ?? .unavailable
            }
            guard relay.clipboardPairSecret(for: peer.deviceId) != nil else { throw ClipboardFailure.rePair }
            let state = try await sharing.perform(ClipboardRequest(.revision), to: peer.deviceId)
            guard active, token == generation, !Task.isCancelled else { return }
            if var saved = cache {
                saved.reconcile(sourceID: peer.deviceId, epoch: state.epoch, manifest: state.manifest)
                cache = saved
                if cacheEnabled {
                    do { try await cacheStore.save(saved) }
                    catch { self.error = ClipboardFailure.storage.localizedDescription }
                }
            }
            if let detail, state.manifest[detail.id.uuidString] != detail.revision { self.detail = nil }
            if checkRevisionOnly, state.epoch == epoch, state.revision == revision, !offline { return }
            let offset = loadMore ? (nextOffset ?? 0) : 0
            let response = try await sharing.perform(ClipboardRequest(.list, query: query, pinnedOnly: pinnedOnly,
                offset: offset, epoch: loadMore ? epoch : nil, revision: loadMore ? revision : nil,
                cursor: loadMore ? cursor : nil), to: peer.deviceId)
            guard active, token == generation, !Task.isCancelled else { return }
            epoch = response.epoch; revision = response.revision
            if loadMore { summaries += response.summaries } else { summaries = response.summaries }
            nextOffset = response.nextOffset; cursor = response.nextCursor
            updatedAt = Date(); offline = false; error = nil
        } catch {
            guard active, token == generation, !Task.isCancelled else { return }
            let failure = error as? ClipboardFailure
            if let failure, [.disabled, .locked, .rePair, .unsupported].contains(failure) {
                await discardCache(); summaries = []; detail = nil; offline = false
            } else if failure == .staleCursor {
                nextOffset = nil; revision = nil
            } else {
                showOfflineCache()
            }
            self.error = (failure ?? .unavailable).localizedDescription
        }
    }

    private func showOfflineCache() {
        offline = true; nextOffset = nil
        cache?.prune()
        if let cache {
            epoch = cache.epoch
            summaries = cache.entries.map(\.entry).filter {
                (!pinnedOnly || $0.isPinned) && (query.isEmpty || $0.text.localizedCaseInsensitiveContains(query))
            }.sorted { $0.lastCopiedAt > $1.lastCopiedAt }.map(ClipboardSummary.init)
        } else { summaries = [] }
        if let detail, !summaries.contains(where: { $0.id == detail.id }) { self.detail = nil }
    }

    private func entry(for summary: ClipboardSummary) async throws -> ClipboardEntry {
        guard let relay, active else { throw ClipboardFailure.unavailable }
        if offline {
            cache?.prune()
            guard cache?.isUsable(ownerID: relay.localDeviceID, pairedSourceID: peer?.deviceId,
                                 pairingKnown: relay.hasLoadedPeers) == true,
                  let entry = cache?.entries.first(where: { $0.entry.id == summary.id })?.entry else {
                throw ClipboardFailure.notFound
            }
            return entry
        }
        guard let peer else { throw ClipboardFailure.unavailable }
        let response = try await sharing.perform(ClipboardRequest(.detail, epoch: epoch,
            revision: summary.revision, itemID: summary.id), to: peer.deviceId)
        guard let entry = response.entry else { throw ClipboardFailure.notFound }
        guard entry.id == summary.id, entry.revision == summary.revision, response.epoch == epoch,
              ClipboardContentPolicy.acceptedKind(text: entry.text) == entry.kind else {
            throw ClipboardFailure.invalidMessage
        }
        return entry
    }

    func open(_ summary: ClipboardSummary, copy: Bool = false) async {
        guard active, detailRequests < 2 else { return }
        let token = generation
        detailRequests += 1
        defer { detailRequests -= 1 }
        var cacheWriteFailed = false
        do {
            let entry = try await entry(for: summary)
            guard active, token == generation, !Task.isCancelled else { return }
            if cacheEnabled, let peer, let ownerID = relay?.localDeviceID, let epoch {
                var saved = cache ?? ClipboardCacheSnapshot(sourceID: peer.deviceId, epoch: epoch, ownerID: ownerID)
                if saved.epoch != epoch || saved.sourceID != peer.deviceId || saved.ownerID != ownerID {
                    saved = ClipboardCacheSnapshot(sourceID: peer.deviceId, epoch: epoch, ownerID: ownerID)
                }
                saved.entries.removeAll { $0.entry.id == entry.id }
                // Receiving from an offline cache must never extend its lifetime.
                if !offline {
                    saved.entries.append(ClipboardCachedEntry(entry: entry, cachedAt: Date()))
                    saved.prune(); cache = saved
                    do { try await cacheStore.save(saved) }
                    catch { cacheWriteFailed = true; self.error = ClipboardFailure.storage.localizedDescription }
                }
            }
            guard active, token == generation else { return }
            if copy {
                UIPasteboard.general.setItems([["public.utf8-plain-text": entry.text]], options: [.localOnly: true])
                copiedID = entry.id
                Task { @MainActor [weak self] in
                    try? await Task.sleep(for: .seconds(2))
                    if self?.copiedID == entry.id { self?.copiedID = nil }
                }
            } else { detail = entry }
            if !cacheWriteFailed { error = nil }
        } catch {
            guard active, token == generation else { return }
            self.error = (error as? ClipboardFailure ?? .unavailable).localizedDescription
            if let failure = error as? ClipboardFailure, [.disabled, .locked, .rePair].contains(failure) {
                await discardCache(); summaries = []; detail = nil
            }
        }
    }
}
