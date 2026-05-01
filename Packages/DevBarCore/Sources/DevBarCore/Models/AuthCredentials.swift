import Foundation

public struct AuthCredentials: Sendable, Codable, Equatable {
    public let token: String
    public let cookieString: String

    public init(token: String, cookieString: String) {
        self.token = token
        self.cookieString = cookieString
    }
}
