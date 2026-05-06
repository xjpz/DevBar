import AppKit
import FinderSync

final class PathCopier {

    static func copySelectedPaths() {
        guard let items = FIFinderSyncController.default().selectedItemURLs(),
              !items.isEmpty else {
            NSLog("DevBar: No items selected for path copy")
            return
        }

        let paths = items.map(\.path).joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(paths, forType: .string)
        NSLog("DevBar: Copied \(items.count) path(s) to clipboard")
    }
}
