import Foundation

public enum IOSAppIconOption: String, CaseIterable, Identifiable, Sendable {
    case `default`
    case dockBlue
    case lightBluePurple
    case frostedLilacGray
    case graphiteMono

    public var id: String {
        switch self {
        case .default:
            "default"
        case .dockBlue:
            "dock-blue"
        case .lightBluePurple:
            "light-blue-purple"
        case .frostedLilacGray:
            "frosted-lilac-gray"
        case .graphiteMono:
            "graphite-mono"
        }
    }

    public var displayName: String {
        switch self {
        case .default:
            "Default"
        case .dockBlue:
            "Dock blue"
        case .lightBluePurple:
            "Light blue-purple"
        case .frostedLilacGray:
            "Frosted lilac gray"
        case .graphiteMono:
            "Graphite mono"
        }
    }

    public var alternateIconName: String? {
        switch self {
        case .default:
            nil
        case .dockBlue:
            "AppIconDockBlue"
        case .lightBluePurple:
            "AppIconLightBluePurple"
        case .frostedLilacGray:
            "AppIconFrostedLilacGray"
        case .graphiteMono:
            "AppIconGraphiteMono"
        }
    }

    public var previewAssetName: String {
        switch self {
        case .default:
            "AppIconPreviewDefault"
        case .dockBlue:
            "AppIconPreviewDockBlue"
        case .lightBluePurple:
            "AppIconPreviewLightBluePurple"
        case .frostedLilacGray:
            "AppIconPreviewFrostedLilacGray"
        case .graphiteMono:
            "AppIconPreviewGraphiteMono"
        }
    }

    public static func option(forAlternateIconName alternateIconName: String?) -> IOSAppIconOption {
        allCases.first {
            $0.alternateIconName == alternateIconName
        } ?? .default
    }
}
