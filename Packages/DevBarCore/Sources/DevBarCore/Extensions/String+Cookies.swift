import Foundation

public extension String {
    static func cookieString(from cookies: [String: String]) -> String {
        cookies.map { "\($0.key)=\($0.value)" }.joined(separator: "; ")
    }
}
