import Foundation

public struct IOSToolVisibilityStore {
    private let defaults: UserDefaults
    private let key: String

    public init(defaults: UserDefaults = .standard, key: String = "ios.tools.hiddenIDs") {
        self.defaults = defaults
        self.key = key
    }

    public func load() -> [String] {
        defaults.stringArray(forKey: key) ?? []
    }

    public func save(_ ids: [String]) {
        defaults.set(ids, forKey: key)
    }
}
