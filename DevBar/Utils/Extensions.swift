// Extensions.swift
// DevBar

import Foundation

extension Date {
    static func formattedDateTime(from milliseconds: Int64) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(milliseconds) / 1000)
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd HH:mm"
        formatter.locale = Locale.current
        return formatter.string(from: date)
    }
}

extension String {
    static func cookieString(from cookies: [String: String]) -> String {
        cookies.map { "\($0.key)=\($0.value)" }.joined(separator: "; ")
    }
}
