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
        process.arguments = ["exec", "--skip-git-repo-check", "echo hello"]

        // 构建 PATH：codex 所在目录（通常是 nvm bin）+ 系统 PATH + shell PATH
        let codexDir = (path as NSString).deletingLastPathComponent
        let systemPath = "/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        let shellPath = shellEnvPath()
        let mergedPath = "\(codexDir):\(shellPath ?? systemPath):\(systemPath)"

        var env = ProcessInfo.processInfo.environment
        env["PATH"] = mergedPath
        process.environment = env

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        do {
            try process.run()
            process.waitUntilExit()
            let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
            let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: outData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let errOutput = String(data: errData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if process.terminationStatus == 0 {
                return (true, output.isEmpty ? "OK" : output)
            } else {
                return (false, errOutput.isEmpty ? output : errOutput)
            }
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

    private static func shellEnvPath() -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", "echo $PATH"]

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
}
