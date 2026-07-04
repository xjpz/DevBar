import Foundation

public struct IOSToolTabStore {
    private let defaults: UserDefaults
    private let key: String

    public init(defaults: UserDefaults = .standard, key: String = "ios.tools.pinnedTabs") {
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
