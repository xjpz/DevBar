import Testing
@testable import DevBarCore

@Test func apnsRegistrationWaitsForCurrentProcessToken() {
    var state = APNsRegistrationState()
    state.updateRegistrationContext(bundleID: "cc.xjpz.DevBar", environment: .development, locale: "zh-Hans")
    state.updateRelayDeviceToken("relay-token")
    state.requestForcedRegistration()

    #expect(state.beginNextAttempt() == nil)

    state.receiveCurrentProcessAPNsToken("apns-token")
    let attempt = state.beginNextAttempt()
    #expect(attempt?.registration.pushToken == "apns-token")
    #expect(attempt?.relayDeviceToken == "relay-token")
}

@Test func apnsRegistrationDoesNotRepeatUnchangedSuccessfulIdentity() throws {
    var state = readyAPNsRegistrationState()
    let attempt = try requireNextAttempt(&state)
    state.complete(attempt, succeeded: true)

    state.receiveCurrentProcessAPNsToken("apns-token")
    state.updateRelayDeviceToken("relay-token")

    #expect(state.beginNextAttempt() == nil)
}

@Test func apnsRegistrationForceCoalescesWithInFlightRequest() throws {
    var state = readyAPNsRegistrationState()
    let attempt = try requireNextAttempt(&state)

    state.requestForcedRegistration()
    state.requestForcedRegistration()
    state.complete(attempt, succeeded: true)

    #expect(state.beginNextAttempt() == nil)
}

@Test func apnsRegistrationForceRetriesCompletedIdentityOnce() throws {
    var state = readyAPNsRegistrationState()
    let first = try requireNextAttempt(&state)
    state.complete(first, succeeded: true)

    state.requestForcedRegistration()
    let forced = try requireNextAttempt(&state)
    state.complete(forced, succeeded: true)

    #expect(forced.id != first.id)
    #expect(state.beginNextAttempt() == nil)
}

@Test func apnsRegistrationSendsNewTokenAfterOlderRequestCompletes() throws {
    var state = readyAPNsRegistrationState()
    let oldAttempt = try requireNextAttempt(&state)

    state.receiveCurrentProcessAPNsToken("new-apns-token")
    state.complete(oldAttempt, succeeded: true)

    let newAttempt = try requireNextAttempt(&state)
    #expect(newAttempt.registration.pushToken == "new-apns-token")
    #expect(newAttempt.id != oldAttempt.id)
}

@Test func apnsRegistrationDoesNotRepeatWhenTokenReturnsToInFlightIdentity() throws {
    var state = readyAPNsRegistrationState()
    let attempt = try requireNextAttempt(&state)

    state.receiveCurrentProcessAPNsToken("temporary-apns-token")
    state.receiveCurrentProcessAPNsToken("apns-token")
    state.complete(attempt, succeeded: true)

    #expect(state.beginNextAttempt() == nil)
}

@Test func apnsRegistrationDoesNotLoopAfterFailureWithoutNewState() throws {
    var state = readyAPNsRegistrationState()
    let attempt = try requireNextAttempt(&state)
    state.complete(attempt, succeeded: false)

    #expect(state.beginNextAttempt() == nil)
}

@Test func apnsRegistrationRetriesLatestStateWhenOlderRequestFails() throws {
    var state = readyAPNsRegistrationState()
    let oldAttempt = try requireNextAttempt(&state)

    state.updateRelayDeviceToken("new-relay-token")
    state.complete(oldAttempt, succeeded: false)

    let nextAttempt = try requireNextAttempt(&state)
    #expect(nextAttempt.relayDeviceToken == "new-relay-token")
}

@Test func pushTokenFingerprintIsShortAndDoesNotContainRawToken() {
    let rawToken = "4085-secret-apns-token"
    let fingerprint = PushTokenFingerprint.make(rawToken)

    #expect(fingerprint.count == 12)
    #expect(!fingerprint.contains(rawToken))
    #expect(fingerprint == PushTokenFingerprint.make(rawToken))
}

@Test func apnsDiagnosticFingerprintsSurviveRedactionWithoutRawToken() {
    let redacted = DiagnosticLogRedactor.redact([
        "apnsFingerprint": "08e88eb2eacd",
        "relayFingerprint": "297b4f6cc5ba",
        "rawToken": "must-not-survive",
    ])

    #expect(redacted["apnsFingerprint"] == "08e88eb2eacd")
    #expect(redacted["relayFingerprint"] == "297b4f6cc5ba")
    #expect(redacted["rawToken"] == "<redacted:length=16>")
}

private func readyAPNsRegistrationState() -> APNsRegistrationState {
    var state = APNsRegistrationState()
    state.updateRegistrationContext(bundleID: "cc.xjpz.DevBar", environment: .development, locale: "zh-Hans")
    state.updateRelayDeviceToken("relay-token")
    state.receiveCurrentProcessAPNsToken("apns-token")
    return state
}

private func requireNextAttempt(_ state: inout APNsRegistrationState) throws -> APNsRegistrationAttempt {
    let attempt = state.beginNextAttempt()
    return try #require(attempt)
}
