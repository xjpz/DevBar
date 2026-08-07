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
        static let legacyAPNsToken = "ios.push.apnsToken"
        static let legacyLastRegistration = "ios.push.lastRegistration"
        static let lastRegistrationSummary = "ios.push.lastRegistrationSummary"
        static let lastLiveActivityPushToStartRegistration = "ios.push.lastLiveActivityPushToStartRegistration"
        static let lastLiveActivityRegistrationPrefix = "ios.push.lastLiveActivityRegistration."
        static let liveActivityPushToStartToken = "ios.push.liveActivityPushToStartToken"
        static let preferences = "ios.push.preferences"
    }

    private let defaults = UserDefaults.standard
    private let service = PushNotificationService.shared
    private var latestRelayDeviceToken: String?
    private var apnsRegistrationState = APNsRegistrationState()
    private var isDrainingAPNsRegistration = false
#if canImport(ActivityKit)
    private var isObservingLiveActivityTokens = false
    private var observedLiveMessageActivityIDs: Set<String> = []
    private var observedQuotaActivityIDs: Set<String> = []
#endif

    private override init() {
        super.init()
        defaults.removeObject(forKey: Keys.legacyAPNsToken)
        defaults.removeObject(forKey: Keys.legacyLastRegistration)
        startLiveActivityTokenObservation()
    }

    func requestAuthorization(application: UIApplication) {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
            let nsError = error as NSError?
            Task { @MainActor in
                if let nsError {
                    DiagnosticLogger.shared.record(
                        level: .error,
                        category: "ios.push.apns",
                        name: "apns_authorization_failed",
                        message: "Notification authorization request failed",
                        details: [
                            "errorDomain": nsError.domain,
                            "errorCode": String(nsError.code),
                        ]
                    )
                    print("[DevBar:iOSPush] Notification authorization failed domain=\(nsError.domain) code=\(nsError.code)")
                }
                guard granted else {
                    DiagnosticLogger.shared.record(
                        level: .warning,
                        category: "ios.push.apns",
                        name: "apns_authorization_not_granted",
                        message: "Notification authorization was not granted"
                    )
                    return
                }
                DiagnosticLogger.shared.record(
                    level: .info,
                    category: "ios.push.apns",
                    name: "apns_authorization_granted",
                    message: "Notification authorization granted; requesting remote notification registration"
                )
                application.registerForRemoteNotifications()
            }
        }
    }

    func didRegisterForRemoteNotifications(deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        let previousFingerprint = apnsRegistrationState.currentAPNsTokenFingerprint
        apnsRegistrationState.receiveCurrentProcessAPNsToken(token)
        let fingerprint = PushTokenFingerprint.make(token)
        DiagnosticLogger.shared.record(
            level: .info,
            category: "ios.push.apns",
            name: "apns_current_process_callback",
            message: "Received APNs device registration callback for current process",
            details: [
                "apnsFingerprint": fingerprint,
                "previousAPNsFingerprint": previousFingerprint ?? "none",
                "fingerprintChanged": String(previousFingerprint != fingerprint),
                "bundleId": Self.bundleIdentifier,
                "environment": Self.pushEnvironment.rawValue,
            ]
        )
        print("[DevBar:iOSPush] Received current-process APNs token fingerprint=\(fingerprint) changed=\(previousFingerprint != fingerprint)")
        NotificationCenter.default.post(name: .iosAPNsTokenChanged, object: nil)
        Task { @MainActor [weak self] in
            await self?.drainAPNsRegistration()
        }
    }

    func didFailToRegisterForRemoteNotifications(error: Error) {
        let nsError = error as NSError
        DiagnosticLogger.shared.record(
            level: .error,
            category: "ios.push.apns",
            name: "apns_system_registration_failed",
            message: "System failed to register for remote notifications",
            details: [
                "errorDomain": nsError.domain,
                "errorCode": String(nsError.code),
                "bundleId": Self.bundleIdentifier,
                "environment": Self.pushEnvironment.rawValue,
            ]
        )
        print("[DevBar:iOSPush] APNs registration failed domain=\(nsError.domain) code=\(nsError.code)")
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
        apnsRegistrationState.updateRegistrationContext(
            bundleID: Self.bundleIdentifier,
            environment: Self.pushEnvironment,
            locale: Locale.current.identifier
        )
        apnsRegistrationState.updateRelayDeviceToken(relayDeviceToken)
        if force {
            apnsRegistrationState.requestForcedRegistration()
        }
        DiagnosticLogger.shared.record(
            level: .info,
            category: "ios.push.apns",
            name: "apns_registration_sync_requested",
            message: "APNs registration synchronization requested",
            endpoint: DevBarCoreConstants.PushNotifications.registerPath,
            details: [
                "force": String(force),
                "hasCurrentProcessCallback": String(apnsRegistrationState.hasCurrentProcessAPNsToken),
                "hasRelayCredential": String(relayDeviceToken?.isEmpty == false),
                "registrationInFlight": String(apnsRegistrationState.isRegistrationInFlight),
                "bundleId": Self.bundleIdentifier,
                "environment": Self.pushEnvironment.rawValue,
            ]
        )
        await drainAPNsRegistration()
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
            apnsTokenFingerprint: apnsRegistrationState.currentAPNsTokenFingerprint,
            hasCurrentProcessAPNsToken: apnsRegistrationState.hasCurrentProcessAPNsToken,
            liveActivityPushToStartToken: defaults.string(forKey: Keys.liveActivityPushToStartToken),
            lastPushRegistration: defaults.string(forKey: Keys.lastRegistrationSummary),
            lastLiveActivityPushToStartRegistration: defaults.string(forKey: Keys.lastLiveActivityPushToStartRegistration)
        )
    }

    private func drainAPNsRegistration() async {
        guard !isDrainingAPNsRegistration else {
            DiagnosticLogger.shared.record(
                level: .info,
                category: "ios.push.apns",
                name: "apns_registration_drain_coalesced",
                message: "APNs registration drain request coalesced with active drain",
                endpoint: DevBarCoreConstants.PushNotifications.registerPath,
                details: [
                    "registrationInFlight": String(apnsRegistrationState.isRegistrationInFlight),
                ]
            )
            return
        }
        isDrainingAPNsRegistration = true
        defer { isDrainingAPNsRegistration = false }

        while let attempt = apnsRegistrationState.beginNextAttempt() {
            let startedAt = Date()
            DiagnosticLogger.shared.record(
                level: .info,
                category: "ios.push.apns",
                name: "apns_registration_attempt_started",
                message: "APNs registration request started",
                endpoint: DevBarCoreConstants.PushNotifications.registerPath,
                details: [
                    "attemptId": String(attempt.id),
                    "apnsFingerprint": attempt.apnsTokenFingerprint,
                    "relayFingerprint": attempt.relayTokenFingerprint,
                    "bundleId": attempt.registration.bundleId,
                    "environment": attempt.registration.environment.rawValue,
                ]
            )
            do {
                _ = try await service.register(
                    attempt.registration,
                    deviceToken: attempt.relayDeviceToken
                )
                let durationMs = Int64(Date().timeIntervalSince(startedAt) * 1_000)
                let registeredAt = ISO8601DateFormatter().string(from: Date())
                defaults.set(
                    "apns:\(attempt.apnsTokenFingerprint)|relay:\(attempt.relayTokenFingerprint)|" +
                        "\(attempt.registration.bundleId)|\(attempt.registration.environment.rawValue)|\(registeredAt)",
                    forKey: Keys.lastRegistrationSummary
                )
                await syncLiveActivityPushToStart(
                    relayDeviceToken: attempt.relayDeviceToken,
                    force: false
                )
                apnsRegistrationState.complete(attempt, succeeded: true)
                DiagnosticLogger.shared.record(
                    level: .info,
                    category: "ios.push.apns",
                    name: "apns_registration_attempt_succeeded",
                    message: "APNs registration request succeeded",
                    endpoint: DevBarCoreConstants.PushNotifications.registerPath,
                    durationMs: durationMs,
                    details: [
                        "attemptId": String(attempt.id),
                        "apnsFingerprint": attempt.apnsTokenFingerprint,
                        "relayFingerprint": attempt.relayTokenFingerprint,
                        "bundleId": attempt.registration.bundleId,
                        "environment": attempt.registration.environment.rawValue,
                    ]
                )
                print("[DevBar:iOSPush] Push registration succeeded attempt=\(attempt.id) apns=\(attempt.apnsTokenFingerprint) relay=\(attempt.relayTokenFingerprint) durationMs=\(durationMs)")
            } catch {
                let durationMs = Int64(Date().timeIntervalSince(startedAt) * 1_000)
                let nsError = error as NSError
                apnsRegistrationState.complete(attempt, succeeded: false)
                DiagnosticLogger.shared.record(
                    level: .error,
                    category: "ios.push.apns",
                    name: "apns_registration_attempt_failed",
                    message: "APNs registration request failed",
                    endpoint: DevBarCoreConstants.PushNotifications.registerPath,
                    durationMs: durationMs,
                    details: [
                        "attemptId": String(attempt.id),
                        "apnsFingerprint": attempt.apnsTokenFingerprint,
                        "relayFingerprint": attempt.relayTokenFingerprint,
                        "bundleId": attempt.registration.bundleId,
                        "environment": attempt.registration.environment.rawValue,
                        "errorDomain": nsError.domain,
                        "errorCode": String(nsError.code),
                        "errorType": String(reflecting: type(of: error)),
                    ]
                )
                print("[DevBar:iOSPush] Push registration failed attempt=\(attempt.id) apns=\(attempt.apnsTokenFingerprint) relay=\(attempt.relayTokenFingerprint) domain=\(nsError.domain) code=\(nsError.code) durationMs=\(durationMs)")
            }
        }
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
    let apnsTokenFingerprint: String?
    let hasCurrentProcessAPNsToken: Bool
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
