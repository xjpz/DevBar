import Foundation

public enum DeviceRelayDeviceType: String, Codable, Sendable, Equatable {
    case iPhone = "iphone"
    case mac
}

public enum DeviceRelayStatus: String, Codable, Sendable, Equatable {
    case online = "ONLINE"
    case offline = "OFFLINE"

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        switch value.uppercased() {
        case Self.online.rawValue:
            self = .online
        case Self.offline.rawValue:
            self = .offline
        default:
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Cannot initialize DeviceRelayStatus from invalid String value \(value)"
            )
        }
    }
}

public struct DeviceRelayDevice: Codable, Sendable, Equatable, Identifiable {
    public var id: String { deviceId }

    public let deviceId: String
    public let deviceType: DeviceRelayDeviceType
    public let deviceName: String?
    public let status: DeviceRelayStatus
    public let online: Bool
    public let lastSeenAt: Int64?

    public init(
        deviceId: String,
        deviceType: DeviceRelayDeviceType,
        deviceName: String?,
        status: DeviceRelayStatus,
        online: Bool,
        lastSeenAt: Int64?
    ) {
        self.deviceId = deviceId
        self.deviceType = deviceType
        self.deviceName = deviceName
        self.status = status
        self.online = online
        self.lastSeenAt = lastSeenAt
    }
}

public struct DeviceRelayRegistration: Codable, Sendable, Equatable {
    public let deviceId: String
    public let deviceType: DeviceRelayDeviceType
    public let deviceName: String?
    public let publicKey: String?
    public let deviceSecret: String?

    public init(
        deviceId: String,
        deviceType: DeviceRelayDeviceType,
        deviceName: String?,
        publicKey: String? = nil,
        deviceSecret: String? = nil
    ) {
        self.deviceId = deviceId
        self.deviceType = deviceType
        self.deviceName = deviceName
        self.publicKey = publicKey
        self.deviceSecret = deviceSecret
    }
}

public struct DeviceRelayRegistrationResponse: Sendable, Equatable {
    public let deviceToken: String
    public let device: DeviceRelayDevice

    public init(deviceToken: String, device: DeviceRelayDevice) {
        self.deviceToken = deviceToken
        self.device = device
    }
}

public struct DeviceRelayPairCode: Sendable, Equatable {
    public let pairCode: String
    public let expiresAt: Int64

    public init(pairCode: String, expiresAt: Int64) {
        self.pairCode = pairCode
        self.expiresAt = expiresAt
    }
}

public struct DeviceRelayMacDevice: Codable, Sendable, Equatable, Identifiable {
    public var id: String { deviceId }

    public let deviceId: String
    public let deviceName: String?

    public init(deviceId: String, deviceName: String?) {
        self.deviceId = deviceId
        self.deviceName = deviceName
    }
}

public struct DeviceRelayConfirmPairResponse: Sendable, Equatable {
    public let paired: Bool
    public let deviceToken: String
    public let macDevice: DeviceRelayMacDevice

    public init(paired: Bool, deviceToken: String, macDevice: DeviceRelayMacDevice) {
        self.paired = paired
        self.deviceToken = deviceToken
        self.macDevice = macDevice
    }
}

public struct DeviceRelayPairQRCodePayload: Codable, Sendable, Equatable {
    public let relay: URL
    public let pairCode: String
    public let macDeviceId: String
    public let expiresAt: Int64
    public let localSecret: String?

    public init(relay: URL, pairCode: String, macDeviceId: String, expiresAt: Int64, localSecret: String? = nil) {
        self.relay = relay
        self.pairCode = pairCode
        self.macDeviceId = macDeviceId
        self.expiresAt = expiresAt
        self.localSecret = localSecret
    }
}

public enum DeviceRelayMessageType: String, Codable, Sendable, Equatable {
    case relayConnected = "relay.connected"
    case relayMessage = "relay.message"
    case relayPaired = "relay.paired"
    case relayHeartbeat = "relay.heartbeat"
    case relayPing = "relay.ping"
    case relayPong = "relay.pong"
    case relayError = "relay.error"
    case agentCommand = "agent.command"
    case agentProgress = "agent.progress"
    case agentDone = "agent.done"
    case agentFailed = "agent.failed"
    case approvalRequest = "approval.request"
    case approvalResponse = "approval.response"
    case systemLockScreen = "system.lockScreen"
    case systemWakeDisplay = "system.wakeDisplay"
    case systemDisplaySleep = "system.displaySleep"
    case systemCommandResult = "system.command.result"
    case systemStatusRequest = "system.status.request"
    case systemStatus = "system.status"
    case smsAlert = "sms.alert"
    case smsAlertAck = "sms.alert.ack"
    case localChallenge = "local.challenge"
    case localAuth = "local.auth"
    case localReady = "local.ready"
    case providerAccountUpsert = "provider.account.upsert"
    case providerAccountDelete = "provider.account.delete"
    case providerQuotaSnapshot = "provider.quota.snapshot"
    case providerCredentialUpdate = "provider.credential.update"
    case providerSyncAck = "provider.sync.ack"
}

public enum DeviceRelayCommandType: String, Codable, Sendable, Equatable {
    case lockScreen
    case wakeDisplay
    case displaySleep
}

public struct DeviceRelayCommandResponse: Sendable, Equatable {
    public let commandId: String
    public let targetDeviceId: String
    public let messageType: DeviceRelayMessageType
    public let delivery: String
    public let acceptedAt: Int64

    public init(
        commandId: String,
        targetDeviceId: String,
        messageType: DeviceRelayMessageType,
        delivery: String,
        acceptedAt: Int64
    ) {
        self.commandId = commandId
        self.targetDeviceId = targetDeviceId
        self.messageType = messageType
        self.delivery = delivery
        self.acceptedAt = acceptedAt
    }
}

public struct DeviceRelayMessage: Codable, Sendable, Equatable, Identifiable {
    public var id: String { requestId ?? "\(type.rawValue)-\(timestamp)" }

    public let type: DeviceRelayMessageType
    public let requestId: String?
    public let fromDeviceId: String?
    public let targetDeviceId: String?
    public let timestamp: Int64
    public let payload: [String: String]

    public init(
        type: DeviceRelayMessageType,
        requestId: String? = nil,
        fromDeviceId: String? = nil,
        targetDeviceId: String? = nil,
        timestamp: Int64 = Int64(Date().timeIntervalSince1970 * 1000),
        payload: [String: String] = [:]
    ) {
        self.type = type
        self.requestId = requestId
        self.fromDeviceId = fromDeviceId
        self.targetDeviceId = targetDeviceId
        self.timestamp = timestamp
        self.payload = payload
    }
}

public enum DeviceRelayProviderSyncPayloadCodec {
    public static func encode<Value: Encodable>(_ value: Value) throws -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(value).base64URLEncodedString()
    }

    public static func decode<Value: Decodable>(_ type: Value.Type, from value: String) throws -> Value {
        guard let data = Data(base64URLEncoded: value) else {
            throw DeviceRelayError.invalidRelayResponse
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(type, from: data)
    }
}

public struct DeviceRelayProviderSyncAck: Codable, Sendable, Equatable {
    public let accountID: String
    public let provider: QuotaProvider
    public let status: String
    public let revision: Int
    public let message: String?

    public init(accountID: String, provider: QuotaProvider, status: String, revision: Int, message: String? = nil) {
        self.accountID = accountID
        self.provider = provider
        self.status = status
        self.revision = revision
        self.message = message
    }
}

public enum DeviceRelayAgentTaskStatus: String, Codable, Sendable, Equatable {
    case pending
    case running
    case succeeded
    case failed
}

public struct DeviceRelayAgentTask: Identifiable, Codable, Sendable, Equatable {
    public let id: String
    public let targetDeviceId: String
    public let prompt: String
    public let agent: String
    public let workspace: String?
    public let createdAt: Date
    public let updatedAt: Date
    public let status: DeviceRelayAgentTaskStatus
    public let progressMessage: String?
    public let resultSummary: String?
    public let errorMessage: String?

    public init(
        id: String,
        targetDeviceId: String,
        prompt: String,
        agent: String,
        workspace: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        status: DeviceRelayAgentTaskStatus = .pending,
        progressMessage: String? = nil,
        resultSummary: String? = nil,
        errorMessage: String? = nil
    ) {
        self.id = id
        self.targetDeviceId = targetDeviceId
        self.prompt = prompt
        self.agent = agent
        self.workspace = workspace
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.status = status
        self.progressMessage = progressMessage
        self.resultSummary = resultSummary
        self.errorMessage = errorMessage
    }

    public func updating(
        status: DeviceRelayAgentTaskStatus,
        progressMessage: String? = nil,
        resultSummary: String? = nil,
        errorMessage: String? = nil,
        updatedAt: Date = Date()
    ) -> DeviceRelayAgentTask {
        DeviceRelayAgentTask(
            id: id,
            targetDeviceId: targetDeviceId,
            prompt: prompt,
            agent: agent,
            workspace: workspace,
            createdAt: createdAt,
            updatedAt: updatedAt,
            status: status,
            progressMessage: progressMessage ?? self.progressMessage,
            resultSummary: resultSummary ?? self.resultSummary,
            errorMessage: errorMessage ?? self.errorMessage
        )
    }
}

public struct DeviceRelayLogEntry: Identifiable, Sendable, Equatable {
    public enum Level: String, Sendable, Equatable {
        case info
        case success
        case warning
        case error
    }

    public let id: UUID
    public let time: Date
    public let level: Level
    public let message: String

    public init(
        id: UUID = UUID(),
        time: Date = Date(),
        level: Level,
        message: String
    ) {
        self.id = id
        self.time = time
        self.level = level
        self.message = message
    }
}

public enum DeviceRelayConnectionState: Sendable, Equatable {
    case disconnected
    case connecting
    case connected
    case failed(String)

    public var isConnected: Bool {
        self == .connected
    }
}

public enum DeviceRelayActiveTransport: String, Sendable, Equatable {
    case none
    case local
    case relay
}

public enum DeviceRelayPeerConnectionStatus: Sendable, Equatable {
    case offline
    case local
    case remote
}

public struct DeviceRelayPeerRuntimeState: Sendable, Equatable {
    public let lastRemoteSeenAt: Date?
    public let lastLocalSeenAt: Date?
    public let displayName: String?
    public let screenLocked: Bool?
    public let displayAwake: Bool?

    public init(
        lastRemoteSeenAt: Date? = nil,
        lastLocalSeenAt: Date? = nil,
        displayName: String? = nil,
        screenLocked: Bool? = nil,
        displayAwake: Bool? = nil
    ) {
        self.lastRemoteSeenAt = lastRemoteSeenAt
        self.lastLocalSeenAt = lastLocalSeenAt
        self.displayName = displayName
        self.screenLocked = screenLocked
        self.displayAwake = displayAwake
    }

    public func updating(
        lastRemoteSeenAt: Date? = nil,
        lastLocalSeenAt: Date? = nil,
        displayName: String? = nil,
        screenLocked: Bool? = nil,
        displayAwake: Bool? = nil
    ) -> DeviceRelayPeerRuntimeState {
        DeviceRelayPeerRuntimeState(
            lastRemoteSeenAt: lastRemoteSeenAt ?? self.lastRemoteSeenAt,
            lastLocalSeenAt: lastLocalSeenAt ?? self.lastLocalSeenAt,
            displayName: displayName ?? self.displayName,
            screenLocked: screenLocked ?? self.screenLocked,
            displayAwake: displayAwake ?? self.displayAwake
        )
    }
}

public enum DeviceRelayError: Error, LocalizedError, Sendable, Equatable {
    case invalidURL
    case invalidQRCode
    case invalidRelayResponse
    case httpError(Int)
    case serverError(String)
    case missingDeviceToken
    case missingDeviceID
    case webSocketNotConnected
    case connectionTimeout

    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "中继服务地址无效"
        case .invalidQRCode:
            return "配对二维码无效或已过期"
        case .invalidRelayResponse:
            return "中继服务响应无效"
        case let .httpError(code):
            return "中继服务请求失败：\(code)"
        case let .serverError(code):
            return "中继服务错误：\(code)"
        case .missingDeviceToken:
            return "设备尚未注册"
        case .missingDeviceID:
            return "设备 ID 不存在"
        case .webSocketNotConnected:
            return "中继 WebSocket 未连接"
        case .connectionTimeout:
            return "等待中继 WebSocket 在线超时"
        }
    }
}
