import AppKit
import DevBarCore
import Foundation

@MainActor
final class ProviderPingScheduler {
    var onFire: (() -> Void)?
    var onWake: (() -> Void)?

    private let calculator = ProviderPingScheduleCalculator()
    private var timer: Timer?
    private var wakeObserver: NSObjectProtocol?

    init() {
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.onWake?()
            }
        }
    }

    deinit {
        timer?.invalidate()
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
        }
    }

    func schedule(config: ProviderPingConfig?) {
        timer?.invalidate()
        timer = nil

        guard let config,
              let nextFireDate = calculator.nextFireDate(for: config, now: Date()) else {
            return
        }

        let timer = Timer(fire: nextFireDate, interval: 0, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.onFire?()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }
}
