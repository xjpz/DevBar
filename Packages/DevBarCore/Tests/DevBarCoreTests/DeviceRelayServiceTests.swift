import Foundation
import Testing
@testable import DevBarCore

@Test
func serverBaseURLUsesCanonicalProductionHost() {
    #expect(DevBarCoreConstants.Server.baseURL == "https://xjpz.cc")
}

@Test
func deviceRelayRegistrationUsesOpenAPIEnvelopeAndSecret() async throws {
    let recorder = DeviceRelayRequestRecorder(
        responseBody: """
        {
          "success": true,
          "code": 20000,
          "msg": "操作成功",
          "data": {
            "deviceToken": "drt_v1.unit",
            "device": {
              "deviceId": "mac-unit",
              "deviceType": "mac",
              "deviceName": "Unit Mac",
              "status": "ONLINE",
              "online": true,
              "lastSeenAt": 1716120000000
            }
          }
        }
        """.data(using: .utf8)!
    )
    let service = DeviceRelayService(
        baseURL: URL(string: "https://relay.example.test")!,
        session: recorder.session
    )

    let response = try await service.registerDevice(
        DeviceRelayRegistration(
            deviceId: "mac-unit",
            deviceType: .mac,
            deviceName: "Unit Mac",
            publicKey: "pk-unit",
            deviceSecret: "secret-unit"
        )
    )

    let request = try #require(await recorder.lastRequest)
    let body = try #require(await recorder.lastRequestBody)
    let bodyObject = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])

    #expect(response.deviceToken == "drt_v1.unit")
    #expect(response.device.deviceId == "mac-unit")
    #expect(response.device.online)
    #expect(request.httpMethod == "POST")
    #expect(request.url?.absoluteString == "https://relay.example.test/api/devbar/devices/register")
    #expect(bodyObject["deviceId"] as? String == "mac-unit")
    #expect(bodyObject["deviceType"] as? String == "mac")
    #expect(bodyObject["deviceSecret"] as? String == "secret-unit")
    #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
}

@Test
func deviceRelayRegistrationAcceptsLowercaseOfflineStatus() async throws {
    let recorder = DeviceRelayRequestRecorder(
        responseBody: """
        {
          "success": true,
          "code": 20000,
          "msg": "操作成功",
          "data": {
            "deviceToken": "drt_v1.unit",
            "device": {
              "deviceId": "mac-unit",
              "deviceType": "mac",
              "deviceName": "Unit Mac",
              "status": "offline",
              "online": false,
              "lastSeenAt": null
            }
          }
        }
        """.data(using: .utf8)!
    )
    let service = DeviceRelayService(
        baseURL: URL(string: "https://relay.example.test")!,
        session: recorder.session
    )

    let response = try await service.registerDevice(
        DeviceRelayRegistration(
            deviceId: "mac-unit",
            deviceType: .mac,
            deviceName: "Unit Mac",
            publicKey: nil,
            deviceSecret: "secret-unit"
        )
    )

    #expect(response.device.status == .offline)
    #expect(response.device.online == false)
    #expect(response.deviceToken == "drt_v1.unit")
}

@Test
func deviceRelayPairQRCodeRoundTripsWithoutSecret() throws {
    let payload = DeviceRelayPairQRCodePayload(
        relay: URL(string: "https://xjpz.cc")!,
        pairCode: "A3B7K9",
        macDeviceId: "mac-unit",
        expiresAt: 1716120060000
    )

    let encoded = try DeviceRelayPairQRCodeCodec.encode(payload)
    let decoded = try DeviceRelayPairQRCodeCodec.decode(encoded)

    #expect(decoded == payload)
    #expect(encoded.contains("deviceSecret") == false)
    #expect(DeviceRelayPairQRCodeCodec.canDecode(encoded))
}

@Test
func deviceRelayConfirmPairingPostsScannedPayloadAndStoresPeer() async throws {
    let recorder = DeviceRelayRequestRecorder(
        responseBody: """
        {
          "success": true,
          "code": 20000,
          "msg": "操作成功",
          "data": {
            "paired": true,
            "deviceToken": "drt_v1.iphone",
            "macDevice": {
              "deviceId": "mac-unit",
              "deviceName": "Unit Mac"
            }
          }
        }
        """.data(using: .utf8)!
    )
    let service = DeviceRelayService(
        baseURL: URL(string: "https://relay.example.test")!,
        session: recorder.session
    )

    let response = try await service.confirmPair(
        pairCode: "A3B7K9",
        macDeviceId: "mac-unit",
        iphoneDeviceId: "iphone-unit",
        iphoneDeviceName: "Unit iPhone",
        publicKey: "pk-iphone",
        deviceSecret: "device-secret-unit"
    )

    let request = try #require(await recorder.lastRequest)
    let body = try #require(await recorder.lastRequestBody)
    let bodyObject = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])

    #expect(response.paired)
    #expect(response.deviceToken == "drt_v1.iphone")
    #expect(response.macDevice.deviceId == "mac-unit")
    #expect(request.url?.absoluteString == "https://relay.example.test/api/devbar/pair/confirm")
    #expect(bodyObject["pairCode"] as? String == "A3B7K9")
    #expect(bodyObject["macDeviceId"] as? String == "mac-unit")
    #expect(bodyObject["iphoneDeviceId"] as? String == "iphone-unit")
    #expect(bodyObject["deviceSecret"] as? String == "device-secret-unit")
}

@Test
func accountBindingQRCodeAcceptsOnlyCurrentTrustedServerAndUnexpiredChallenge() throws {
    let payload = DeviceAccountBindQRCodePayload(
        type: "devbar.account-bind",
        version: 1,
        baseUrl: URL(string: DevBarCoreConstants.Server.baseURL)!,
        challenge: String(repeating: "A", count: 43),
        expiresAt: Int64(Date().addingTimeInterval(120).timeIntervalSince1970 * 1_000)
    )
    let encoded = String(data: try JSONEncoder().encode(payload), encoding: .utf8)!

    #expect(DeviceAccountBindQRCodeCodec.matchesType(encoded))
    #expect(try DeviceAccountBindQRCodeCodec.decode(encoded) == payload)

    let untrusted = encoded.replacingOccurrences(
        of: "xjpz.cc",
        with: "evil.example"
    )
    #expect(throws: DeviceRelayError.self) {
        try DeviceAccountBindQRCodeCodec.decode(untrusted)
    }

    let expiredPayload = DeviceAccountBindQRCodePayload(
        type: payload.type,
        version: payload.version,
        baseUrl: payload.baseUrl,
        challenge: payload.challenge,
        expiresAt: Int64(Date().addingTimeInterval(-1).timeIntervalSince1970 * 1_000)
    )
    let expired = String(data: try JSONEncoder().encode(expiredPayload), encoding: .utf8)!
    #expect(throws: DeviceRelayError.self) {
        try DeviceAccountBindQRCodeCodec.decode(expired)
    }
}

@Test
func accountBindingPreviewUsesDeviceCredentials() async throws {
    let recorder = DeviceRelayRequestRecorder(
        responseBody: """
        {
          "success": true,
          "code": 20000,
          "data": {
            "accountName": "a***e",
            "expiresAt": 1912345678000
          }
        }
        """.data(using: .utf8)!
    )
    let service = DeviceRelayService(
        baseURL: URL(string: DevBarCoreConstants.Server.baseURL)!,
        session: recorder.session
    )

    let preview = try await service.previewAccountBinding(
        challenge: String(repeating: "A", count: 43),
        deviceToken: "drt_v1.iphone",
        deviceSecret: "device-secret-unit"
    )

    let request = try #require(await recorder.lastRequest)
    #expect(preview.accountName == "a***e")
    #expect(request.url?.path == "/api/devbar/devices/account-bind/preview")
    #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer drt_v1.iphone")
    #expect(request.value(forHTTPHeaderField: "X-Device-Secret") == "device-secret-unit")
}

@Test
func accountBindingConfirmationUsesDeviceCredentialsAndDecodesClaimedHistory() async throws {
    let recorder = DeviceRelayRequestRecorder(
        responseBody: """
        {
          "success": true,
          "code": 20000,
          "data": {
            "deviceId": "iphone-unit",
            "deviceType": "iphone",
            "deviceName": "Unit iPhone",
            "claimedSnippets": 3
          }
        }
        """.data(using: .utf8)!
    )
    let service = DeviceRelayService(
        baseURL: URL(string: DevBarCoreConstants.Server.baseURL)!,
        session: recorder.session
    )
    let challenge = String(repeating: "B", count: 43)

    let confirmation = try await service.confirmAccountBinding(
        challenge: challenge,
        deviceToken: "drt_v1.iphone",
        deviceSecret: "device-secret-unit"
    )

    let request = try #require(await recorder.lastRequest)
    let body = try #require(await recorder.lastRequestBody)
    let bodyObject = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
    #expect(confirmation.deviceId == "iphone-unit")
    #expect(confirmation.claimedSnippets == 3)
    #expect(request.url?.path == "/api/devbar/devices/account-bind/confirm")
    #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer drt_v1.iphone")
    #expect(request.value(forHTTPHeaderField: "X-Device-Secret") == "device-secret-unit")
    #expect(bodyObject["challenge"] as? String == challenge)
}

@Test
func deviceRelayRevokePairPostsMacAndIPhoneIDs() async throws {
    let recorder = DeviceRelayRequestRecorder(
        responseBody: """
        {
          "success": true,
          "code": 20000,
          "msg": "操作成功",
          "data": {
            "revoked": true
          }
        }
        """.data(using: .utf8)!
    )
    let service = DeviceRelayService(
        baseURL: URL(string: "https://relay.example.test")!,
        session: recorder.session
    )

    let revoked = try await service.revokePair(
        macDeviceId: "mac-unit",
        iphoneDeviceId: "iphone-unit",
        deviceToken: "drt_v1.mac"
    )

    let request = try #require(await recorder.lastRequest)
    let body = try #require(await recorder.lastRequestBody)
    let bodyObject = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])

    #expect(revoked)
    #expect(request.httpMethod == "POST")
    #expect(request.url?.absoluteString == "https://relay.example.test/api/devbar/pair/revoke")
    #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer drt_v1.mac")
    #expect(bodyObject["macDeviceId"] as? String == "mac-unit")
    #expect(bodyObject["iphoneDeviceId"] as? String == "iphone-unit")
}

@Test
func deviceRelayPeersDecodeOnlineAndOfflineStatus() async throws {
    let recorder = DeviceRelayRequestRecorder(
        responseBody: """
        {
          "success": true,
          "code": 20000,
          "msg": "操作成功",
          "data": {
            "devices": [
              {
                "deviceId": "mac-online",
                "deviceType": "mac",
                "deviceName": "Online Mac",
                "status": "ONLINE",
                "online": true,
                "lastSeenAt": 1716120000000
              },
              {
                "deviceId": "mac-offline",
                "deviceType": "mac",
                "deviceName": "Offline Mac",
                "status": "OFFLINE",
                "online": false,
                "lastSeenAt": null
              }
            ]
          }
        }
        """.data(using: .utf8)!
    )
    let service = DeviceRelayService(
        baseURL: URL(string: "https://relay.example.test")!,
        session: recorder.session
    )

    let peers = try await service.fetchPeers(deviceToken: "drt_v1.unit")

    let request = try #require(await recorder.lastRequest)
    #expect(peers.map(\.deviceId) == ["mac-online", "mac-offline"])
    #expect(peers[0].online)
    #expect(peers[1].online == false)
    #expect(request.httpMethod == "GET")
    #expect(request.url?.absoluteString == "https://relay.example.test/api/devbar/devices/peers")
    #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer drt_v1.unit")
}

@Test
func deviceRelaySocketBuildsWssURLAndRelayMessagesRoundTrip() throws {
    let url = try DeviceRelayService.webSocketURL(
        baseURL: URL(string: "https://xjpz.cc")!,
        deviceId: "iphone unit",
        deviceToken: "drt_v1.token+unit"
    )
    let message = DeviceRelayMessage(
        type: .agentCommand,
        requestId: "task-unit",
        fromDeviceId: "iphone-unit",
        targetDeviceId: "mac-unit",
        timestamp: 1716120000000,
        payload: ["prompt": "hello", "agent": "codex"]
    )
    let encoded = try DeviceRelayMessageCodec.encode(message)
    let decoded = try DeviceRelayMessageCodec.decode(encoded)

    #expect(url.absoluteString == "wss://xjpz.cc/ws/devbar-relay?deviceId=iphone%20unit&token=drt_v1.token+unit")
    #expect(decoded == message)
}

@Test
func deviceRelayMessageDecodesServerConnectedWithoutRequestID() throws {
    let rawMessage = """
    {
      "type": "relay.connected",
      "payload": {
        "connectionId": "conn-unit",
        "serverTime": 1716120000000
      }
    }
    """

    let message = try DeviceRelayMessageCodec.decode(rawMessage)

    #expect(message.type == .relayConnected)
    #expect(message.requestId == nil)
    #expect(message.payload["connectionId"] == "conn-unit")
    #expect(message.payload["serverTime"] == "1716120000000")
}

@Test
func deviceRelayMessageDecodesServerRelayErrorWithoutClosingReceiveLoop() throws {
    let rawMessage = """
    {
      "type": "relay.error",
      "payload": {
        "code": "mac_device_offline",
        "message": "Mac device is offline"
      }
    }
    """

    let message = try DeviceRelayMessageCodec.decode(rawMessage)

    #expect(message.type == .relayError)
    #expect(message.requestId == nil)
    #expect(message.payload["code"] == "mac_device_offline")
    #expect(message.payload["message"] == "Mac device is offline")
}

@MainActor
@Test
func deviceRelayHeartbeatUsesServerPingPath() throws {
    let message = DeviceRelayManager.makeHeartbeatMessage(localDeviceID: "mac-unit", deviceName: "Unit Mac")
    let encoded = try DeviceRelayMessageCodec.encode(message)
    let decoded = try DeviceRelayMessageCodec.decode(encoded)

    #expect(decoded.type == .relayPing)
    #expect(decoded.requestId?.hasPrefix("heartbeat-") == true)
    #expect(decoded.fromDeviceId == "mac-unit")
    #expect(decoded.targetDeviceId == nil)
    #expect(decoded.payload["deviceName"] == "Unit Mac")
}

@Test
func deviceRelayMessageDecodesServerPong() throws {
    let rawMessage = """
    {
      "type": "relay.pong",
      "payload": {
        "serverTime": 1716120000000
      }
    }
    """

    let message = try DeviceRelayMessageCodec.decode(rawMessage)

    #expect(message.type == .relayPong)
    #expect(message.requestId == nil)
    #expect(message.payload["serverTime"] == "1716120000000")
}

@MainActor
@Test
func deviceRelayPeerConnectionStatusExpiresStaleRemotePeer() {
    let manager = DeviceRelayManager()
    let now = Date(timeIntervalSince1970: 1_716_120_100)
    let freshPeer = DeviceRelayDevice(
        deviceId: "iphone-fresh",
        deviceType: .iPhone,
        deviceName: "Unit iPhone",
        status: .online,
        online: true,
        lastSeenAt: Int64(now.addingTimeInterval(-20).timeIntervalSince1970 * 1000)
    )
    let stalePeer = DeviceRelayDevice(
        deviceId: "iphone-stale",
        deviceType: .iPhone,
        deviceName: "Unit iPhone",
        status: .online,
        online: true,
        lastSeenAt: Int64(now.addingTimeInterval(-120).timeIntervalSince1970 * 1000)
    )

    manager.setConnectedForTesting()

    #expect(manager.connectionStatus(for: freshPeer, now: now) == .remote)
    #expect(manager.connectionStatus(for: stalePeer, now: now) == .offline)
}

@MainActor
@Test
func deviceRelaySystemStatusTracksPeerNameLockStateAndDisplayState() throws {
    let manager = DeviceRelayManager()
    let peer = DeviceRelayDevice(
        deviceId: "mac-unit",
        deviceType: .mac,
        deviceName: "Mac",
        status: .online,
        online: true,
        lastSeenAt: nil
    )
    let message = DeviceRelayManager.makeSystemStatusMessage(
        localDeviceID: "mac-unit",
        targetDeviceId: "iphone-unit",
        requestId: "status-unit",
        screenLocked: true,
        displayAwake: false,
        deviceName: "Unit MacBook",
        cpuPercent: 37,
        memoryPercent: 68,
        networkDownBytesPerSecond: 2_621_440,
        networkUpBytesPerSecond: 184_320
    )

    let encoded = try DeviceRelayMessageCodec.encode(message)
    let decoded = try DeviceRelayMessageCodec.decode(encoded)
    manager.handleMessageForTesting(decoded)

    #expect(decoded.type == .systemStatus)
    #expect(decoded.payload["screenLocked"] == "true")
    #expect(decoded.payload["displayAwake"] == "false")
    #expect(decoded.payload["cpuPercent"] == "37")
    #expect(decoded.payload["memoryPercent"] == "68")
    #expect(decoded.payload["networkDownBytesPerSecond"] == "2621440")
    #expect(decoded.payload["networkUpBytesPerSecond"] == "184320")
    #expect(manager.displayName(for: peer) == "Unit MacBook")
    #expect(manager.screenLocked(for: peer) == true)
    #expect(manager.displayAwake(for: peer) == false)
    #expect(manager.cpuPercent(for: peer) == 37)
    #expect(manager.memoryPercent(for: peer) == 68)
    #expect(manager.networkDownBytesPerSecond(for: peer) == 2_621_440)
    #expect(manager.networkUpBytesPerSecond(for: peer) == 184_320)
}

@Test
func deviceRelaySocketDisconnectedErrorIsNotReportedAsUnregistered() {
    #expect(DeviceRelayError.webSocketNotConnected.errorDescription == "中继 WebSocket 未连接")
    #expect(DeviceRelayError.missingDeviceToken.errorDescription == "设备尚未注册")
}

@MainActor
@Test
func invalidDeviceSecretRequiresRecoveryAndIsNotOverwrittenByMissingToken() async {
    let recorder = DeviceRelayRequestRecorder(
        responseBody: """
        {
          "success": false,
          "code": 40302,
          "msg": "invalid_device_secret",
          "data": null
        }
        """.data(using: .utf8)!,
        statusCode: 403
    )
    let context = makeStoreContext()
    defer { context.cleanup() }
    let deviceID = "mac-identity-conflict"
    context.defaults.set(deviceID, forKey: DevBarCoreConstants.Defaults.relayMacDeviceIDKey)
    context.secureStore.setString(deviceID, forKey: DevBarCoreConstants.Keychain.macRelayDeviceIDKey)
    context.secureStore.setString(
        "drs_stable-device-secret-with-more-than-32-chars",
        forKey: DevBarCoreConstants.Keychain.macRelayDeviceSecretKey
    )
    let service = DeviceRelayService(
        baseURL: URL(string: "https://relay.example.test")!,
        session: recorder.session
    )
    let manager = DeviceRelayManager(service: service, store: context.store)

    await manager.setup(deviceType: .mac, deviceName: "Unit Mac")

    #expect(manager.identityRecoveryRequirement == .secretMismatch)
    #expect(manager.deviceToken == nil)
    #expect(manager.lastErrorMessage == "本机中继凭据与服务端记录不一致，需要重置后重新连接 iPhone")
    let originalMessage = manager.lastErrorMessage

    await manager.createPairQRCode(deviceName: "Unit Mac")

    #expect(manager.lastErrorMessage == originalMessage)
    #expect(manager.identityRecoveryRequirement == .secretMismatch)
}

@MainActor
@Test
func relayPairedOverwritesOnlyTheConfirmedIPhoneLocalSecret() {
    let context = makeStoreContext()
    defer { context.cleanup() }
    let manager = DeviceRelayManager(store: context.store)
    let payload = DeviceRelayPairQRCodePayload(
        relay: URL(string: "https://relay.example.test")!,
        pairCode: "ABC123",
        macDeviceId: "mac-unit",
        expiresAt: 1_900_000_000_000,
        localSecret: "new-local-secret"
    )
    context.store.savePendingLocalPairSecret("new-local-secret", pairCode: payload.pairCode)
    context.store.saveLocalPairSecret("old-target-secret", peerDeviceID: "iphone-target")
    context.store.saveLocalPairSecret("other-secret", peerDeviceID: "iphone-other")
    manager.setPendingPairForTesting(payload, deviceType: .mac)

    manager.handleMessageForTesting(DeviceRelayMessage(
        type: .relayPaired,
        fromDeviceId: "iphone-target",
        targetDeviceId: "mac-unit",
        payload: ["iphoneDeviceId": "iphone-target"]
    ))

    #expect(context.store.loadLocalPairSecret(peerDeviceID: "iphone-target") == "new-local-secret")
    #expect(context.store.loadLocalPairSecret(peerDeviceID: "iphone-other") == "other-secret")
    #expect(context.store.loadPendingLocalPairSecret(pairCode: payload.pairCode) == nil)
}

@Test
@MainActor
func deviceRelayReconnectBackoffIsCapped() {
    #expect(DeviceRelayManager.reconnectDelay(forAttempt: 0) == 2)
    #expect(DeviceRelayManager.reconnectDelay(forAttempt: 1) == 5)
    #expect(DeviceRelayManager.reconnectDelay(forAttempt: 2) == 15)
    #expect(DeviceRelayManager.reconnectDelay(forAttempt: 3) == 30)
    #expect(DeviceRelayManager.reconnectDelay(forAttempt: 4) == 60)
    #expect(DeviceRelayManager.reconnectDelay(forAttempt: 99) == 60)
}

@MainActor
@Test
func deviceRelayLockScreenMessageUsesSystemCommandType() throws {
    let message = DeviceRelayManager.makeLockScreenMessage(
        localDeviceID: "iphone-unit",
        targetDeviceId: "mac-unit"
    )
    let encoded = try DeviceRelayMessageCodec.encode(message)
    let decoded = try DeviceRelayMessageCodec.decode(encoded)

    #expect(decoded.type == .systemLockScreen)
    #expect(decoded.requestId?.hasPrefix("lock-") == true)
    #expect(decoded.fromDeviceId == "iphone-unit")
    #expect(decoded.targetDeviceId == "mac-unit")
    #expect(decoded.payload["command"] == "lockScreen")
}

@MainActor
@Test
func deviceRelayDisplayCommandsUseMatchingSystemMessageTypes() throws {
    let wakeMessage = DeviceRelayManager.makeSystemCommandMessage(
        localDeviceID: "iphone-unit",
        targetDeviceId: "mac-unit",
        command: .wakeDisplay
    )
    let sleepMessage = DeviceRelayManager.makeSystemCommandMessage(
        localDeviceID: "iphone-unit",
        targetDeviceId: "mac-unit",
        command: .displaySleep
    )

    #expect(wakeMessage.type == .systemWakeDisplay)
    #expect(wakeMessage.requestId?.hasPrefix("wake-") == true)
    #expect(wakeMessage.payload["command"] == "wakeDisplay")
    #expect(sleepMessage.type == .systemDisplaySleep)
    #expect(sleepMessage.requestId?.hasPrefix("sleep-") == true)
    #expect(sleepMessage.payload["command"] == "displaySleep")
}

@Test
func deviceRelayCommandPostUsesPairedMacCommandEndpoint() async throws {
    let recorder = DeviceRelayRequestRecorder(
        responseBody: """
        {
          "success": true,
          "code": 20000,
          "msg": "操作成功",
          "data": {
            "commandId": "cmd-unit",
            "targetDeviceId": "mac-unit",
            "messageType": "system.lockScreen",
            "delivery": "forwarded",
            "acceptedAt": 1716120000000
          }
        }
        """.data(using: .utf8)!
    )
    let service = DeviceRelayService(
        baseURL: URL(string: "https://relay.example.test")!,
        session: recorder.session
    )

    let response = try await service.sendDeviceCommand(
        type: .lockScreen,
        targetDeviceId: "mac-unit",
        deviceToken: "drt_v1.iphone",
        nonce: "nonce-unit-1234567890",
        timestamp: 1_716_120_000_000
    )

    let request = try #require(await recorder.lastRequest)
    let body = try #require(await recorder.lastRequestBody)
    let bodyObject = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])

    #expect(response.commandId == "cmd-unit")
    #expect(response.messageType == .systemLockScreen)
    #expect(response.delivery == "forwarded")
    #expect(request.httpMethod == "POST")
    #expect(request.url?.absoluteString == "https://relay.example.test/api/devbar/devices/mac-unit/commands")
    #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer drt_v1.iphone")
    #expect(bodyObject["type"] as? String == "lockScreen")
    #expect(bodyObject["nonce"] as? String == "nonce-unit-1234567890")
    #expect(bodyObject["timestamp"] as? Int == 1_716_120_000_000)
}

@Test
func deviceRelayControlCommandTypesMapToWireValues() {
    #expect(DeviceRelayCommandType.lockScreen.rawValue == "lockScreen")
    #expect(DeviceRelayCommandType.wakeDisplay.rawValue == "wakeDisplay")
    #expect(DeviceRelayCommandType.displaySleep.rawValue == "displaySleep")
}

@MainActor
@Test
func deviceRelaySMSAlertMessageCarriesShortcutPayloadAndStableDedupKey() throws {
    let message = DeviceRelayManager.makeSMSAlertMessage(
        localDeviceID: "iphone-unit",
        targetDeviceId: "mac-unit",
        messageText: "验证码 123456，请勿泄露",
        sender: "955xx",
        matchedKeyword: "验证码",
        notificationTitle: "银行验证码",
        receivedAt: 1_716_120_045_000
    )
    let repeated = DeviceRelayManager.makeSMSAlertMessage(
        localDeviceID: "iphone-unit",
        targetDeviceId: "mac-unit",
        messageText: "验证码 123456，请勿泄露",
        sender: "955xx",
        matchedKeyword: "验证码",
        receivedAt: 1_716_120_049_000
    )

    let encoded = try DeviceRelayMessageCodec.encode(message)
    let decoded = try DeviceRelayMessageCodec.decode(encoded)

    #expect(decoded.type == .smsAlert)
    #expect(decoded.requestId?.hasPrefix("sms-") == true)
    #expect(decoded.fromDeviceId == "iphone-unit")
    #expect(decoded.targetDeviceId == "mac-unit")
    #expect(decoded.payload["messageText"] == "验证码 123456，请勿泄露")
    #expect(decoded.payload["sender"] == "955xx")
    #expect(decoded.payload["matchedKeyword"] == "验证码")
    #expect(decoded.payload["notificationTitle"] == "银行验证码")
    #expect(decoded.payload["source"] == "shortcuts.messageAutomation")
    #expect(decoded.payload["receivedAt"] == "1716120045000")
    #expect(decoded.payload["dedupKey"] == repeated.payload["dedupKey"])
    #expect(decoded.payload["dedupKey"]?.isEmpty == false)
}

@Test
func smsAlertSummaryTrimsWhitespaceAndLimitsDisplayedContent() {
    let longText = "  " + String(repeating: "验证码", count: 90) + "  "

    let summary = DeviceRelaySMSAlert.summary(for: longText, limit: 12)

    #expect(summary == "验证码验证码验证码验证码...")
}

@MainActor
@Test
func deviceRelaySMSAlertAckMessageReportsShownStatus() throws {
    let message = DeviceRelayManager.makeSMSAlertAckMessage(
        localDeviceID: "mac-unit",
        targetDeviceId: "iphone-unit",
        requestId: "sms-unit",
        status: "shown",
        detail: "Mac 已提醒",
        shownAt: 1_716_120_050_000
    )

    let encoded = try DeviceRelayMessageCodec.encode(message)
    let decoded = try DeviceRelayMessageCodec.decode(encoded)

    #expect(decoded.type == .smsAlertAck)
    #expect(decoded.requestId == "sms-unit")
    #expect(decoded.payload["status"] == "shown")
    #expect(decoded.payload["message"] == "Mac 已提醒")
    #expect(decoded.payload["shownAt"] == "1716120050000")
}

@Test
func homeScreenQuickActionsShowLockMacOnlyWhenPairedMacExists() {
    let withoutMac = DeviceRelayHomeScreenShortcutPolicy.availableActions(hasPairedMac: false)
    let withMac = DeviceRelayHomeScreenShortcutPolicy.availableActions(hasPairedMac: true)
    let defaultSelection = DeviceRelayHomeScreenShortcutPolicy.defaultSelection(hasPairedMac: true)

    #expect(withoutMac.contains(.apiClient))
    #expect(withoutMac.contains(.lockMac) == false)
    #expect(withMac.contains(.apiClient))
    #expect(withMac.contains(.lockMac))
    #expect(defaultSelection.contains(.apiClient) == false)
}

@Test
func homeScreenQuickActionsNormalizeUserSelectionToFourAvailableItems() {
    let selected = DeviceRelayHomeScreenShortcutPolicy.normalizedSelection(
        [
            .memo,
            .qrScan,
            .ocr,
            .apiClient,
            .lockMac,
            .wakeMacDisplay,
        ],
        hasPairedMac: true
    )

    #expect(selected == [.memo, .qrScan, .ocr, .apiClient])
}

@Test
func homeScreenQuickActionsRemoveMacControlsWhenNoMacIsPaired() {
    let selected = DeviceRelayHomeScreenShortcutPolicy.normalizedSelection(
        [.memo, .lockMac, .wakeMacDisplay, .sleepMacDisplay],
        hasPairedMac: false
    )

    #expect(selected == [.memo])
}

@Test
@MainActor
func deviceRelayAgentTaskTracksProgressDoneAndFailure() {
    let manager = DeviceRelayManager()
    let task = DeviceRelayAgentTask(
        id: "task-unit",
        targetDeviceId: "mac-unit",
        prompt: "Summarize the workspace",
        agent: "codex"
    )

    manager.recordAgentTaskForTesting(task)
    manager.handleMessageForTesting(
        DeviceRelayMessage(
            type: .agentProgress,
            requestId: "task-unit",
            fromDeviceId: "mac-unit",
            targetDeviceId: "iphone-unit",
            payload: ["message": "Mac 已收到任务"]
        )
    )

    #expect(manager.agentTasks.first?.status == .running)
    #expect(manager.agentTasks.first?.progressMessage == "Mac 已收到任务")

    manager.handleMessageForTesting(
        DeviceRelayMessage(
            type: .agentDone,
            requestId: "task-unit",
            fromDeviceId: "mac-unit",
            targetDeviceId: "iphone-unit",
            payload: ["summary": "Done"]
        )
    )

    #expect(manager.agentTasks.first?.status == .succeeded)
    #expect(manager.agentTasks.first?.resultSummary == "Done")

    manager.recordAgentTaskForTesting(
        DeviceRelayAgentTask(
            id: "task-failed",
            targetDeviceId: "mac-unit",
            prompt: "Break",
            agent: "codex"
        )
    )
    manager.handleMessageForTesting(
        DeviceRelayMessage(
            type: .agentFailed,
            requestId: "task-failed",
            fromDeviceId: "mac-unit",
            targetDeviceId: "iphone-unit",
            payload: [
                "errorCode": "AGENT_FAILED",
                "message": "failed"
            ]
        )
    )

    #expect(manager.agentTasks.first { $0.id == "task-failed" }?.status == .failed)
    #expect(manager.agentTasks.first { $0.id == "task-failed" }?.errorMessage == "failed")
}

private final class DeviceRelayRequestRecorder: @unchecked Sendable {
    private let requestStore = CapturedRequestStore()
    let session: URLSession

    var lastRequest: URLRequest? {
        get async {
            requestStore.request
        }
    }

    var lastRequestBody: Data? {
        get async {
            requestStore.body
        }
    }

    init(responseBody: Data, statusCode: Int = 200) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [DeviceRelayMockURLProtocol.self]
        let id = UUID()
        configuration.httpAdditionalHeaders = ["X-Test-Device-Relay-Recorder-ID": id.uuidString]
        DeviceRelayMockURLProtocol.register(
            recorderID: id.uuidString,
            responseBody: responseBody,
            statusCode: statusCode,
            capture: { [requestStore] request, body in
                requestStore.request = request
                requestStore.body = body
            }
        )
        self.session = URLSession(configuration: configuration)
    }

    private final class CapturedRequestStore: @unchecked Sendable {
        private let lock = NSLock()
        private var storedRequest: URLRequest?
        private var storedBody: Data?

        var request: URLRequest? {
            get {
                lock.withLock { storedRequest }
            }
            set {
                lock.withLock { storedRequest = newValue }
            }
        }

        var body: Data? {
            get {
                lock.withLock { storedBody }
            }
            set {
                lock.withLock { storedBody = newValue }
            }
        }
    }
}

private final class DeviceRelayMockURLProtocol: URLProtocol, @unchecked Sendable {
    private struct Stub: Sendable {
        let responseBody: Data
        let statusCode: Int
        let capture: @Sendable (URLRequest, Data?) -> Void
    }

    private static let store = StubStore()

    static func register(
        recorderID: String,
        responseBody: Data,
        statusCode: Int,
        capture: @escaping @Sendable (URLRequest, Data?) -> Void
    ) {
        store.set(
            Stub(responseBody: responseBody, statusCode: statusCode, capture: capture),
            for: recorderID
        )
    }

    override class func canInit(with request: URLRequest) -> Bool {
        request.value(forHTTPHeaderField: "X-Test-Device-Relay-Recorder-ID") != nil
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let recorderID = request.value(forHTTPHeaderField: "X-Test-Device-Relay-Recorder-ID"),
              let stub = Self.store.stub(for: recorderID),
              let url = request.url,
              let response = HTTPURLResponse(
                  url: url,
                  statusCode: stub.statusCode,
                  httpVersion: "HTTP/1.1",
                  headerFields: ["Content-Type": "application/json"]
              ) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        stub.capture(request, request.httpBody ?? request.httpBodyStream?.readAllData())
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: stub.responseBody)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private final class StubStore: @unchecked Sendable {
        private let lock = NSLock()
        private var stubs: [String: Stub] = [:]

        func set(_ stub: Stub, for recorderID: String) {
            lock.withLock { stubs[recorderID] = stub }
        }

        func stub(for recorderID: String) -> Stub? {
            lock.withLock { stubs[recorderID] }
        }
    }
}

private extension InputStream {
    func readAllData() -> Data {
        open()
        defer { close() }

        var data = Data()
        let bufferSize = 1_024
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }

        while hasBytesAvailable {
            let count = read(buffer, maxLength: bufferSize)
            guard count > 0 else { break }
            data.append(buffer, count: count)
        }
        return data
    }
}
