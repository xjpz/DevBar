import Foundation

public enum APIError: Error, LocalizedError {
    case notLoggedIn
    case invalidResponse
    case httpError(Int)
    case unauthorized
    case openAIUnauthorized
    case mimoCookieExpired
    case providerMessage(String)
    case decodingError(Error)

    public var errorDescription: String? {
        switch self {
        case .notLoggedIn:
            return CoreL10n.text("not_logged_in")
        case .invalidResponse:
            return CoreL10n.text("invalid_response")
        case .httpError(let code):
            return String(format: CoreL10n.text("http_error"), code)
        case .unauthorized:
            return CoreL10n.text("login_expired")
        case .openAIUnauthorized:
            return CoreL10n.text("openai_token_invalid")
        case .mimoCookieExpired:
            return CoreL10n.text("mimo_cookie_expired")
        case .providerMessage(let message):
            return message
        case .decodingError(let error):
            return String(format: CoreL10n.text("decoding_failed"), error.localizedDescription)
        }
    }
}
