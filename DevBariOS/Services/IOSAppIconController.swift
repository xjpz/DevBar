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
            let actualOption = IOSAppIconOption.option(forAlternateIconName: UIApplication.shared.alternateIconName)
            if defaults.string(forKey: key) != actualOption.id {
                defaults.set(actualOption.id, forKey: key)
            }
            return actualOption
        }
        set {
            defaults.set(newValue.id, forKey: key)
        }
    }

    func synchronizePreferredIcon(
        traceId: String = UUID().uuidString
    ) {
        guard UIApplication.shared.supportsAlternateIcons else { return }
        apply(preferredOption, traceId: traceId) { _ in }
    }

    func apply(
        _ option: IOSAppIconOption,
        traceId: String = UUID().uuidString,
        completion: @escaping (Error?) -> Void
    ) {
        let currentIconName = UIApplication.shared.alternateIconName
        let desiredIconName = option.alternateIconName
        let supportsAlternateIcons = UIApplication.shared.supportsAlternateIcons

        logAppIconEvent(
            level: .info,
            name: "ios_app_icon_apply_requested",
            message: "iOS app icon change requested",
            traceId: traceId,
            option: option,
            currentIconName: currentIconName,
            desiredIconName: desiredIconName,
            details: iconRegistrationDetails(for: option, desiredIconName: desiredIconName).merging([
                "supportsAlternateIcons": String(supportsAlternateIcons),
                "registeredAlternateIcons": registeredAlternateIconNames().joined(separator: ","),
                "registeredCurrentIconName": registeredIconName(forIconName: currentIconName) ?? "<missing>",
                "applicationState": applicationStateDescription,
            ]) { _, newValue in newValue }
        )

        guard UIApplication.shared.supportsAlternateIcons else {
            logAppIconEvent(
                level: .warning,
                name: "ios_app_icon_apply_skipped",
                message: "iOS alternate app icons are not supported",
                traceId: traceId,
                option: option,
                currentIconName: currentIconName,
                desiredIconName: desiredIconName
            )
            completion(nil)
            return
        }

        guard currentIconName != desiredIconName else {
            preferredOption = option
            logAppIconEvent(
                level: .info,
                name: "ios_app_icon_apply_noop",
                message: "Requested iOS app icon is already active",
                traceId: traceId,
                option: option,
                currentIconName: currentIconName,
                desiredIconName: desiredIconName
            )
            completion(nil)
            return
        }

        UIApplication.shared.setAlternateIconName(desiredIconName) { error in
            Task { @MainActor in
                if let error {
                    Self.shared.logAppIconError(
                        error,
                        traceId: traceId,
                        option: option,
                        requestedCurrentIconName: currentIconName,
                        desiredIconName: desiredIconName
                    )
                } else {
                    Self.shared.preferredOption = option
                    Self.shared.logAppIconEvent(
                        level: .info,
                        name: "ios_app_icon_apply_succeeded",
                        message: "iOS app icon change succeeded",
                        traceId: traceId,
                        option: option,
                        currentIconName: UIApplication.shared.alternateIconName,
                        desiredIconName: desiredIconName
                    )
                }
                completion(error)
            }
        }
    }

    private var applicationStateDescription: String {
        switch UIApplication.shared.applicationState {
        case .active:
            "active"
        case .inactive:
            "inactive"
        case .background:
            "background"
        @unknown default:
            "unknown"
        }
    }

    private func registeredAlternateIconNames() -> [String] {
        alternateIconDictionary().keys.sorted()
    }

    private func registeredIconName(forIconName iconName: String?) -> String? {
        guard let iconName else {
            return primaryIconDictionary()["CFBundleIconName"] as? String
        }
        guard let iconInfo = alternateIconDictionary()[iconName] as? [String: Any] else { return nil }
        return iconInfo["CFBundleIconName"] as? String
    }

    private func registeredIconName(for option: IOSAppIconOption) -> String? {
        return registeredIconName(forIconName: option.alternateIconName)
    }

    private func registeredIconFiles(forIconName iconName: String?) -> [String] {
        let iconInfo: [String: Any]
        if iconName == nil {
            iconInfo = primaryIconDictionary()
        } else if let iconName,
                  let alternateInfo = alternateIconDictionary()[iconName] as? [String: Any] {
            iconInfo = alternateInfo
        } else {
            return []
        }

        return iconInfo["CFBundleIconFiles"] as? [String] ?? []
    }

    private func alternateIconDictionary() -> [String: Any] {
        guard let icons = Bundle.main.infoDictionary?["CFBundleIcons"] as? [String: Any],
              let alternateIcons = icons["CFBundleAlternateIcons"] as? [String: Any] else { return [:] }
        return alternateIcons
    }

    private func primaryIconDictionary() -> [String: Any] {
        guard let icons = Bundle.main.infoDictionary?["CFBundleIcons"] as? [String: Any],
              let primaryIcon = icons["CFBundlePrimaryIcon"] as? [String: Any] else { return [:] }
        return primaryIcon
    }

    private func iconRegistrationDetails(for option: IOSAppIconOption, desiredIconName: String?) -> [String: String] {
        let primaryIconFiles = registeredIconFiles(forIconName: nil)
        let desiredIconFiles = registeredIconFiles(forIconName: desiredIconName)

        return [
            "expectedBundleIconName": desiredIconName ?? "AppIcon",
            "registeredDesiredIconName": registeredIconName(forIconName: desiredIconName) ?? "<missing>",
            "registeredDesiredIconFiles": iconFilesDescription(desiredIconFiles),
            "desiredIconResources": iconResourceStatusDescription(desiredIconFiles),
            "primaryIconName": registeredIconName(for: .smileBlueBorder) ?? "<missing>",
            "primaryIconFiles": iconFilesDescription(primaryIconFiles),
            "primaryIconResources": iconResourceStatusDescription(primaryIconFiles),
            "assetsCatalogExists": String(Bundle.main.path(forResource: "Assets", ofType: "car") != nil),
            "bundlePath": Bundle.main.bundlePath,
        ]
    }

    private func iconFilesDescription(_ iconFiles: [String]) -> String {
        iconFiles.isEmpty ? "<none>" : iconFiles.joined(separator: ",")
    }

    private func iconResourceStatusDescription(_ iconFiles: [String]) -> String {
        guard !iconFiles.isEmpty else { return "<none>" }
        return iconFiles.map { iconFile in
            let candidates = [
                "\(iconFile).png",
                "\(iconFile)@2x.png",
                "\(iconFile)@3x.png",
            ]
            let exists = candidates.contains { candidate in
                Bundle.main.path(forResource: candidate, ofType: nil) != nil
            }
            return "\(iconFile)=\(exists)"
        }
        .joined(separator: ",")
    }

    private func logAppIconError(
        _ error: Error,
        traceId: String,
        option: IOSAppIconOption,
        requestedCurrentIconName: String?,
        desiredIconName: String?
    ) {
        let nsError = error as NSError
        var details = [
            "errorDomain": nsError.domain,
            "errorCode": String(nsError.code),
            "errorDescription": nsError.localizedDescription,
            "errorUserInfoKeys": nsError.userInfo.keys.map(String.init(describing:)).sorted().joined(separator: ","),
            "actualIconAfterFailure": UIApplication.shared.alternateIconName ?? "<default>",
            "requestedCurrentIconName": requestedCurrentIconName ?? "<default>",
            "registeredAlternateIcons": registeredAlternateIconNames().joined(separator: ","),
            "applicationState": applicationStateDescription,
        ].merging(iconRegistrationDetails(for: option, desiredIconName: desiredIconName)) { _, newValue in newValue }
        if let failureReason = nsError.localizedFailureReason {
            details["failureReason"] = failureReason
        }
        if let recoverySuggestion = nsError.localizedRecoverySuggestion {
            details["recoverySuggestion"] = recoverySuggestion
        }
        details.merge(errorUserInfoDetails(nsError)) { _, newValue in newValue }

        logAppIconEvent(
            level: .error,
            name: "ios_app_icon_apply_failed",
            message: "iOS app icon change failed",
            traceId: traceId,
            option: option,
            currentIconName: UIApplication.shared.alternateIconName,
            desiredIconName: desiredIconName,
            details: details
        )
    }

    private func errorUserInfoDetails(_ nsError: NSError) -> [String: String] {
        var details: [String: String] = [:]
        for key in ["_LSFile", "_LSFunction", "_LSLine"] {
            if let value = nsError.userInfo[key] {
                details["errorUserInfo.\(key)"] = String(describing: value)
            }
        }
        if let underlyingError = nsError.userInfo[NSUnderlyingErrorKey] as? NSError {
            details["underlyingErrorDomain"] = underlyingError.domain
            details["underlyingErrorCode"] = String(underlyingError.code)
            details["underlyingErrorDescription"] = underlyingError.localizedDescription
        }
        return details
    }

    private func logAppIconEvent(
        level: DiagnosticLogLevel,
        name: String,
        message: String,
        traceId: String,
        option: IOSAppIconOption,
        currentIconName: String?,
        desiredIconName: String?,
        details: [String: String] = [:]
    ) {
        var mergedDetails = details
        mergedDetails["optionId"] = option.id
        mergedDetails["optionDisplayName"] = option.displayName
        mergedDetails["currentAlternateIconName"] = currentIconName ?? "<default>"
        mergedDetails["desiredAlternateIconName"] = desiredIconName ?? "<default>"
        mergedDetails["bundleIdentifier"] = Bundle.main.bundleIdentifier ?? "<unknown>"

        DiagnosticLogger.shared.record(
            level: level,
            category: "ios.appIcon",
            name: name,
            message: message,
            traceId: traceId,
            tags: ["app-icon"],
            details: mergedDetails
        )

        NSLog("[DevBar][AppIcon][%@] %@ %@", traceId, name, mergedDetails.description)
    }
}
