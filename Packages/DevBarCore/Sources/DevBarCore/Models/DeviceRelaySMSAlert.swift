import CryptoKit
import Foundation

public enum DeviceRelaySMSAlert {
    public static let source = "shortcuts.messageAutomation"

    public static func summary(for messageText: String, limit: Int = 240) -> String {
        let trimmed = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > limit else { return trimmed }
        return String(trimmed.prefix(max(0, limit))) + "..."
    }

    public static func dedupKey(sender: String?, messageText: String, receivedAt: Int64) -> String {
        let minuteBucket = receivedAt / 60_000
        let rawValue = [
            normalized(sender),
            normalized(messageText),
            "\(minuteBucket)",
        ].joined(separator: "|")
        let digest = SHA256.hash(data: Data(rawValue.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func normalized(_ value: String?) -> String {
        value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}
