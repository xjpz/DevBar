import Foundation

public enum TerminalPrivateKeyPassphrasePolicy {
    public static func normalized(_ passphrase: String?) -> String? {
        guard let passphrase else { return nil }
        if passphrase.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return nil
        }
        return passphrase
    }
}
