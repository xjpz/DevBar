import Foundation

enum TerminalApp: String, CaseIterable, Identifiable {
    case terminal = "Terminal"
    case iterm = "iTerm"

    var id: String { rawValue }

    var bundleIdentifier: String {
        switch self {
        case .terminal: return "com.apple.Terminal"
        case .iterm:    return "com.googlecode.iterm2"
        }
    }

    var displayName: String { rawValue }
}

final class FinderSyncPreferences {
    static let shared = FinderSyncPreferences()

    private let defaults: UserDefaults

    init() {
        defaults = UserDefaults(suiteName: "group.cc.xjpz.DevBar") ?? .standard
    }

    var preferredTerminal: TerminalApp {
        get {
            TerminalApp(rawValue: defaults.string(forKey: "finder_preferredTerminal") ?? "") ?? .terminal
        }
        set { defaults.set(newValue.rawValue, forKey: "finder_preferredTerminal") }
    }

    var enableTxt: Bool {
        get { defaults.object(forKey: "finder_enableTxt") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "finder_enableTxt") }
    }

    var enableSh: Bool {
        get { defaults.object(forKey: "finder_enableSh") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "finder_enableSh") }
    }

    var enableMd: Bool {
        get { defaults.object(forKey: "finder_enableMd") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "finder_enableMd") }
    }

    var enableDocx: Bool {
        get { defaults.object(forKey: "finder_enableDocx") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "finder_enableDocx") }
    }

    var enableXlsx: Bool {
        get { defaults.object(forKey: "finder_enableXlsx") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "finder_enableXlsx") }
    }

    var enablePptx: Bool {
        get { defaults.object(forKey: "finder_enablePptx") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "finder_enablePptx") }
    }

    var enableCopyPath: Bool {
        get { defaults.object(forKey: "finder_enableCopyPath") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "finder_enableCopyPath") }
    }
}
