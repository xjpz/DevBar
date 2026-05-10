// AntiSleepService.swift
// DevBar

import AppKit
import Combine
import Foundation
import IOKit
import IOKit.pwr_mgt

struct AntiSleepSnapshot: Equatable {
    var isEnabled: Bool
    var isPortableMac: Bool
    var isLidClosed: Bool?
}

@MainActor
final class AntiSleepService: ObservableObject {
    enum Status: Equatable {
        case disabled
        case desktopHolding
        case portableOpenHolding
        case portableClosedReleased
    }

    @Published private(set) var status: Status = .disabled

    private var isEnabled = false
    private var assertionID: IOPMAssertionID?
    private var pollingTask: Task<Void, Never>?
    private var notificationObservers: [NSObjectProtocol] = []

    nonisolated static func shouldHoldAssertion(for snapshot: AntiSleepSnapshot) -> Bool {
        guard snapshot.isEnabled else { return false }
        guard snapshot.isPortableMac else { return true }
        return snapshot.isLidClosed != true
    }

    nonisolated static func isPortableMac(model: String) -> Bool {
        model.contains("MacBook") || model.contains("MacBookAir") || model.contains("MacBookPro")
    }

    init() {
        installNotificationObservers()
        reconcile()
    }

    deinit {
        pollingTask?.cancel()
        notificationObservers.forEach {
            NSWorkspace.shared.notificationCenter.removeObserver($0)
        }
        if let assertionID {
            IOPMAssertionRelease(assertionID)
        }
    }

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        if enabled {
            startPollingIfNeeded()
        } else {
            stopPolling()
        }
        reconcile()
    }

    func refresh() {
        reconcile()
    }

    private func installNotificationObservers() {
        let center = NSWorkspace.shared.notificationCenter
        notificationObservers = [
            center.addObserver(
                forName: NSWorkspace.didWakeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.reconcile()
                }
            },
            center.addObserver(
                forName: NSWorkspace.willSleepNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.releaseAssertion()
                    self?.updateStatus()
                }
            },
        ]
    }

    private func startPollingIfNeeded() {
        guard pollingTask == nil else { return }
        guard Self.isPortableMac(model: Self.currentHardwareModel() ?? "") else { return }

        pollingTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                self?.reconcile()
                try? await Task.sleep(for: .seconds(15))
            }
        }
    }

    private func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    private func reconcile() {
        let snapshot = currentSnapshot()
        if Self.shouldHoldAssertion(for: snapshot) {
            holdAssertion()
        } else {
            releaseAssertion()
        }

        if isEnabled, snapshot.isPortableMac {
            startPollingIfNeeded()
        } else if !snapshot.isPortableMac || !isEnabled {
            stopPolling()
        }

        updateStatus(snapshot: snapshot)
    }

    private func currentSnapshot() -> AntiSleepSnapshot {
        let isPortable = Self.isPortableMac(model: Self.currentHardwareModel() ?? "")
        return AntiSleepSnapshot(
            isEnabled: isEnabled,
            isPortableMac: isPortable,
            isLidClosed: isPortable ? Self.currentLidClosed() : nil
        )
    }

    private func updateStatus(snapshot: AntiSleepSnapshot? = nil) {
        let snapshot = snapshot ?? currentSnapshot()
        guard snapshot.isEnabled else {
            status = .disabled
            return
        }

        guard snapshot.isPortableMac else {
            status = .desktopHolding
            return
        }

        status = snapshot.isLidClosed == true ? .portableClosedReleased : .portableOpenHolding
    }

    private func holdAssertion() {
        guard assertionID == nil else { return }

        var newAssertionID: IOPMAssertionID = 0
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertionTypeNoIdleSleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            "DevBar Prevent Sleep" as CFString,
            &newAssertionID
        )

        if result == kIOReturnSuccess {
            assertionID = newAssertionID
        } else {
            print("[DevBar] AntiSleep assertion failed: \(result)")
        }
    }

    private func releaseAssertion() {
        guard let assertionID else { return }
        IOPMAssertionRelease(assertionID)
        self.assertionID = nil
    }

    static func currentHardwareModel() -> String? {
        var size = 0
        guard sysctlbyname("hw.model", nil, &size, nil, 0) == 0, size > 0 else {
            return nil
        }

        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname("hw.model", &buffer, &size, nil, 0) == 0 else {
            return nil
        }

        return String(cString: buffer)
    }

    static func currentLidClosed() -> Bool? {
        let rootDomain = IORegistryEntryFromPath(kIOMainPortDefault, "IOService:/IOResources/IOPMrootDomain")
        guard rootDomain != MACH_PORT_NULL else { return nil }
        defer { IOObjectRelease(rootDomain) }

        let value = IORegistryEntryCreateCFProperty(
            rootDomain,
            "AppleClamshellState" as CFString,
            kCFAllocatorDefault,
            0
        )?.takeRetainedValue()

        return value as? Bool
    }
}
