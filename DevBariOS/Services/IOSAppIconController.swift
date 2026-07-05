import DevBarCore
import UIKit

@MainActor
final class IOSAppIconController {
    static let shared = IOSAppIconController()

    private let defaults: UserDefaults
    private let key = "ios.appIcon.preferredOption"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var preferredOption: IOSAppIconOption {
        get {
            guard let id = defaults.string(forKey: key),
                  let option = IOSAppIconOption.allCases.first(where: { $0.id == id }) else {
                return IOSAppIconOption.option(forAlternateIconName: UIApplication.shared.alternateIconName)
            }
            return option
        }
        set {
            defaults.set(newValue.id, forKey: key)
        }
    }

    func migrateLegacyDarkIconIfNeeded() {
        guard UIApplication.shared.supportsAlternateIcons,
              let currentIconName = UIApplication.shared.alternateIconName,
              let lightIconName = legacyLightIconName(for: currentIconName) else { return }

        UIApplication.shared.setAlternateIconName(lightIconName)
    }

    func apply(_ option: IOSAppIconOption) {
        guard UIApplication.shared.supportsAlternateIcons else { return }

        preferredOption = option

        let desiredIconName = option.alternateIconName
        guard UIApplication.shared.alternateIconName != desiredIconName else { return }

        UIApplication.shared.setAlternateIconName(desiredIconName)
    }

    private func legacyLightIconName(for iconName: String) -> String? {
        switch iconName {
        case "AppIconLightBluePurpleDark":
            "AppIconLightBluePurple"
        case "AppIconFrostedLilacGrayDark":
            "AppIconFrostedLilacGray"
        case "AppIconGraphiteMonoDark":
            "AppIconGraphiteMono"
        default:
            nil
        }
    }
}
