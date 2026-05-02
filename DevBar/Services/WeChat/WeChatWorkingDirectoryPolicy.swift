// WeChatWorkingDirectoryPolicy.swift
// DevBar

import AppKit
import Foundation

enum WeChatWorkingDirectoryPolicy {
    enum ProtectedDirectory: String, Sendable {
        case documents = "Documents"
        case desktop = "Desktop"
        case downloads = "Downloads"
        case iCloudDrive = "iCloud Drive"

        var displayName: String {
            switch self {
            case .documents: return String(localized: "wechat_cwd_protected_documents")
            case .desktop: return String(localized: "wechat_cwd_protected_desktop")
            case .downloads: return String(localized: "wechat_cwd_protected_downloads")
            case .iCloudDrive: return String(localized: "wechat_cwd_protected_icloud")
            }
        }
    }

    enum DirectoryStatus: Sendable, Equatable {
        case unset
        case normal(String)
        case protected(String, ProtectedDirectory)
        case missing(String)

        var path: String? {
            switch self {
            case .unset:
                return nil
            case .normal(let path), .protected(let path, _), .missing(let path):
                return path
            }
        }

        var isValidForSave: Bool {
            switch self {
            case .missing:
                return false
            case .unset, .normal, .protected:
                return true
            }
        }
    }

    struct DirectoryAccessResult: Sendable, Equatable {
        let path: String
        let isAccessible: Bool
        let message: String?
    }

    nonisolated static var defaultDirectoryURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return support
            .appendingPathComponent("DevBar", isDirectory: true)
            .appendingPathComponent("WeChatAgents", isDirectory: true)
            .appendingPathComponent("Workspace", isDirectory: true)
    }

    nonisolated static func ensureDefaultDirectory() -> String {
        let url = defaultDirectoryURL
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url.path
    }

    nonisolated static func effectiveDirectory(for configuredPath: String?) -> String {
        let trimmed = configuredPath?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else {
            return ensureDefaultDirectory()
        }
        return normalizedPath(trimmed)
    }

    nonisolated static func status(for configuredPath: String?) -> DirectoryStatus {
        let trimmed = configuredPath?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return .unset }

        let path = normalizedPath(trimmed)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return .missing(path)
        }

        if let protected = protectedDirectoryKind(for: path) {
            return .protected(path, protected)
        }
        return .normal(path)
    }

    nonisolated static func displayPath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path == home {
            return "~"
        }
        if path.hasPrefix(home + "/") {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }

    @MainActor
    static func chooseDirectory(initialPath: String?) -> String? {
        chooseDirectoryURL(initialPath: initialPath)?.path
    }

    @MainActor
    static func chooseDirectoryURL(initialPath: String?) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = String(localized: "wechat_cwd_choose")

        let initialStatus = status(for: initialPath)
        if let path = initialStatus.path, FileManager.default.fileExists(atPath: path) {
            panel.directoryURL = URL(fileURLWithPath: path)
        } else {
            panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser
        }

        return panel.runModal() == .OK ? panel.url : nil
    }

    nonisolated static func validateAccess(for path: String) -> DirectoryAccessResult {
        let normalized = normalizedPath(path)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: normalized, isDirectory: &isDirectory), isDirectory.boolValue else {
            return DirectoryAccessResult(
                path: normalized,
                isAccessible: false,
                message: String(localized: "wechat_cwd_missing")
            )
        }

        let probeURL = URL(fileURLWithPath: normalized, isDirectory: true)
            .appendingPathComponent(".devbar-access-check-\(UUID().uuidString)", isDirectory: false)

        do {
            try "DevBar access check".write(to: probeURL, atomically: true, encoding: .utf8)
            try? FileManager.default.removeItem(at: probeURL)
            return DirectoryAccessResult(path: normalized, isAccessible: true, message: nil)
        } catch {
            try? FileManager.default.removeItem(at: probeURL)
            return DirectoryAccessResult(
                path: normalized,
                isAccessible: false,
                message: "\(String(localized: "wechat_cwd_access_denied")) \(error.localizedDescription)"
            )
        }
    }

    nonisolated static func normalizedPath(_ path: String) -> String {
        let expanded = (path as NSString).expandingTildeInPath
        return URL(fileURLWithPath: expanded).standardizedFileURL.path
    }

    nonisolated static func path(_ path: String, isInsideOrEqualTo root: String) -> Bool {
        let candidatePath = normalizedPath(path)
        let rootPath = normalizedPath(root)
        return candidatePath == rootPath || candidatePath.hasPrefix(rootPath + "/")
    }

    nonisolated private static func protectedDirectoryKind(for path: String) -> ProtectedDirectory? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let protectedRoots: [(String, ProtectedDirectory)] = [
            ("\(home)/Documents", .documents),
            ("\(home)/Desktop", .desktop),
            ("\(home)/Downloads", .downloads),
            ("\(home)/Library/Mobile Documents", .iCloudDrive),
        ]

        for (root, kind) in protectedRoots {
            let normalizedRoot = normalizedPath(root)
            if path == normalizedRoot || path.hasPrefix(normalizedRoot + "/") {
                return kind
            }
        }
        return nil
    }
}
