import Foundation
import DevBarCore

enum MimoCookieBuilder {
    static func cookies(from rawValue: String) -> [HTTPCookie] {
        rawValue
            .split(separator: ";")
            .compactMap { part -> HTTPCookie? in
                let pair = part.trimmingCharacters(in: .whitespacesAndNewlines)
                guard let separator = pair.firstIndex(of: "=") else { return nil }

                let name = pair[..<separator].trimmingCharacters(in: .whitespacesAndNewlines)
                var value = String(pair[pair.index(after: separator)...])
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                if value.hasPrefix("\"") { value.removeFirst() }
                if value.hasSuffix("\"") { value.removeLast() }

                guard !name.isEmpty, !value.isEmpty else { return nil }
                guard MimoAPIClient.requiredCookieValues(from: "\(name)=\(value)").keys.contains(name) else {
                    return nil
                }

                return HTTPCookie(properties: [
                    .domain: "platform.xiaomimimo.com",
                    .path: "/",
                    .name: String(name),
                    .value: value,
                    .secure: true,
                ])
            }
    }
}
