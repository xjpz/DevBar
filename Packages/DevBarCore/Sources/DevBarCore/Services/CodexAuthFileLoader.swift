import Foundation

public enum CodexAuthFileLoader {
    public static func loadOpenAIAccessToken() throws -> String {
        #if os(macOS)
        let authFileURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex", isDirectory: true)
            .appendingPathComponent("auth.json", isDirectory: false)

        let data = try Data(contentsOf: authFileURL)
        let decoded = try JSONDecoder().decode(CodexAuthFile.self, from: data)
        return (decoded.tokens.accessToken ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        #else
        throw CocoaError(.fileReadUnsupportedScheme)
        #endif
    }
}

public struct CodexAuthFile: Decodable {
    public struct Tokens: Decodable {
        public let accessToken: String?

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
        }
    }

    public let tokens: Tokens
}
