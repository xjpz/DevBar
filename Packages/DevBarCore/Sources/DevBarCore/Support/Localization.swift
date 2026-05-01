import Foundation

enum CoreL10n {
    static func text(_ key: String.LocalizationValue) -> String {
        String(localized: key, bundle: .main)
    }
}
