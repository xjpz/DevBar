import Foundation

enum MacSystemCommandExecutor {
    static func lockScreen() throws {
        var errors: [String] = []

        for path in cgSessionCandidatePaths where FileManager.default.isExecutableFile(atPath: path) {
            do {
                try run(path, arguments: ["-suspend"])
                return
            } catch {
                errors.append("\(path): \(error.localizedDescription)")
            }
        }

        do {
            try run(
                "/usr/bin/osascript",
                arguments: [
                    "-e",
                    "tell application \"System Events\" to key code 12 using {control down, command down}",
                ]
            )
            return
        } catch {
            errors.append("osascript lock shortcut: \(error.localizedDescription)")
        }

        let screenSaverPath = "/System/Library/CoreServices/ScreenSaverEngine.app"
        if FileManager.default.fileExists(atPath: screenSaverPath) {
            do {
                try run("/usr/bin/open", arguments: [screenSaverPath])
                return
            } catch {
                errors.append("ScreenSaverEngine: \(error.localizedDescription)")
            }
        }

        do {
            try displaySleep()
            return
        } catch {
            errors.append("pmset displaysleepnow: \(error.localizedDescription)")
        }

        throw MacSystemCommandError.unavailable(command: "lockScreen", errors: errors)
    }

    static func wakeDisplay() throws {
        try run("/usr/bin/caffeinate", arguments: ["-u", "-t", "3"])
    }

    static func displaySleep() throws {
        try run("/usr/bin/pmset", arguments: ["displaysleepnow"])
    }

    private static let cgSessionCandidatePaths = [
        "/System/Library/CoreServices/Menu Extras/User.menu/Contents/Resources/CGSession",
        "/System/Library/CoreServices/CGSession",
    ]

    private static func run(_ executablePath: String, arguments: [String]) throws {
        let process = Process()
        let errorPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        process.standardError = errorPipe
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: errorData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw MacSystemCommandError.failed(
                executablePath: executablePath,
                status: process.terminationStatus,
                message: message
            )
        }
    }
}

enum MacSystemCommandError: LocalizedError {
    case failed(executablePath: String, status: Int32, message: String?)
    case unavailable(command: String, errors: [String])

    var errorDescription: String? {
        switch self {
        case let .failed(executablePath, status, message):
            if let message, !message.isEmpty {
                return "\(executablePath) exited \(status): \(message)"
            }
            return "\(executablePath) exited \(status)"
        case let .unavailable(command, errors):
            guard !errors.isEmpty else {
                return String(format: String(localized: "没有可用的 %@ 命令"), command)
            }
            return String(
                format: String(localized: "%@ 命令均失败：%@"),
                command,
                errors.joined(separator: "; ")
            )
        }
    }
}
