// UpdateService.swift
// DevBar

import Foundation
import AppKit

enum UpdateError: Error, LocalizedError {
    case networkError(Error)
    case noReleaseFound
    case noSuitableAsset
    case downloadFailed
    case invalidArchive
    case installationFailed(String)

    var errorDescription: String? {
        switch self {
        case .networkError(let error):
            String(format: String(localized: "network_error"), error.localizedDescription)
        case .noReleaseFound:
            String(localized: "no_release_found")
        case .noSuitableAsset:
            String(localized: "no_update_package")
        case .downloadFailed:
            String(localized: "download_failed")
        case .invalidArchive:
            String(localized: "invalid_package")
        case .installationFailed(let reason):
            String(format: String(localized: "installation_failed"), reason)
        }
    }
}

final class UpdateService: Sendable {

    // MARK: - Version

    private var localVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    func isUpdateAvailable(remoteTag: String) -> Bool {
        let remote = stripVPrefix(remoteTag)
        let local = stripVPrefix(localVersion)
        return compareVersions(remote, local) > 0
    }

    // MARK: - Check

    func shouldCheckForUpdate() -> Bool {
        let defaults = UserDefaults.standard
        let lastCheck = defaults.double(forKey: Constants.Defaults.lastUpdateCheckKey)
        guard lastCheck == 0 else {
            let interval = Date().timeIntervalSince(Date(timeIntervalSince1970: lastCheck))
            let ok = interval >= Constants.Update.checkInterval
            print("[DevBar] Update check: last check \(Int(interval))s ago, should check: \(ok)")
            return ok
        }
        print("[DevBar] Update check: never checked before")
        return true
    }

    func isSkippedVersion(_ tagName: String) -> Bool {
        let skipped = UserDefaults.standard.string(forKey: Constants.Defaults.skippedVersionKey)
        return skipped == tagName
    }

    func checkForUpdates() async throws -> GitHubRelease {
        print("[DevBar] Update check: fetching \(Constants.Update.releasesURL)")
        var request = URLRequest(url: URL(string: Constants.Update.releasesURL)!)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw UpdateError.networkError(error)
        }

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            print("[DevBar] Update check: HTTP \(code)")
            throw UpdateError.noReleaseFound
        }

        let release: GitHubRelease
        do {
            release = try JSONDecoder().decode(GitHubRelease.self, from: data)
        } catch {
            throw UpdateError.noReleaseFound
        }

        UserDefaults.standard.set(Date().timeIntervalSince1970,
                                  forKey: Constants.Defaults.lastUpdateCheckKey)
        print("[DevBar] Update check: remote=\(release.tagName), local=\(localVersion), available=\(isUpdateAvailable(remoteTag: release.tagName))")
        return release
    }

    // MARK: - Download

    func downloadAsset(from url: URL, progressHandler: @escaping @Sendable (Double) -> Void) async throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("DevBarUpdate", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let destination = tempDir.appendingPathComponent("DevBar.zip")
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }

        let delegate = DownloadDelegate(
            progressHandler: progressHandler,
            destinationURL: destination
        )
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)

        let task = session.downloadTask(with: url)
        task.resume()

        let resultURL = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
            delegate.onComplete = { result in
                continuation.resume(with: result)
            }
        }

        session.invalidateAndCancel()

        // resultURL is already the final destination (moved in delegate)
        return resultURL
    }

    // MARK: - Install

    func installAndRelaunch(from zipURL: URL) throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("DevBarUpdate", isDirectory: true)
        let extractDir = tempDir.appendingPathComponent("extracted")

        // Clean previous extraction
        if FileManager.default.fileExists(atPath: extractDir.path) {
            try FileManager.default.removeItem(at: extractDir)
        }
        try FileManager.default.createDirectory(at: extractDir, withIntermediateDirectories: true)

        // Extract zip
        let ditto = Process()
        ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        ditto.arguments = ["-x", "-k", zipURL.path, extractDir.path]
        try ditto.run()
        ditto.waitUntilExit()
        guard ditto.terminationStatus == 0 else {
            throw UpdateError.invalidArchive
        }

        // Verify extracted app
        let newApp = extractDir.appendingPathComponent("DevBar.app")
        guard FileManager.default.fileExists(atPath: newApp.path) else {
            throw UpdateError.invalidArchive
        }

        // Determine install location from current bundle
        let currentAppURL = Bundle.main.bundleURL
        let installPath = currentAppURL.deletingLastPathComponent().path

        // Build replacement script
        let pid = ProcessInfo.processInfo.processIdentifier
        let script = """
        while kill -0 \(pid) 2>/dev/null; do sleep 0.5; done
        rm -rf "\(currentAppURL.path)"
        mv "\(newApp.path)" "\(installPath)/DevBar.app"
        open "\(installPath)/DevBar.app"
        rm -rf "\(tempDir.path)"
        """

        let bash = Process()
        bash.executableURL = URL(fileURLWithPath: "/bin/bash")
        bash.arguments = ["-c", script]
        try bash.run()

        print("[DevBar] Update install: relaunching from \(installPath)")
        NSApplication.shared.terminate(nil)
    }

    // MARK: - Private Helpers

    private func stripVPrefix(_ version: String) -> String {
        version.hasPrefix("v") ? String(version.dropFirst()) : version
    }

    private func compareVersions(_ a: String, _ b: String) -> Int {
        let partsA = a.split(separator: ".").compactMap { Int($0) }
        let partsB = b.split(separator: ".").compactMap { Int($0) }
        let count = max(partsA.count, partsB.count)
        for i in 0..<count {
            let va = i < partsA.count ? partsA[i] : 0
            let vb = i < partsB.count ? partsB[i] : 0
            if va != vb { return va > vb ? 1 : -1 }
        }
        return 0
    }
}

// MARK: - Download Delegate

private final class DownloadDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    var onComplete: ((Result<URL, Error>) -> Void)?
    private let progressHandler: @Sendable (Double) -> Void
    private let destinationURL: URL
    private var totalBytes: Int64 = 0

    init(progressHandler: @escaping @Sendable (Double) -> Void, destinationURL: URL) {
        self.progressHandler = progressHandler
        self.destinationURL = destinationURL
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        // Move file immediately — the temp URL is only valid until this method returns
        do {
            let dir = destinationURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }
            try FileManager.default.moveItem(at: location, to: destinationURL)
            onComplete?(.success(destinationURL))
        } catch {
            onComplete?(.failure(error))
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        totalBytes = totalBytesExpectedToWrite
        let progress = totalBytes > 0 ? Double(totalBytesWritten) / Double(totalBytes) : 0
        progressHandler(progress)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    didCompleteWithError error: Error?) {
        if let error {
            onComplete?(.failure(error))
        }
    }
}
