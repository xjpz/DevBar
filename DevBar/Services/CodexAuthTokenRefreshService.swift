import Foundation
import DevBarCore

enum CodexAuthTokenRefreshError: LocalizedError, Equatable {
    case authFileUnavailable
    case accountMismatch
    case refreshTokenMissing
    case codexExecutableNotFound
    case codexRefreshFailed
    case refreshedTokenUnavailable

    var errorDescription: String? {
        switch self {
        case .authFileUnavailable:
            return String(localized: "openai_codex_auth_unavailable")
        case .accountMismatch:
            return String(localized: "openai_codex_account_mismatch")
        case .refreshTokenMissing:
            return String(localized: "openai_codex_refresh_token_missing")
        case .codexExecutableNotFound:
            return String(localized: "openai_codex_cli_missing")
        case .codexRefreshFailed:
            return String(localized: "openai_codex_refresh_failed")
        case .refreshedTokenUnavailable:
            return String(localized: "openai_codex_refreshed_token_unavailable")
        }
    }
}

enum CodexAuthTokenRefreshService {
    enum RecoveryDecision: Equatable {
        case useCredential(CodexAuthCredential)
        case requestCodexRefresh
    }

    nonisolated static func recoverCredential(
        storedAccessToken: String,
        configuredAccountID: String?
    ) throws -> CodexAuthCredential {
        let onDiskCredential: CodexAuthCredential
        do {
            onDiskCredential = try CodexAuthFileLoader.loadOpenAICredential()
        } catch {
            throw CodexAuthTokenRefreshError.authFileUnavailable
        }

        switch try recoveryDecision(
            storedAccessToken: storedAccessToken,
            configuredAccountID: configuredAccountID,
            codexCredential: onDiskCredential
        ) {
        case .useCredential(let credential):
            return credential
        case .requestCodexRefresh:
            try CodexAppServerAuthRefresher.requestTokenRefresh()
            guard let refreshedCredential = try? CodexAuthFileLoader.loadOpenAICredential() else {
                throw CodexAuthTokenRefreshError.refreshedTokenUnavailable
            }
            try validateAccount(configuredAccountID, matches: refreshedCredential.accountID)
            guard !refreshedCredential.accessToken.isEmpty,
                  refreshedCredential.accessToken != storedAccessToken else {
                throw CodexAuthTokenRefreshError.refreshedTokenUnavailable
            }
            return refreshedCredential
        }
    }

    nonisolated static func recoveryDecision(
        storedAccessToken: String,
        configuredAccountID: String?,
        codexCredential: CodexAuthCredential
    ) throws -> RecoveryDecision {
        try validateAccount(configuredAccountID, matches: codexCredential.accountID)
        guard !codexCredential.accessToken.isEmpty else {
            throw CodexAuthTokenRefreshError.authFileUnavailable
        }
        if codexCredential.accessToken != storedAccessToken {
            return .useCredential(codexCredential)
        }
        guard codexCredential.hasRefreshToken else {
            throw CodexAuthTokenRefreshError.refreshTokenMissing
        }
        return .requestCodexRefresh
    }

    nonisolated private static func validateAccount(_ configuredAccountID: String?, matches codexAccountID: String?) throws {
        let configured = configuredAccountID?.trimmingCharacters(in: .whitespacesAndNewlines)
        let codex = codexAccountID?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard configured?.isEmpty == false, codex?.isEmpty == false else { return }
        guard configured == codex else {
            throw CodexAuthTokenRefreshError.accountMismatch
        }
    }
}

private enum CodexAppServerAuthRefresher {
    private struct Response: Decodable {
        struct ServerError: Decodable {
            let message: String?
        }

        let id: Int?
        let error: ServerError?
    }

    nonisolated static func requestTokenRefresh() throws {
        let path = WeChatShellEnvironment.buildPATH()
        guard let codexExecutable = WeChatShellEnvironment.findExecutable(named: "codex", inPATH: path) else {
            throw CodexAuthTokenRefreshError.codexExecutableNotFound
        }

        let process = Process()
        let input = Pipe()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: codexExecutable)
        process.arguments = ["app-server", "--stdio"]
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice

        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = path
        environment["HOME"] = FileManager.default.homeDirectoryForCurrentUser.path
        process.environment = environment

        do {
            try process.run()
        } catch {
            throw CodexAuthTokenRefreshError.codexRefreshFailed
        }

        defer {
            try? input.fileHandleForWriting.close()
            if process.isRunning {
                process.terminate()
            }
            process.waitUntilExit()
        }

        do {
            try writeMessage([
                "method": "initialize",
                "id": 1,
                "params": [
                    "clientInfo": [
                        "name": "devbar",
                        "title": "DevBar",
                        "version": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
                    ],
                    "capabilities": [:],
                ],
            ], to: input.fileHandleForWriting)
            try requireSuccess(responseID: 1, from: output.fileHandleForReading)

            try writeMessage(["method": "initialized"], to: input.fileHandleForWriting)
            try writeMessage([
                "method": "account/read",
                "id": 2,
                "params": ["refreshToken": true],
            ], to: input.fileHandleForWriting)
            try requireSuccess(responseID: 2, from: output.fileHandleForReading)
        } catch let error as CodexAuthTokenRefreshError {
            throw error
        } catch {
            throw CodexAuthTokenRefreshError.codexRefreshFailed
        }
    }

    nonisolated private static func writeMessage(_ object: [String: Any], to handle: FileHandle) throws {
        var data = try JSONSerialization.data(withJSONObject: object)
        data.append(0x0A)
        try handle.write(contentsOf: data)
    }

    nonisolated private static func requireSuccess(responseID: Int, from handle: FileHandle) throws {
        var buffered = Data()
        while true {
            if let newline = buffered.firstIndex(of: 0x0A) {
                let line = buffered[..<newline]
                buffered.removeSubrange(...newline)
                guard !line.isEmpty,
                      let response = try? JSONDecoder().decode(Response.self, from: Data(line)),
                      response.id == responseID else {
                    continue
                }
                guard response.error == nil else {
                    throw CodexAuthTokenRefreshError.codexRefreshFailed
                }
                return
            }

            guard let chunk = try handle.read(upToCount: 4_096), !chunk.isEmpty else {
                throw CodexAuthTokenRefreshError.codexRefreshFailed
            }
            buffered.append(chunk)
        }
    }
}
