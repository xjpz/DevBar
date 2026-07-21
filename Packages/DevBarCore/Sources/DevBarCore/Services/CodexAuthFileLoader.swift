import Foundation

public enum CodexAuthFileLoader {
    public static func loadOpenAIAccessToken() throws -> String {
        try loadOpenAICredential().accessToken
    }

    public static func loadOpenAICredential() throws -> CodexAuthCredential {
        #if os(macOS)
        let authFileURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex", isDirectory: true)
            .appendingPathComponent("auth.json", isDirectory: false)

        let data = try Data(contentsOf: authFileURL)
        return try decodeOpenAICredential(from: data)
        #else
        throw CocoaError(.fileReadUnsupportedScheme)
        #endif
    }

    static func decodeOpenAICredential(from data: Data) throws -> CodexAuthCredential {
        let decoded = try JSONDecoder().decode(CodexAuthFile.self, from: data)
        return CodexAuthCredential(
            accessToken: decoded.tokens.accessToken ?? "",
            accountID: decoded.tokens.accountID,
            hasRefreshToken: decoded.tokens.refreshToken?.isEmpty == false
        )
    }
}

public struct CodexAuthCredential: Sendable, Equatable {
    public let accessToken: String
    public let accountID: String?
    public let hasRefreshToken: Bool

    public init(accessToken: String, accountID: String?, hasRefreshToken: Bool) {
        self.accessToken = accessToken.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedAccountID = accountID?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.accountID = trimmedAccountID?.isEmpty == false ? trimmedAccountID : nil
        self.hasRefreshToken = hasRefreshToken
    }
}

public struct CodexAuthFile: Decodable {
    public struct Tokens: Decodable {
        public let accessToken: String?
        public let refreshToken: String?
        public let accountID: String?

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case refreshToken = "refresh_token"
            case accountID = "account_id"
        }
    }

    public let tokens: Tokens
}
