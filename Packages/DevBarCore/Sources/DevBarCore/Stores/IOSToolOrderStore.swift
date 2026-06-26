import Foundation

public struct IOSToolOrderStore {
    private let defaults: UserDefaults
    private let key: String

    public init(defaults: UserDefaults = .standard, key: String = "ios.tools.customOrder") {
        self.defaults = defaults
        self.key = key
    }

    public func load() -> [String] {
        defaults.stringArray(forKey: key) ?? []
    }

    public func save(_ order: [String]) {
        defaults.set(order, forKey: key)
    }
}
