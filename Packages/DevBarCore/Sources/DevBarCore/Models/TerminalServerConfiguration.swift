import Foundation

public enum TerminalAuthenticationDraft: Equatable, Sendable {
    case password(secret: String)
    case privateKey(secret: String)
}

public struct TerminalServerDraft: Equatable, Sendable {
    public let name: String
    public let host: String
    public let portText: String
    public let username: String
    public let authentication: TerminalAuthenticationDraft

    public init(
        name: String,
        host: String,
        portText: String,
        username: String,
        authentication: TerminalAuthenticationDraft
    ) {
        self.name = name
        self.host = host
        self.portText = portText
        self.username = username
        self.authentication = authentication
    }
}

public struct TerminalServerConfiguration: Equatable, Sendable {
    public let name: String
    public let host: String
    public let port: Int
    public let username: String
    public let authentication: TerminalAuthenticationDraft

    public init(
        name: String,
        host: String,
        port: Int,
        username: String,
        authentication: TerminalAuthenticationDraft
    ) {
        self.name = name
        self.host = host
        self.port = port
        self.username = username
        self.authentication = authentication
    }
}

public enum TerminalServerValidationError: Error, Equatable, LocalizedError, Sendable {
    case missingHost
    case invalidPort
    case missingUsername
    case missingCredential

    public var errorDescription: String? {
        switch self {
        case .missingHost:
            return "Host is required."
        case .invalidPort:
            return "Port must be between 1 and 65535."
        case .missingUsername:
            return "Username is required."
        case .missingCredential:
            return "A password or SSH key is required."
        }
    }
}

public enum TerminalServerValidator {
    public static func validate(_ draft: TerminalServerDraft) throws -> TerminalServerConfiguration {
        let name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let host = draft.host.trimmingCharacters(in: .whitespacesAndNewlines)
        let username = draft.username.trimmingCharacters(in: .whitespacesAndNewlines)
        let portText = draft.portText.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !host.isEmpty else {
            throw TerminalServerValidationError.missingHost
        }

        guard let port = Int(portText), (1...65535).contains(port) else {
            throw TerminalServerValidationError.invalidPort
        }

        guard !username.isEmpty else {
            throw TerminalServerValidationError.missingUsername
        }

        let authentication: TerminalAuthenticationDraft
        switch draft.authentication {
        case let .password(secret):
            let trimmed = secret.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                throw TerminalServerValidationError.missingCredential
            }
            authentication = .password(secret: trimmed)
        case let .privateKey(secret):
            let trimmed = secret.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                throw TerminalServerValidationError.missingCredential
            }
            authentication = .privateKey(secret: trimmed)
        }

        return TerminalServerConfiguration(
            name: name.isEmpty ? host : name,
            host: host,
            port: port,
            username: username,
            authentication: authentication
        )
    }
}
