import DevBarCore
import Foundation
import UIKit
import UserNotifications
#if canImport(ActivityKit)
import ActivityKit
#endif

@MainActor
final class IOSPushNotificationCoordinator: NSObject, UNUserNotificationCenterDelegate {
    static let shared = IOSPushNotificationCoordinator()

    private enum Keys {
        static let apnsToken = "ios.push.apnsToken"
        static let lastRegistration = "ios.push.lastRegistration"
        static let lastLiveActivityPushToStartRegistration = "ios.push.lastLiveActivityPushToStartRegistration"
        static let lastLiveActivityRegistrationPrefix = "ios.push.lastLiveActivityRegistration."
        static let liveActivityPushToStartToken = "ios.push.liveActivityPushToStartToken"
        static let preferences = "ios.push.preferences"
    }

    private let defaults = UserDefaults.standard
    private let service = PushNotificationService.shared
    private var latestRelayDeviceToken: String?
#if canImport(ActivityKit)
    private var isObservingLiveActivityTokens = false
    private var observedLiveMessageActivityIDs: Set<String> = []
    private var observedQuotaActivityIDs: Set<String> = []
#endif

    private override init() {
        super.init()
        startLiveActivityTokenObservation()
    }

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

    func clearApplicationBadge() {
        UNUserNotificationCenter.current().setBadgeCount(0) { error in
            if let error {
                print("[DevBar:iOSPush] Clear badge failed: \(error)")
            }
        }
    }

    func syncRegistration(relayDeviceToken: String?, force: Bool = false) async {
        latestRelayDeviceToken = relayDeviceToken
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
        guard force || defaults.string(forKey: Keys.lastRegistration) != fingerprint else { return }

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
            await syncLiveActivityPushToStart(relayDeviceToken: relayDeviceToken, force: force)
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

    func debugSnapshot() -> IOSPushNotificationDebugSnapshot {
        IOSPushNotificationDebugSnapshot(
            apnsToken: defaults.string(forKey: Keys.apnsToken),
            liveActivityPushToStartToken: defaults.string(forKey: Keys.liveActivityPushToStartToken),
            lastPushRegistration: defaults.string(forKey: Keys.lastRegistration),
            lastLiveActivityPushToStartRegistration: defaults.string(forKey: Keys.lastLiveActivityPushToStartRegistration)
        )
    }

    private func savePreferences(_ preferences: PushNotificationPreferences) {
        guard let data = try? JSONEncoder().encode(preferences) else { return }
        defaults.set(data, forKey: Keys.preferences)
    }

    func syncLiveActivityPushToStart(relayDeviceToken: String?, force: Bool = false) async {
        latestRelayDeviceToken = relayDeviceToken
        guard let relayDeviceToken, !relayDeviceToken.isEmpty,
              let token = defaults.string(forKey: Keys.liveActivityPushToStartToken), !token.isEmpty
        else { return }

        let registration = LiveActivityPushToStartRegistration(
            activityType: .devBarLiveMessage,
            pushToStartToken: token,
            bundleId: Self.bundleIdentifier,
            environment: Self.pushEnvironment,
            minimumIOSVersion: "17.2"
        )
        let fingerprint = "\(token)|\(registration.bundleId)|\(registration.environment.rawValue)|\(relayDeviceToken)"
        guard force || defaults.string(forKey: Keys.lastLiveActivityPushToStartRegistration) != fingerprint else { return }

        do {
            _ = try await service.registerLiveActivityPushToStart(registration, deviceToken: relayDeviceToken)
            defaults.set(fingerprint, forKey: Keys.lastLiveActivityPushToStartRegistration)
        } catch {
            print("[DevBar:iOSPush] Live Activity push-to-start sync failed: \(error)")
        }
    }

    func syncLiveActivityRegistration(_ registration: LiveActivityPushRegistration, relayDeviceToken: String?) async {
        latestRelayDeviceToken = relayDeviceToken
        guard let relayDeviceToken, !relayDeviceToken.isEmpty else { return }

        let registrationFingerprint = (try? JSONEncoder().encode(registration).base64EncodedString()) ?? registration.activityPushToken
        let fingerprint = "\(registrationFingerprint)|\(relayDeviceToken)"
        let key = Keys.lastLiveActivityRegistrationPrefix + registration.activityId
        guard defaults.string(forKey: key) != fingerprint else { return }

        do {
            _ = try await service.registerLiveActivity(registration, deviceToken: relayDeviceToken)
            defaults.set(fingerprint, forKey: key)
        } catch {
            print("[DevBar:iOSPush] Live Activity update token sync failed: \(error)")
        }
    }

    func unregisterLiveActivity(activityId: String, relayDeviceToken: String?) async {
        latestRelayDeviceToken = relayDeviceToken
        guard let relayDeviceToken, !relayDeviceToken.isEmpty else { return }

        do {
            _ = try await service.unregisterLiveActivity(
                activityId: activityId,
                deviceToken: relayDeviceToken
            )
            defaults.removeObject(forKey: Keys.lastLiveActivityRegistrationPrefix + activityId)
        } catch {
            print("[DevBar:iOSPush] Live Activity unregister failed: \(error)")
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

    private func startLiveActivityTokenObservation() {
        #if canImport(ActivityKit)
        guard !isObservingLiveActivityTokens else { return }
        isObservingLiveActivityTokens = true

        if #available(iOS 17.2, *) {
            Task { @MainActor [weak self] in
                guard let self else { return }
                for await tokenData in Activity<DevBarLiveMessageActivityAttributes>.pushToStartTokenUpdates {
                    let token = tokenData.hexString
                    self.defaults.set(token, forKey: Keys.liveActivityPushToStartToken)
                    NotificationCenter.default.post(name: .iosLiveActivityPushToStartTokenChanged, object: nil)
                    await self.syncLiveActivityPushToStart(relayDeviceToken: self.latestRelayDeviceToken)
                }
            }
        }

        Task { @MainActor [weak self] in
            guard let self else { return }
            for activity in Activity<DevBarLiveMessageActivityAttributes>.activities {
                self.observeLiveMessageActivityUpdateTokens(activity)
            }
            for await activity in Activity<DevBarLiveMessageActivityAttributes>.activityUpdates {
                self.observeLiveMessageActivityUpdateTokens(activity)
            }
        }

        Task { @MainActor [weak self] in
            guard let self else { return }
            for activity in Activity<DevBarQuotaActivityAttributes>.activities {
                self.observeQuotaActivityUpdateTokens(activity)
            }
            for await activity in Activity<DevBarQuotaActivityAttributes>.activityUpdates {
                self.observeQuotaActivityUpdateTokens(activity)
            }
        }
        #endif
    }

    #if canImport(ActivityKit)
    private func observeLiveMessageActivityUpdateTokens(_ activity: Activity<DevBarLiveMessageActivityAttributes>) {
        guard observedLiveMessageActivityIDs.insert(activity.id).inserted else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            if let pushToken = activity.pushToken {
                await self.syncLiveActivityRegistration(
                    LiveActivityPushRegistration(
                        activityId: activity.id,
                        activityType: .devBarLiveMessage,
                        activityPushToken: pushToken.hexString,
                        bundleId: Self.bundleIdentifier,
                        environment: Self.pushEnvironment,
                        startedBy: .remote
                    ),
                    relayDeviceToken: self.latestRelayDeviceToken
                )
            }
            for await tokenData in activity.pushTokenUpdates {
                await self.syncLiveActivityRegistration(
                    LiveActivityPushRegistration(
                        activityId: activity.id,
                        activityType: .devBarLiveMessage,
                        activityPushToken: tokenData.hexString,
                        bundleId: Self.bundleIdentifier,
                        environment: Self.pushEnvironment,
                        startedBy: .remote
                    ),
                    relayDeviceToken: self.latestRelayDeviceToken
                )
            }
        }
    }

    private func observeQuotaActivityUpdateTokens(_ activity: Activity<DevBarQuotaActivityAttributes>) {
        guard observedQuotaActivityIDs.insert(activity.id).inserted else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            if let registration = IOSLiveActivityManager.registration(for: activity) {
                await self.syncLiveActivityRegistration(
                    registration,
                    relayDeviceToken: self.latestRelayDeviceToken
                )
            }
            for await _ in activity.pushTokenUpdates {
                guard let registration = IOSLiveActivityManager.registration(for: activity) else { continue }
                await self.syncLiveActivityRegistration(
                    registration,
                    relayDeviceToken: self.latestRelayDeviceToken
                )
            }
        }
    }
    #endif

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        DispatchQueue.main.async {
            completionHandler([.banner, .list, .sound])
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = NotificationUserInfo(response.notification.request.content.userInfo)
        let actionIdentifier = response.actionIdentifier
        DispatchQueue.main.async {
            defer { completionHandler() }
            guard actionIdentifier == UNNotificationDefaultActionIdentifier else { return }

            if let messageId = userInfo.value["messageId"] as? String, !messageId.isEmpty {
                NotificationCenter.default.post(
                    name: .iosDevBarMessageNotificationOpened,
                    object: nil,
                    userInfo: ["messageId": messageId]
                )
            }

            if let rawURL = userInfo.value["url"] as? String,
               let url = PushNotificationURLPolicy.validatedURL(from: rawURL) {
                UIApplication.shared.open(url)
                return
            }

            guard DevBarCoreConstants.Features.agentWatcherEnabled else { return }
            NotificationCenter.default.post(
                name: .iosAgentWatcherNotificationOpened,
                object: nil,
                userInfo: userInfo.value
            )
        }
    }
}

private struct NotificationUserInfo: @unchecked Sendable {
    let value: [AnyHashable: Any]

    init(_ value: [AnyHashable: Any]) {
        self.value = value
    }
}

struct IOSPushNotificationDebugSnapshot {
    let apnsToken: String?
    let liveActivityPushToStartToken: String?
    let lastPushRegistration: String?
    let lastLiveActivityPushToStartRegistration: String?
}

extension Notification.Name {
    static let iosAPNsTokenChanged = Notification.Name("iosAPNsTokenChanged")
    static let iosAgentWatcherNotificationOpened = Notification.Name("iosAgentWatcherNotificationOpened")
    static let iosDevBarMessageNotificationOpened = Notification.Name("iosDevBarMessageNotificationOpened")
    static let iosLiveActivityPushToStartTokenChanged = Notification.Name("iosLiveActivityPushToStartTokenChanged")
}

private extension Data {
    var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}
