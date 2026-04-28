// WeChatShellEnvironment.swift
// DevBar

import Foundation

enum WeChatShellEnvironment {
    nonisolated static func buildPATH(environment: [String: String] = ProcessInfo.processInfo.environment) -> String {
        var paths: [String] = []

        appendPATH(environment["PATH"], to: &paths)
        appendPATH(loginShellPATH(environment: environment), to: &paths)

        let home = FileManager.default.homeDirectoryForCurrentUser.path
        paths.append(contentsOf: [
            "/opt/homebrew/bin",
            "/opt/homebrew/sbin",
            "/usr/local/bin",
            "/usr/local/sbin",
            "\(home)/.local/bin",
            "\(home)/.cargo/bin",
            "\(home)/.npm-global/bin",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin",
        ])

        paths.append(contentsOf: discoverVersionManagerBinPaths(home: home))
        return uniqueExistingDirectories(paths).joined(separator: ":")
    }

    nonisolated static func findExecutable(named name: String, inPATH pathValue: String) -> String? {
        for dir in pathValue.split(separator: ":").map(String.init) {
            let candidate = "\(dir)/\(name)"
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return nil
    }

    nonisolated private static func loginShellPATH(environment: [String: String]) -> String? {
        let shell = environment["SHELL"] ?? "/bin/zsh"
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: shell)
        process.arguments = ["-lic", "echo $PATH"]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let path = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return path?.isEmpty == false ? path : nil
        } catch {
            return nil
        }
    }

    nonisolated private static func appendPATH(_ pathValue: String?, to paths: inout [String]) {
        guard let pathValue, !pathValue.isEmpty else { return }
        paths.append(contentsOf: pathValue.split(separator: ":").map(String.init))
    }

    nonisolated private static func discoverVersionManagerBinPaths(home: String) -> [String] {
        let fileManager = FileManager.default
        let roots = [
            "\(home)/.nvm/versions/node",
            "\(home)/.fnm/node-versions",
            "\(home)/.asdf/installs/nodejs",
        ]

        var paths: [String] = []
        for root in roots {
            guard let entries = try? fileManager.contentsOfDirectory(atPath: root) else { continue }
            for entry in entries where !entry.hasPrefix(".") {
                let binPath = "\(root)/\(entry)/bin"
                if fileManager.isExecutableFile(atPath: "\(binPath)/node") ||
                    fileManager.isExecutableFile(atPath: "\(binPath)/codex") ||
                    fileManager.isExecutableFile(atPath: "\(binPath)/claude") {
                    paths.append(binPath)
                }
            }
        }

        let voltaBin = "\(home)/.volta/bin"
        if fileManager.fileExists(atPath: voltaBin) {
            paths.append(voltaBin)
        }

        return Array(paths.sorted().reversed())
    }

    nonisolated private static func uniqueExistingDirectories(_ paths: [String]) -> [String] {
        let fileManager = FileManager.default
        var seen = Set<String>()
        var result: [String] = []

        for rawPath in paths {
            let path = (rawPath as NSString).expandingTildeInPath
            guard !path.isEmpty, fileManager.fileExists(atPath: path) else { continue }
            guard seen.insert(path).inserted else { continue }
            result.append(path)
        }
        return result
    }
}
