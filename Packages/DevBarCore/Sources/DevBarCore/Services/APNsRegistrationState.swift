import Crypto
import Foundation

public struct APNsRegistrationAttempt: Sendable, Equatable {
    public let id: UInt64
    public let registration: PushDeviceRegistration
    public let relayDeviceToken: String

    public var apnsTokenFingerprint: String {
        PushTokenFingerprint.make(registration.pushToken)
    }

    public var relayTokenFingerprint: String {
        PushTokenFingerprint.make(relayDeviceToken)
    }

    fileprivate var identity: APNsRegistrationIdentity {
        APNsRegistrationIdentity(
            registration: registration,
            relayDeviceToken: relayDeviceToken
        )
    }
}

public enum PushTokenFingerprint {
    public static func make(_ rawValue: String) -> String {
        SHA256.hash(data: Data(rawValue.utf8))
            .prefix(6)
            .map { String(format: "%02x", $0) }
            .joined()
    }
}

public struct APNsRegistrationState: Sendable {
    private var currentProcessAPNsToken: String?
    private var relayDeviceToken: String?
    private var bundleID: String?
    private var environment: PushEnvironment?
    private var locale: String?
    private var lastAttemptedIdentity: APNsRegistrationIdentity?
    private var inFlightAttempt: APNsRegistrationAttempt?
    private var needsRegistration = false
    private var nextAttemptID: UInt64 = 0

    public init() {}

    public var hasCurrentProcessAPNsToken: Bool {
        currentProcessAPNsToken?.isEmpty == false
    }

    public var currentAPNsTokenFingerprint: String? {
        currentProcessAPNsToken.map(PushTokenFingerprint.make)
    }

    public var isRegistrationInFlight: Bool {
        inFlightAttempt != nil
    }

    public mutating func receiveCurrentProcessAPNsToken(_ token: String) {
        let normalized = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty, normalized != currentProcessAPNsToken else { return }
        currentProcessAPNsToken = normalized
        refreshRegistrationNeed()
    }

    public mutating func updateRelayDeviceToken(_ token: String?) {
        let normalized = token?.trimmingCharacters(in: .whitespacesAndNewlines)
        let value = normalized?.isEmpty == false ? normalized : nil
        guard value != relayDeviceToken else { return }
        relayDeviceToken = value
        refreshRegistrationNeed()
    }

    public mutating func updateRegistrationContext(
        bundleID: String,
        environment: PushEnvironment,
        locale: String?
    ) {
        let normalizedBundleID = bundleID.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedLocale = locale?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedLocale = normalizedLocale?.isEmpty == false ? normalizedLocale : nil
        guard normalizedBundleID != self.bundleID ||
                environment != self.environment ||
                resolvedLocale != self.locale else { return }
        self.bundleID = normalizedBundleID
        self.environment = environment
        self.locale = resolvedLocale
        refreshRegistrationNeed()
    }

    public mutating func requestForcedRegistration() {
        guard let identity = currentIdentity else { return }
        if inFlightAttempt?.identity != identity {
            needsRegistration = true
        }
    }

    public mutating func beginNextAttempt() -> APNsRegistrationAttempt? {
        guard inFlightAttempt == nil,
              needsRegistration,
              let identity = currentIdentity else { return nil }

        nextAttemptID &+= 1
        let attempt = APNsRegistrationAttempt(
            id: nextAttemptID,
            registration: identity.registration,
            relayDeviceToken: identity.relayDeviceToken
        )
        inFlightAttempt = attempt
        needsRegistration = false
        return attempt
    }

    public mutating func complete(_ attempt: APNsRegistrationAttempt, succeeded _: Bool) {
        guard inFlightAttempt?.id == attempt.id else { return }
        inFlightAttempt = nil
        lastAttemptedIdentity = attempt.identity
        refreshRegistrationNeed()
    }

    private var currentIdentity: APNsRegistrationIdentity? {
        guard let currentProcessAPNsToken,
              let relayDeviceToken,
              let bundleID,
              !bundleID.isEmpty,
              let environment else { return nil }
        return APNsRegistrationIdentity(
            registration: PushDeviceRegistration(
                pushToken: currentProcessAPNsToken,
                bundleId: bundleID,
                environment: environment,
                locale: locale
            ),
            relayDeviceToken: relayDeviceToken
        )
    }

    private mutating func refreshRegistrationNeed() {
        guard let identity = currentIdentity else {
            needsRegistration = false
            return
        }
        needsRegistration = inFlightAttempt?.identity != identity &&
            lastAttemptedIdentity != identity
    }
}

private struct APNsRegistrationIdentity: Sendable, Equatable {
    let registration: PushDeviceRegistration
    let relayDeviceToken: String
}
