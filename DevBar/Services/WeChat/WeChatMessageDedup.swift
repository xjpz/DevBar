// WeChatMessageDedup.swift
// DevBar

import Foundation

actor WeChatMessageDedup {
    private struct Entry {
        let timestamp: Date
    }

    private var processed: [String: Entry] = [:]
    // content dedup: userID -> (text, timestamp)
    private var recentContent: [String: (text: String, time: Date)] = [:]
    private let ttl: TimeInterval = 300
    private let contentDeduWindow: TimeInterval = 10

    /// Returns `true` if the message was already processed (duplicate).
    func checkAndMark(_ messageID: String) -> Bool {
        cleanup()
        if processed[messageID] != nil {
            return true
        }
        processed[messageID] = Entry(timestamp: Date())
        return false
    }

    /// Content-based dedup: same user, same text within the window.
    func isContentDuplicate(userID: String, text: String) -> Bool {
        let now = Date()
        if let entry = recentContent[userID],
           entry.text == text,
           now.timeIntervalSince(entry.time) < contentDeduWindow {
            return true
        }
        recentContent[userID] = (text: text, time: now)
        return false
    }

    private func cleanup() {
        let cutoff = Date().addingTimeInterval(-ttl)
        processed = processed.filter { $0.value.timestamp > cutoff }
        let contentCutoff = Date().addingTimeInterval(-contentDeduWindow * 2)
        recentContent = recentContent.filter { $0.value.time > contentCutoff }
    }
}
