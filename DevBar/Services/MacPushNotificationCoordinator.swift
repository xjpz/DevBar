import AppKit
import DevBarCore
import Foundation
import UserNotifications

@MainActor
final class MacPushNotificationCoordinator: NSObject, UNUserNotificationCenterDelegate {
    static let shared = MacPushNotificationCoordinator()

    private enum Keys {
        static let apnsToken = "mac.push.apnsToken"
        static let lastRegistration = "mac.push.lastRegistration"
    }

    private let defaults = UserDefaults.standard
    private let service = PushNotificationService.shared

    private override init() {
        super.init()
    }

    func requestAuthorization() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
            if let error {
                print("[DevBar:MacPush] Notification authorization failed: \(error)")
            }
            guard granted else { return }
            Task { @MainActor in
                NSApplication.shared.registerForRemoteNotifications()
            }
        }
    }

    func didRegisterForRemoteNotifications(deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        defaults.set(token, forKey: Keys.apnsToken)
        NotificationCenter.default.post(name: .macAPNsTokenChanged, object: nil)
    }

    func didFailToRegisterForRemoteNotifications(error: Error) {
        print("[DevBar:MacPush] APNs registration failed: \(error)")
    }

    func syncRegistration(relayDeviceToken: String?) async {
        guard let relayDeviceToken, !relayDeviceToken.isEmpty,
              let apnsToken = defaults.string(forKey: Keys.apnsToken), !apnsToken.isEmpty
        else { return }

        let registration = PushDeviceRegistration(
            pushToken: apnsToken,
            bundleId: Self.bundleIdentifier,
            environment: Self.pushEnvironment,
            locale: Locale.current.identifier
        )
        let fingerprint = "\(apnsToken)|\(registration.bundleId)|\(registration.environment.rawValue)|\(relayDeviceToken)"
        guard defaults.string(forKey: Keys.lastRegistration) != fingerprint else { return }

        do {
            _ = try await service.register(registration, deviceToken: relayDeviceToken)
            defaults.set(fingerprint, forKey: Keys.lastRegistration)
        } catch {
            print("[DevBar:MacPush] Push token sync failed: \(error)")
        }
    }

    static var bundleIdentifier: String {
        Bundle.main.bundleIdentifier ?? "cc.xjpz.DevBar"
    }

    static var pushEnvironment: PushEnvironment {
        #if DEBUG
        .development
        #else
        .production
        #endif
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound, .badge]
    }
}

final class MacAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        MacPushNotificationCoordinator.shared.requestAuthorization()
    }

    func application(_ application: NSApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        MacPushNotificationCoordinator.shared.didRegisterForRemoteNotifications(deviceToken: deviceToken)
    }

    func application(_ application: NSApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        MacPushNotificationCoordinator.shared.didFailToRegisterForRemoteNotifications(error: error)
    }
}

extension Notification.Name {
    static let macAPNsTokenChanged = Notification.Name("macAPNsTokenChanged")
}
