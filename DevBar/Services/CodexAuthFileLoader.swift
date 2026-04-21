import Foundation

enum CodexAuthFileLoader {
    static func loadOpenAIAccessToken() throws -> String {
        let authFileURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex", isDirectory: true)
            .appendingPathComponent("auth.json", isDirectory: false)

        let data = try Data(contentsOf: authFileURL)
        let decoded = try JSONDecoder().decode(CodexAuthFile.self, from: data)
        return (decoded.tokens.accessToken ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct CodexAuthFile: Decodable {
    struct Tokens: Decodable {
        let accessToken: String?

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
        }
    }

    let tokens: Tokens
}
