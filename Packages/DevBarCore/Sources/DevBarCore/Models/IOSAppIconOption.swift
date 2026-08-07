import Foundation

public enum IOSAppIconOption: String, CaseIterable, Identifiable, Sendable {
    case smileBlueBorder
    case `default`
    case dockBlue
    case lightBluePurple
    case frostedLilacGray
    case graphiteMono
    case smileBlue

    public static let primaryBundleIconName = "AppIconSmileBlueBorder"

    public var id: String {
        switch self {
        case .smileBlueBorder:
            "smile-blue-border"
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
        case .smileBlue:
            "smile-blue"
        }
    }

    public var displayName: String {
        switch self {
        case .smileBlueBorder:
            "Smile blue border"
        case .default:
            "Original"
        case .dockBlue:
            "Dock blue"
        case .lightBluePurple:
            "Light blue-purple"
        case .frostedLilacGray:
            "Frosted lilac gray"
        case .graphiteMono:
            "Graphite mono"
        case .smileBlue:
            "Smile blue"
        }
    }

    public var alternateIconName: String? {
        switch self {
        case .smileBlueBorder:
            nil
        case .default:
            "AppIcon"
        case .dockBlue:
            "AppIconDockBlue"
        case .lightBluePurple:
            "AppIconLightBluePurple"
        case .frostedLilacGray:
            "AppIconFrostedLilacGray"
        case .graphiteMono:
            "AppIconGraphiteMono"
        case .smileBlue:
            "AppIconSmileBlueV2"
        }
    }

    public var expectedBundleIconName: String {
        alternateIconName ?? Self.primaryBundleIconName
    }

    public var previewAssetName: String {
        switch self {
        case .smileBlueBorder:
            "AppIconPreviewSmileBlueBorder"
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
        case .smileBlue:
            "AppIconPreviewSmileBlue"
        }
    }

    public static func option(forAlternateIconName alternateIconName: String?) -> IOSAppIconOption {
        // Before Smile Blue Border became the primary icon, it was registered under this
        // alternate name. Resolve it to the new primary option so foreground synchronization
        // migrates existing installations back to a nil alternate icon name.
        if alternateIconName == "AppIconSmileBlueBorder" {
            return .smileBlueBorder
        }
        if alternateIconName == "AppIconSmileBlue" || alternateIconName == "AppIconSmileBlueDark" {
            return .smileBlue
        }
        return allCases.first { $0.alternateIconName == alternateIconName } ?? .smileBlueBorder
    }
}
