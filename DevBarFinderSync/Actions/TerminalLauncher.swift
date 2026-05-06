import Foundation
import AppKit

final class TerminalLauncher {

    static func open(at directory: URL, using app: TerminalApp) {
        let bundleID = app.bundleIdentifier
        let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)

        guard let appURL = appURL else {
            NSLog("DevBar: \(app.displayName) not found")
            return
        }

        let config = NSWorkspace.OpenConfiguration()
        config.arguments = []

        NSWorkspace.shared.open(
            [directory],
            withApplicationAt: appURL,
            configuration: config
        ) { _, error in
            if let error = error {
                NSLog("DevBar: Failed to open terminal: \(error.localizedDescription)")
            }
        }
    }
}
