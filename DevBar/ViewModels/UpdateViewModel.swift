// UpdateViewModel.swift
// DevBar

import SwiftUI
import Combine
import AppKit

@MainActor
final class UpdateViewModel: ObservableObject {

    enum UpdateState: Equatable {
        case idle
        case checking
        case available(GitHubRelease)
        case downloading(progress: Double)
        case downloaded(zipURL: URL)
        case installing
        case error(String)
        case upToDate

        static func == (lhs: UpdateState, rhs: UpdateState) -> Bool {
            switch (lhs, rhs) {
            case (.idle, .idle), (.checking, .checking),
                 (.installing, .installing), (.upToDate, .upToDate):
                return true
            case (.available(let a), .available(let b)):
                return a.tagName == b.tagName
            case (.downloading(let a), .downloading(let b)):
                return a == b
            case (.downloaded(let a), .downloaded(let b)):
                return a == b
            case (.error(let a), .error(let b)):
                return a == b
            default:
                return false
            }
        }
    }

    @Published var state: UpdateState = .idle

    private let service = UpdateService()
    private var downloadTask: Task<Void, Never>?
    private var updateWindow: NSWindow?

    var latestRelease: GitHubRelease? {
        if case .available(let release) = state { return release }
        return nil
    }

    var hasUpdateAvailable: Bool {
        if case .available = state { return true }
        return false
    }

    // MARK: - Window Management

    private func showWindow() {
        // If window exists and is visible, just bring to front
        if let window = updateWindow, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        // Clean up previous window
        updateWindow = nil

        let contentView = UpdateView(viewModel: self)
        let hostingView = NSHostingView(rootView: contentView)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 280, height: 300),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        window.title = "DevBar 更新"
        window.center()
        window.level = .floating
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        updateWindow = window
    }

    private func hideWindow() {
        updateWindow?.orderOut(nil)
        updateWindow = nil
    }

    // MARK: - Actions

    func checkForUpdates(silent: Bool = true) {
        switch state {
        case .checking, .downloading, .installing:
            print("[DevBar] Update: check skipped, busy (\(state))")
            return
        default:
            break
        }

        if silent && !service.shouldCheckForUpdate() { return }

        print("[DevBar] Update: checking (silent=\(silent))...")
        state = .checking

        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let release = try await service.checkForUpdates()

                guard service.isUpdateAvailable(remoteTag: release.tagName) else {
                    print("[DevBar] Update: already up to date")
                    if !silent {
                        self.state = .upToDate
                        self.showWindow()
                        try? await Task.sleep(for: .seconds(2))
                        if case .upToDate = self.state {
                            self.hideWindow()
                            self.state = .idle
                        }
                    } else {
                        self.state = .idle
                    }
                    return
                }

                if silent && service.isSkippedVersion(release.tagName) {
                    print("[DevBar] Update: version \(release.tagName) was skipped by user")
                    self.state = .idle
                    return
                }

                print("[DevBar] Update: new version available: \(release.tagName)")
                self.state = .available(release)
                self.showWindow()
            } catch {
                if !silent {
                    self.state = .error(error.localizedDescription)
                    self.showWindow()
                } else {
                    print("[DevBar] Update check failed: \(error.localizedDescription)")
                    self.state = .idle
                }
            }
        }
    }

    func downloadUpdate() {
        guard case .available(let release) = state else { return }
        guard let asset = release.assets.first(where: { $0.name.hasSuffix(".zip") }) else {
            print("[DevBar] Update: no zip asset found in release \(release.tagName), assets=\(release.assets.map(\.name))")
            state = .error("未找到可用的更新包")
            return
        }

        state = .downloading(progress: 0)
        print("[DevBar] Update: downloading from \(asset.browserDownloadUrl)")

        downloadTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let url = URL(string: asset.browserDownloadUrl)!
                let localURL = try await service.downloadAsset(
                    from: url,
                    progressHandler: { [weak self] progress in
                        Task { @MainActor in
                            guard let self, case .downloading = self.state else { return }
                            self.state = .downloading(progress: progress)
                        }
                    }
                )
                if !Task.isCancelled {
                    print("[DevBar] Update: download complete -> \(localURL.lastPathComponent)")
                    self.state = .downloaded(zipURL: localURL)
                }
            } catch {
                if !Task.isCancelled {
                    self.state = .error(error.localizedDescription)
                }
            }
        }
    }

    func cancelDownload() {
        downloadTask?.cancel()
        downloadTask = nil
        state = .idle
        hideWindow()
    }

    func installAndRelaunch() {
        guard case .downloaded(let zipURL) = state else { return }
        state = .installing
        do {
            try service.installAndRelaunch(from: zipURL)
        } catch {
            state = .error(error.localizedDescription)
        }
    }

    func skipThisVersion() {
        if let release = latestRelease {
            UserDefaults.standard.set(release.tagName,
                                      forKey: Constants.Defaults.skippedVersionKey)
        }
        dismiss()
    }

    func openReleasePage() {
        if let url = URL(string: Constants.Update.releasesPageURL) {
            NSWorkspace.shared.open(url)
        }
    }

    func dismiss() {
        hideWindow()
        state = .idle
    }
}
