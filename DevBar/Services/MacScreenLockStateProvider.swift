import CoreGraphics
import Foundation

enum MacScreenLockStateProvider {
    static func isScreenLocked() -> Bool {
        guard let session = CGSessionCopyCurrentDictionary() as? [String: Any] else {
            return false
        }
        return session["CGSSessionScreenIsLocked"] as? Bool ?? false
    }
}

enum MacDisplayStateProvider {
    static func isDisplayAwake() -> Bool {
        CGDisplayIsAsleep(CGMainDisplayID()) == 0
    }
}
