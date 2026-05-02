// WeChatAuthorizedDirectoryStore.swift
// DevBar

import Combine
import Foundation

@MainActor
final class WeChatAuthorizedDirectoryStore: ObservableObject {
    struct AuthorizedDirectory: Identifiable, Equatable, Sendable {
        let id: UUID
        let path: String
        let bookmarkData: Data
        let createdAt: Date
        var isStale: Bool
    }

    enum DirectoryError: LocalizedError {
        case accessDenied(String)
        case notAuthorized(String)
        case bookmarkStale(String)
        case accessStartFailed(String)

        var errorDescription: String? {
            switch self {
            case .accessDenied(let message):
                return message
            case .notAuthorized(let path):
                return "该目录未在 Mac 端授权，远程无法完成 macOS 文件夹授权。请先在 DevBar 设置中添加授权工作目录。\n\(path)"
            case .bookmarkStale(let path):
                return "授权目录需要重新授权：\(path)"
            case .accessStartFailed(let path):
                return "无法打开授权目录访问：\(path)"
            }
        }
    }

    @Published private(set) var directories: [AuthorizedDirectory] = []

    private struct StoredDirectory: Codable {
        let id: UUID
        let path: String
        let bookmarkData: Data
        let createdAt: Date
    }

    private let fileManager = FileManager.default
    private let storeURL: URL

    init() {
        let baseURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("DevBar", isDirectory: true)
            .appendingPathComponent("WeChatAgents", isDirectory: true)
        self.storeURL = baseURL.appendingPathComponent("authorized-directories.json", isDirectory: false)
        load()
    }

    @discardableResult
    func addDirectory(url: URL) throws -> AuthorizedDirectory {
        let normalizedPath = WeChatWorkingDirectoryPolicy.normalizedPath(url.path)
        let accessURL = URL(fileURLWithPath: normalizedPath, isDirectory: true)
        let didStartAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let access = WeChatWorkingDirectoryPolicy.validateAccess(for: normalizedPath)
        guard access.isAccessible else {
            throw DirectoryError.accessDenied(access.message ?? String(localized: "wechat_cwd_access_denied"))
        }

        let bookmarkData = try url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        let now = Date()
        let directory = AuthorizedDirectory(
            id: directories.first(where: { $0.path == normalizedPath })?.id ?? UUID(),
            path: accessURL.path,
            bookmarkData: bookmarkData,
            createdAt: now,
            isStale: false
        )

        if let index = directories.firstIndex(where: { $0.path == normalizedPath }) {
            directories[index] = directory
        } else {
            directories.append(directory)
            directories.sort { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
        }
        save()
        return directory
    }

    func removeDirectory(id: UUID) {
        directories.removeAll { $0.id == id }
        save()
    }

    func isPathAllowedRemotely(_ path: String) -> Bool {
        isInDefaultWorkspace(path) || authorizedRoot(for: path) != nil
    }

    func authorizedRoot(for path: String) -> AuthorizedDirectory? {
        let normalizedPath = WeChatWorkingDirectoryPolicy.normalizedPath(path)
        return directories
            .filter { !$0.isStale && WeChatWorkingDirectoryPolicy.path(normalizedPath, isInsideOrEqualTo: $0.path) }
            .sorted { $0.path.count > $1.path.count }
            .first
    }

    func accessHandle(for path: String) throws -> WeChatAuthorizedDirectoryAccess? {
        let normalizedPath = WeChatWorkingDirectoryPolicy.normalizedPath(path)
        guard !isInDefaultWorkspace(normalizedPath) else { return nil }
        guard let directory = authorizedRoot(for: normalizedPath) else {
            throw DirectoryError.notAuthorized(normalizedPath)
        }

        var isStale = false
        let url = try URL(
            resolvingBookmarkData: directory.bookmarkData,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )

        if isStale {
            markStale(id: directory.id)
            throw DirectoryError.bookmarkStale(directory.path)
        }

        let didStartAccess = url.startAccessingSecurityScopedResource()
        guard didStartAccess else {
            throw DirectoryError.accessStartFailed(directory.path)
        }
        return WeChatAuthorizedDirectoryAccess(url: url)
    }

    func withAccess<T>(to path: String, perform operation: () throws -> T) throws -> T {
        let access = try accessHandle(for: path)
        defer {
            access?.stop()
        }
        return try operation()
    }

    func unauthorizedRemoteMessage(for path: String) -> String {
        let normalizedPath = WeChatWorkingDirectoryPolicy.normalizedPath(path)
        return "该目录未在 Mac 端授权，远程无法完成 macOS 文件夹授权。请先在 DevBar 设置中添加授权工作目录。\n\(normalizedPath)"
    }

    func remoteListText(currentAgent: WeChatAgentRouter.AgentConfig? = nil) -> String {
        var lines = [
            "[DevBar] 可用工作目录:",
            "默认: \(WeChatWorkingDirectoryPolicy.ensureDefaultDirectory())",
        ]

        if let currentAgent {
            lines.append("当前 \(currentAgent.name): \(WeChatWorkingDirectoryPolicy.effectiveDirectory(for: currentAgent.cwd))")
        }

        if directories.isEmpty {
            lines.append("远程可用: 未添加")
        } else {
            lines.append("远程可用:")
            for (index, directory) in directories.enumerated() {
                let suffix = directory.isStale ? " (需重新授权)" : ""
                lines.append("  \(index + 1). \(directory.path)\(suffix)")
            }
        }
        return lines.joined(separator: "\n")
    }

    private func isInDefaultWorkspace(_ path: String) -> Bool {
        WeChatWorkingDirectoryPolicy.path(path, isInsideOrEqualTo: WeChatWorkingDirectoryPolicy.ensureDefaultDirectory())
    }

    private func load() {
        guard let data = try? Data(contentsOf: storeURL),
              let stored = try? JSONDecoder().decode([StoredDirectory].self, from: data) else {
            directories = []
            return
        }

        directories = stored.map { item in
            var isStale = false
            let resolvedPath: String
            if let url = try? URL(
                resolvingBookmarkData: item.bookmarkData,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) {
                resolvedPath = WeChatWorkingDirectoryPolicy.normalizedPath(url.path)
            } else {
                resolvedPath = item.path
                isStale = true
            }
            return AuthorizedDirectory(
                id: item.id,
                path: resolvedPath,
                bookmarkData: item.bookmarkData,
                createdAt: item.createdAt,
                isStale: isStale
            )
        }
    }

    private func save() {
        let stored = directories.map {
            StoredDirectory(id: $0.id, path: $0.path, bookmarkData: $0.bookmarkData, createdAt: $0.createdAt)
        }
        try? fileManager.createDirectory(at: storeURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(stored) else { return }
        try? data.write(to: storeURL, options: .atomic)
    }

    private func markStale(id: UUID) {
        guard let index = directories.firstIndex(where: { $0.id == id }) else { return }
        directories[index].isStale = true
    }
}

final class WeChatAuthorizedDirectoryAccess: @unchecked Sendable {
    private let url: URL
    private var isActive = true

    init(url: URL) {
        self.url = url
    }

    func stop() {
        guard isActive else { return }
        isActive = false
        url.stopAccessingSecurityScopedResource()
    }

    deinit {
        stop()
    }
}
