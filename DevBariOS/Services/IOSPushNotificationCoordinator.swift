import DevBarCore
import Foundation
import UIKit
import UserNotifications

@MainActor
final class IOSPushNotificationCoordinator: NSObject, UNUserNotificationCenterDelegate {
    static let shared = IOSPushNotificationCoordinator()

    private enum Keys {
        static let apnsToken = "ios.push.apnsToken"
        static let lastRegistration = "ios.push.lastRegistration"
        static let preferences = "ios.push.preferences"
    }

    private let defaults = UserDefaults.standard
    private let service = PushNotificationService.shared

    func requestAuthorization(application: UIApplication) {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
            if let error {
                print("[DevBar:iOSPush] Notification authorization failed: \(error)")
            }
            guard granted else { return }
            Task { @MainActor in
                application.registerForRemoteNotifications()
            }
        }
    }

    func didRegisterForRemoteNotifications(deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        defaults.set(token, forKey: Keys.apnsToken)
        NotificationCenter.default.post(name: .iosAPNsTokenChanged, object: nil)
    }

    func didFailToRegisterForRemoteNotifications(error: Error) {
        print("[DevBar:iOSPush] APNs registration failed: \(error)")
    }

    func syncRegistration(relayDeviceToken: String?) async {
        guard let relayDeviceToken, !relayDeviceToken.isEmpty,
              let apnsToken = defaults.string(forKey: Keys.apnsToken), !apnsToken.isEmpty
        else { return }

        let environment: PushEnvironment
        #if DEBUG
        environment = .development
        #else
        environment = .production
        #endif

        let bundleId = Bundle.main.bundleIdentifier ?? "cc.xjpz.DevBariOS"
        let fingerprint = "\(apnsToken)|\(bundleId)|\(environment.rawValue)|\(relayDeviceToken)"
        guard defaults.string(forKey: Keys.lastRegistration) != fingerprint else { return }

        do {
            _ = try await service.register(
                PushDeviceRegistration(
                    pushToken: apnsToken,
                    bundleId: bundleId,
                    environment: environment,
                    locale: Locale.current.identifier
                ),
                deviceToken: relayDeviceToken
            )
            defaults.set(fingerprint, forKey: Keys.lastRegistration)
        } catch {
            print("[DevBar:iOSPush] Push token sync failed: \(error)")
        }
    }

    func syncPreferences(_ preferences: PushNotificationPreferences, relayDeviceToken: String?) async {
        savePreferences(preferences)
        guard let relayDeviceToken, !relayDeviceToken.isEmpty else { return }
        do {
            _ = try await service.updatePreferences(preferences, deviceToken: relayDeviceToken)
        } catch {
            print("[DevBar:iOSPush] Push preferences sync failed: \(error)")
        }
    }

    func loadPreferences() -> PushNotificationPreferences {
        guard let data = defaults.data(forKey: Keys.preferences),
              let preferences = try? JSONDecoder().decode(PushNotificationPreferences.self, from: data)
        else {
            return PushNotificationPreferences()
        }
        return preferences
    }

    private func savePreferences(_ preferences: PushNotificationPreferences) {
        guard let data = try? JSONEncoder().encode(preferences) else { return }
        defaults.set(data, forKey: Keys.preferences)
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound, .badge]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        await MainActor.run {
            NotificationCenter.default.post(
                name: .iosAgentWatcherNotificationOpened,
                object: nil,
                userInfo: response.notification.request.content.userInfo
            )
        }
    }
}

extension Notification.Name {
    static let iosAPNsTokenChanged = Notification.Name("iosAPNsTokenChanged")
    static let iosAgentWatcherNotificationOpened = Notification.Name("iosAgentWatcherNotificationOpened")
}
