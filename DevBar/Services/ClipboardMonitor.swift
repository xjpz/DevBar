import AppKit
import Combine
import CoreGraphics
import DevBarCore
import SwiftUI

@MainActor
final class MacClipboardController: ObservableObject {
    @Published private(set) var snapshot = ClipboardHistorySnapshot()
    @Published private(set) var recordingEnabled: Bool
    @Published private(set) var sharingEnabled: Bool
    @Published private(set) var pausedUntil: Date?
    @Published private(set) var statusKey = "clipboard_status_off"
    @Published private(set) var error: String?
    @Published private(set) var skippedCount = 0
    @Published var ignoredApps: String {
        didSet { defaults.set(ignoredApps, forKey: "clipboard.ignoredApps") }
    }
    @Published var strictSource: Bool {
        didSet { defaults.set(strictSource, forKey: "clipboard.strictSource") }
    }
    let sharing = ClipboardSharingCoordinator()
    private let store = ClipboardHistoryStore()
    private let defaults = UserDefaults.standard
    private weak var relay: DeviceRelayManager?
    private var monitor: Task<Void, Never>?
    private var observers = Set<AnyCancellable>()
    private var lastChange = NSPasteboard.general.changeCount
    private var awake = true
    private var wasAvailable = false
    private var storageFailed = false
    private var lastLocked: Bool?
    private var window: NSWindow?
    private var peerRefresh: Task<Void, Never>?
    private var lastPeerRefresh = Date.distantPast
    private var lastPrunedAt = Date.distantPast

    init() {
        recordingEnabled = UserDefaults.standard.bool(forKey: "clipboard.recording")
        sharingEnabled = UserDefaults.standard.bool(forKey: "clipboard.sharing")
        pausedUntil = UserDefaults.standard.object(forKey: "clipboard.pause") as? Date
        ignoredApps = UserDefaults.standard.string(forKey: "clipboard.ignoredApps") ??
            "com.1password.1password\ncom.agilebits.onepassword7\ncom.bitwarden.desktop\ncom.dashlane.Dashlane\ncom.apple.keychainaccess"
        strictSource = UserDefaults.standard.object(forKey: "clipboard.strictSource") as? Bool ?? true
    }

    func start(relay: DeviceRelayManager) {
        guard monitor == nil else { return }
        self.relay = relay
        // Capability is part of this binary; it must be advertised even if loading Keychain/history waits.
        updateSharingStatus()
        sharing.attach(to: relay)
        sharing.authorization = { [weak self] in
            guard let self else { return .unavailable }
            return self.sharingFailure
        }
        sharing.hostHandler = { [weak self] request in
            guard let self else { throw ClipboardFailure.unavailable }
            return try await self.store.respond(to: request)
        }
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.sessionDidResignActiveNotification] {
            NSWorkspace.shared.notificationCenter.publisher(for: name).sink { [weak self] _ in
                Task { @MainActor in self?.suspend() }
            }.store(in: &observers)
        }
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
            NSWorkspace.shared.notificationCenter.publisher(for: name).sink { [weak self] _ in
                Task { @MainActor in
                    self?.awake = true
                    self?.lastChange = NSPasteboard.general.changeCount
                    await self?.reload()
                }
            }.store(in: &observers)
        }
        relay.$peers.map { Set($0.map(\.deviceId)) }.removeDuplicates().dropFirst().sink { [weak self] _ in
            Task { @MainActor in self?.sharing.reset() }
        }.store(in: &observers)
        monitor = Task { @MainActor [weak self] in
            await self?.reload()
            while !Task.isCancelled {
                await self?.tick()
                do { try await Task.sleep(for: .milliseconds(500)) } catch { return }
            }
        }
    }

    private func suspend() {
        awake = false; wasAvailable = false
        lastChange = NSPasteboard.general.changeCount
        sharing.reset()
        updateSharingStatus()
    }

    private var locked: Bool? {
        guard let session = CGSessionCopyCurrentDictionary() as? [String: Any] else { return nil }
        guard let onConsole = session[kCGSessionOnConsoleKey as String] as? Bool else { return nil }
        if !onConsole { return true }
        return session["CGSSessionScreenIsLocked"] as? Bool ?? false
    }

    private var sharingFailure: ClipboardFailure? {
        guard sharingEnabled else { return .disabled }
        guard awake, locked == false else { return .locked }
        return storageFailed ? .storage : nil
    }

    private func updateSharingStatus() {
        relay?.clipboardStatusFields = ["clipboardVersion": "1", "clipboardState": sharingFailure?.rawValue ?? "ready"]
    }

    func setRecording(_ enabled: Bool) {
        recordingEnabled = enabled
        defaults.set(enabled, forKey: "clipboard.recording")
        lastChange = NSPasteboard.general.changeCount
        wasAvailable = false
        if enabled { requestPermission() }
    }

    func requestPermission() {
        guard recordingEnabled, awake, locked == false else { return }
        if #available(macOS 15.4, *) {
            switch NSPasteboard.general.accessBehavior {
            case .alwaysDeny: statusKey = "clipboard_status_permission"; return
            case .ask, .default:
                // A single user-initiated attempt. The periodic task never triggers prompts.
                _ = NSPasteboard.general.string(forType: .string)
            default: break
            }
        }
        lastChange = NSPasteboard.general.changeCount
    }

    func setSharing(_ enabled: Bool) {
        sharingEnabled = enabled
        defaults.set(enabled, forKey: "clipboard.sharing")
        sharing.reset()
        updateSharingStatus()
    }

    func pause(for duration: TimeInterval?) {
        pausedUntil = duration.map { Date().addingTimeInterval($0) }
        defaults.set(pausedUntil, forKey: "clipboard.pause")
        wasAvailable = false
        lastChange = NSPasteboard.general.changeCount
    }

    private func tick() async {
        if sharingEnabled, peerRefresh == nil, Date().timeIntervalSince(lastPeerRefresh) >= 30 {
            lastPeerRefresh = Date()
            peerRefresh = Task { @MainActor [weak self] in
                await self?.relay?.refreshPeers()
                self?.peerRefresh = nil
            }
        }
        let currentLocked = locked
        if currentLocked != lastLocked {
            sharing.reset(); lastLocked = currentLocked
        }
        updateSharingStatus()
        if awake, currentLocked == false, Date().timeIntervalSince(lastPrunedAt) >= 60 {
            lastPrunedAt = Date()
            await reload()
        }
        if let until = pausedUntil, until <= Date() { pause(for: nil) }
        var available = recordingEnabled && awake && currentLocked == false && pausedUntil == nil && !storageFailed
        let nextStatus = !recordingEnabled ? "clipboard_status_off" :
            storageFailed ? "clipboard_error_storage" :
            !awake || currentLocked != false ? "clipboard_status_locked" :
            pausedUntil != nil ? "clipboard_status_paused" : "clipboard_status_recording"
        if #available(macOS 15.4, *), recordingEnabled, NSPasteboard.general.accessBehavior != .alwaysAllow {
            available = false
            if statusKey != "clipboard_status_permission" { statusKey = "clipboard_status_permission" }
        } else if statusKey != nextStatus {
            statusKey = nextStatus
        }
        let pasteboard = NSPasteboard.general
        guard available, wasAvailable else {
            wasAvailable = available
            lastChange = pasteboard.changeCount
            return
        }
        let count = pasteboard.changeCount
        guard count != lastChange else { return }
        lastChange = count
        let app = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        let exclusions = Set(ignoredApps.split(whereSeparator: { $0.isWhitespace || $0 == "," }).map(String.init))
        guard !(app == nil && strictSource), !exclusions.contains(app ?? ""),
              let items = pasteboard.pasteboardItems, items.count == 1 else { skippedCount += 1; return }
        let types = Set(items[0].types.map(\.rawValue))
        guard types.isDisjoint(with: ClipboardContentPolicy.privateTypes),
              !types.contains("public.file-url"), !types.contains("NSFilenamesPboardType"),
              let text = items[0].string(forType: .string) ?? items[0].string(forType: .URL), pasteboard.changeCount == count,
              ClipboardContentPolicy.acceptedKind(text: text, types: types) != nil else { skippedCount += 1; return }
        do { try await store.capture(text); await reload() }
        catch { failStorage() }
    }

    func reload() async {
        do { snapshot = try await store.snapshot(); storageFailed = false; error = nil }
        catch { failStorage() }
    }

    private func failStorage() {
        storageFailed = true
        error = ClipboardFailure.storage.localizedDescription
        updateSharingStatus()
    }

    func copy(_ entry: ClipboardEntry) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let item = NSPasteboardItem()
        item.setString(entry.text, forType: .string)
        item.setString("1", forType: NSPasteboard.PasteboardType("cc.xjpz.DevBar.clipboard.restore"))
        if pasteboard.writeObjects([item]) {
            lastChange = pasteboard.changeCount
            Task { do { try await store.markCopied(entry.id); await reload() } catch { failStorage() } }
        }
    }

    func pin(_ entry: ClipboardEntry) async {
        do { try await store.setPinned(entry.id, pinned: !entry.isPinned); await reload() }
        catch { self.error = (error as? ClipboardFailure ?? .storage).localizedDescription }
    }
    func remove(_ entry: ClipboardEntry) async {
        do { try await store.remove(entry.id); await reload() } catch { failStorage() }
    }
    func clear(includingPinned: Bool) async {
        do { try await store.clear(includingPinned: includingPinned); await reload() } catch { failStorage() }
    }

    func showWindow(locale: Locale) {
        if let window { window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); return }
        let view = ClipboardHistoryView(controller: self).environment(\.locale, locale)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 860, height: 600),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = String(localized: "clipboard_title")
        window.contentView = NSHostingView(rootView: view)
        window.isReleasedWhenClosed = false
        window.center(); window.makeKeyAndOrderFront(nil)
        self.window = window
        NSApp.activate(ignoringOtherApps: true)
    }
}
