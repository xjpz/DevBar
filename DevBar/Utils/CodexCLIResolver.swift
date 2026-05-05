// CodexCLIResolver.swift
// DevBar

import Foundation

enum CodexCLIResolver: Sendable {
    private static let nvmBase = "\(NSHomeDirectory())/.nvm/versions/node"
    private static let fixedCandidates = [
        "/opt/homebrew/bin/codex",
        "/usr/local/bin/codex",
    ]

    // MARK: - Public

    static func resolveCodexPath() -> String? {
        if let saved = UserDefaults.standard.string(forKey: Constants.Defaults.codexPathKey),
           FileManager.default.isExecutableFile(atPath: saved)
        {
            return saved
        }

        let candidates = [
            findCodexByShell(),
            findCodexInNVM(),
        ] + fixedCandidates

        for path in candidates.compactMap({ $0 }) {
            if FileManager.default.isExecutableFile(atPath: path) {
                UserDefaults.standard.set(path, forKey: Constants.Defaults.codexPathKey)
                return path
            }
        }

        return nil
    }

    static func autoDetect() {
        UserDefaults.standard.removeObject(forKey: Constants.Defaults.codexPathKey)
        _ = resolveCodexPath()
    }

    @MainActor
    static func testCodex(at path: String) async -> (success: Bool, output: String) {
        guard FileManager.default.isExecutableFile(atPath: path) else {
            return (false, String(localized: "codex_not_executable"))
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = ["exec", "echo hello"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return (process.terminationStatus == 0, output)
        } catch {
            return (false, error.localizedDescription)
        }
    }

    // MARK: - Private

    private static func findCodexByShell() -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", "command -v codex"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let path = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return path?.isEmpty == false ? path : nil
        } catch {
            return nil
        }
    }

    private static func findCodexInNVM() -> String? {
        guard let versions = try? FileManager.default.contentsOfDirectory(atPath: nvmBase) else {
            return nil
        }

        for version in versions.sorted().reversed() {
            let path = "\(nvmBase)/\(version)/bin/codex"
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }

        return nil
    }
}
