import Foundation

public struct TerminalConnectionConfiguration: Equatable, Sendable {
    public let host: String
    public let port: Int
    public let username: String
    public let authentication: TerminalConnectionAuthentication
    public let columns: Int
    public let rows: Int

    public init(
        host: String,
        port: Int,
        username: String,
        authentication: TerminalConnectionAuthentication,
        columns: Int = 80,
        rows: Int = 24
    ) {
        self.host = host
        self.port = port
        self.username = username
        self.authentication = authentication
        self.columns = columns
        self.rows = rows
    }
}

public enum TerminalConnectionAuthentication: Equatable, Sendable {
    case password(String)
    case privateKey(String, passphrase: String? = nil)
}

public protocol TerminalSessionClient: Sendable {
    func connect(configuration: TerminalConnectionConfiguration) async throws
    func outputStream() async -> AsyncThrowingStream<String, Error>
    func send(_ data: Data) async throws
    func disconnect() async
}

public enum TerminalSessionClientError: LocalizedError, Equatable, Sendable {
    case missingCredential
    case unsupportedPrivateKeyFormat
    case passwordAuthenticationNotSupported
    case publicKeyAuthenticationNotSupported
    case invalidChannelType
    case notConnected

    public var errorDescription: String? {
        switch self {
        case .missingCredential:
            return "Missing terminal credential."
        case .unsupportedPrivateKeyFormat:
            return "SSH key authentication is not available for this key format yet."
        case .passwordAuthenticationNotSupported:
            return "The server does not support password authentication."
        case .publicKeyAuthenticationNotSupported:
            return "The server does not support SSH key authentication."
        case .invalidChannelType:
            return "The SSH server opened an unexpected channel type."
        case .notConnected:
            return "Terminal is not connected."
        }
    }
}
