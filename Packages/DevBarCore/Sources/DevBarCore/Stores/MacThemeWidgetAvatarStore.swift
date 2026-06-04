import Foundation

public struct MacThemeWidgetAvatarStore: Sendable {
    public enum StoreError: Error {
        case appGroupContainerUnavailable
    }

    private let containerURL: URL?

    public init(
        containerURL: URL? = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: DevBarCoreConstants.AppGroup.groupID
        )
    ) {
        self.containerURL = containerURL
    }

    @discardableResult
    public func save(_ data: Data) throws -> String {
        guard let avatarURL else {
            throw StoreError.appGroupContainerUnavailable
        }
        try data.write(to: avatarURL, options: .atomic)
        return avatarURL.lastPathComponent
    }

    public func load(fileName: String?) -> Data? {
        guard let fileURL = fileURL(for: fileName) else { return nil }
        return try? Data(contentsOf: fileURL)
    }

    public func clear(fileName: String? = DevBarCoreConstants.AppGroup.macThemeWidgetAvatarFileName) {
        guard let fileURL = fileURL(for: fileName) else { return }
        try? FileManager.default.removeItem(at: fileURL)
    }

    private var avatarURL: URL? {
        fileURL(for: DevBarCoreConstants.AppGroup.macThemeWidgetAvatarFileName)
    }

    private func fileURL(for fileName: String?) -> URL? {
        guard let containerURL, let fileName, !fileName.isEmpty else { return nil }
        return containerURL.appendingPathComponent(fileName, isDirectory: false)
    }
}
