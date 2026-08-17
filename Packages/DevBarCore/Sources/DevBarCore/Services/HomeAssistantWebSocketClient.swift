import Foundation

public actor HomeAssistantWebSocketClient {
    public typealias EventStream = AsyncStream<HomeAssistantState>

    private struct PendingCommand {
        let operation: String
        let continuation: CheckedContinuation<HomeAssistantJSONValue, Error>
    }

    private let session: URLSession
    private let diagnostics: HomeAssistantDiagnosticReporter
    private var socket: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?
    private var heartbeatTask: Task<Void, Never>?
    private var commandSendTask: Task<Void, Never>?
    private var commandSendTaskEpoch: Int?
    private var nextID = 1
    private var pending: [Int: PendingCommand] = [:]
    private var outboundCommands = HomeAssistantWebSocketCommandQueue()
    private var authContinuation: CheckedContinuation<Void, Error>?
    private var authenticated = false
    private var eventContinuation: EventStream.Continuation?
    private var token = ""
    private var endpointURL: URL?
    private var connectionEpoch = HomeAssistantConnectionEpoch()

    public init(
        session: URLSession = .shared,
        diagnostics: HomeAssistantDiagnosticReporter = .shared
    ) {
        self.session = session
        self.diagnostics = diagnostics
    }

    public func events() -> EventStream {
        EventStream { continuation in
            eventContinuation = continuation
        }
    }

    public func connect(baseURL: URL, token: String) async throws {
        disconnect()
        let epoch = connectionEpoch.current
        guard let url = HomeAssistantEndpointSelector.webSocketURL(from: baseURL) else {
            throw HomeAssistantError.invalidResponse
        }
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw HomeAssistantError.emptyToken }
        self.token = trimmed
        endpointURL = url
        let socket = session.webSocketTask(with: url)
        self.socket = socket
        socket.resume()

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            authContinuation = continuation
            receiveTask = Task { [weak self] in
                await self?.receiveLoop(socket: socket, epoch: epoch)
            }
        }
    }

    public func disconnect() {
        connectionEpoch.advance()
        receiveTask?.cancel()
        receiveTask = nil
        heartbeatTask?.cancel()
        heartbeatTask = nil
        commandSendTask?.cancel()
        commandSendTask = nil
        commandSendTaskEpoch = nil
        outboundCommands.removeAll()
        socket?.cancel(with: .goingAway, reason: nil)
        socket = nil
        authenticated = false
        token = ""
        endpointURL = nil
        authContinuation?.resume(throwing: HomeAssistantError.disconnected)
        authContinuation = nil
        for command in pending.values {
            command.continuation.resume(throwing: HomeAssistantError.disconnected)
        }
        pending.removeAll()
        eventContinuation?.finish()
        eventContinuation = nil
    }

    public func fetchStates() async throws -> [HomeAssistantState] {
        let value = try await command(type: "get_states")
        return try decode([HomeAssistantState].self, from: value, operation: "get_states")
    }

    public func fetchConfig() async throws -> HomeAssistantConfig {
        let value = try await command(type: "get_config")
        return try decode(HomeAssistantConfig.self, from: value, operation: "get_config")
    }

    public func fetchServices() async throws -> [HomeAssistantService] {
        let value = try await command(type: "get_services")
        guard case .object(let domains) = value else {
            recordDecodeFailure(operation: "get_services", value: value)
            throw HomeAssistantError.invalidResponse
        }
        return domains.map { domain, services in
            HomeAssistantService(domain: domain, services: services.objectValue ?? [:])
        }.sorted { $0.domain < $1.domain }
    }

    public func fetchAreas() async throws -> [HomeAssistantArea] {
        let value = try await command(type: "config/area_registry/list")
        return try decode([HomeAssistantArea].self, from: value, operation: "config/area_registry/list")
    }

    public func fetchDevices() async throws -> [HomeAssistantDevice] {
        let value = try await command(type: "config/device_registry/list")
        return try decode([HomeAssistantDevice].self, from: value, operation: "config/device_registry/list")
    }

    public func fetchEntityRegistry() async throws -> [HomeAssistantEntityRegistryEntry] {
        do {
            return try await fetchEntityRegistryForDisplay()
        } catch {
            let value = try await command(type: "config/entity_registry/list")
            guard let entities = value.arrayValue else {
                recordDecodeFailure(operation: "config/entity_registry/list", value: value)
                throw HomeAssistantError.invalidResponse
            }
            return entities.compactMap { value in
                guard let entry = value.objectValue,
                      let entityID = entry["entity_id"]?.stringValue,
                      entry["disabled_by"]?.stringValue == nil else { return nil }
                return HomeAssistantEntityRegistryEntry(
                    entityID: entityID,
                    platform: entry["platform"]?.stringValue,
                    translationKey: entry["translation_key"]?.stringValue,
                    areaID: entry["area_id"]?.stringValue,
                    deviceID: entry["device_id"]?.stringValue,
                    name: entry["name"]?.stringValue ?? entry["original_name"]?.stringValue,
                    icon: entry["icon"]?.stringValue,
                    entityCategory: entry["entity_category"]?.stringValue,
                    isHidden: entry["hidden_by"]?.stringValue != nil
                )
            }
        }
    }

    public func fetchEntityRegistryForDisplay() async throws -> [HomeAssistantEntityRegistryEntry] {
        let value = try await command(type: "config/entity_registry/list_for_display")
        let root = value.objectValue
        guard let entities = root?["entities"]?.arrayValue ?? value.arrayValue else {
            recordDecodeFailure(operation: "config/entity_registry/list_for_display", value: value)
            throw HomeAssistantError.invalidResponse
        }
        let categories = root?["entity_categories"]?.objectValue ?? [:]
        return entities.compactMap { value in
            guard let entry = value.objectValue,
                  let entityID = entry["ei"]?.stringValue else { return nil }
            let category: String?
            if let raw = entry["ec"]?.doubleValue {
                category = categories[String(Int(raw))]?.stringValue
            } else {
                category = nil
            }
            return HomeAssistantEntityRegistryEntry(
                entityID: entityID,
                platform: entry["pl"]?.stringValue,
                translationKey: entry["tk"]?.stringValue,
                areaID: entry["ai"]?.stringValue,
                deviceID: entry["di"]?.stringValue,
                name: entry["en"]?.stringValue,
                icon: entry["ic"]?.stringValue,
                entityCategory: category,
                isHidden: entry["hb"]?.boolValue == true
            )
        }
    }

    public func fetchTranslationCatalog(
        language: String,
        categories: [String] = ["entity", "entity_component"]
    ) async -> HomeAssistantTranslationCatalog {
        var resources: [String: String] = [:]
        for category in categories {
            guard let value = try? await command(
                type: "frontend/get_translations",
                payload: [
                    "language": .string(language),
                    "category": .string(category),
                ]
            ), let translatedResources = value.objectValue?["resources"]?.objectValue else {
                continue
            }
            for (key, value) in translatedResources {
                if let text = value.stringValue { resources[key] = text }
            }
        }
        return HomeAssistantTranslationCatalog(language: language, resources: resources)
    }

    public func subscribeStateChanges() async throws {
        _ = try await command(
            type: "subscribe_events",
            payload: ["event_type": .string("state_changed")]
        )
    }

    @discardableResult
    public func callService(_ call: HomeAssistantServiceCall) async throws -> HomeAssistantJSONValue {
        try await command(
            type: "call_service",
            payload: HomeAssistantWebSocketCommandAdapter.serviceCallPayload(call)
        )
    }

    private func command(
        type: String,
        payload: [String: HomeAssistantJSONValue] = [:]
    ) async throws -> HomeAssistantJSONValue {
        guard authenticated, let socket else { throw HomeAssistantError.disconnected }
        let id = nextID
        nextID += 1
        let epoch = connectionEpoch.current
        var body = payload
        body["id"] = .number(Double(id))
        body["type"] = .string(type)
        let data = try JSONEncoder().encode(body)
        guard let text = String(data: data, encoding: .utf8) else { throw HomeAssistantError.invalidResponse }

        return try await withCheckedThrowingContinuation { continuation in
            pending[id] = PendingCommand(operation: type, continuation: continuation)
            outboundCommands.enqueue(
                .init(id: id, operation: type, text: text, epoch: epoch)
            )
            startCommandSenderIfNeeded(using: socket, epoch: epoch)
        }
    }

    private func startCommandSenderIfNeeded(
        using socket: URLSessionWebSocketTask,
        epoch: Int
    ) {
        guard commandSendTask == nil, connectionEpoch.isCurrent(epoch) else { return }
        commandSendTaskEpoch = epoch
        commandSendTask = Task { [weak self] in
            await self?.drainOutboundCommands(using: socket, epoch: epoch)
        }
    }

    private func drainOutboundCommands(
        using socket: URLSessionWebSocketTask,
        epoch: Int
    ) async {
        defer { finishCommandSender(epoch: epoch, socket: socket) }

        while !Task.isCancelled, connectionEpoch.isCurrent(epoch) {
            guard let command = outboundCommands.next(for: epoch) else { return }
            do {
                try await socket.send(.string(command.text))
            } catch {
                guard connectionEpoch.isCurrent(epoch) else { return }
                diagnostics.record(
                    category: "home_assistant.websocket",
                    name: "websocket_command_failed",
                    operation: command.operation,
                    endpoint: endpointURL,
                    error: error,
                    details: [
                        "stage": "send",
                        "commandID": String(command.id),
                        "connectionEpoch": String(epoch),
                    ]
                )
                failPending(id: command.id, error: error)
            }
        }
    }

    private func finishCommandSender(
        epoch: Int,
        socket: URLSessionWebSocketTask
    ) {
        guard commandSendTaskEpoch == epoch else { return }
        commandSendTask = nil
        commandSendTaskEpoch = nil
        guard connectionEpoch.isCurrent(epoch), !outboundCommands.isEmpty else { return }
        startCommandSenderIfNeeded(using: socket, epoch: epoch)
    }

    private func failPending(id: Int, error: Error) {
        pending.removeValue(forKey: id)?.continuation.resume(throwing: error)
    }

    private func receiveLoop(socket: URLSessionWebSocketTask, epoch: Int) async {
        do {
            while !Task.isCancelled {
                let message = try await socket.receive()
                guard connectionEpoch.isCurrent(epoch) else { return }
                let data: Data
                switch message {
                case .string(let text): data = Data(text.utf8)
                case .data(let raw): data = raw
                @unknown default: continue
                }
                let envelope: [String: HomeAssistantJSONValue]
                do {
                    envelope = try HomeAssistantWebSocketPayloadDecoder.decodeEnvelope(data)
                } catch {
                    diagnostics.record(
                        category: "home_assistant.websocket",
                        name: "websocket_message_decode_failed",
                        operation: "receive_envelope",
                        endpoint: endpointURL,
                        error: error,
                        responseData: data
                    )
                    throw error
                }
                try await process(envelope, socket: socket, epoch: epoch)
            }
        } catch {
            guard !Task.isCancelled,
                  !HomeAssistantErrorClassifier.isCancellation(error),
                  connectionEpoch.isCurrent(epoch) else { return }
            if !(error is DecodingError) {
                diagnostics.record(
                    category: "home_assistant.websocket",
                    name: "websocket_receive_failed",
                    operation: "receive_loop",
                    endpoint: endpointURL,
                    error: error
                )
            }
            failConnection(error, epoch: epoch)
        }
    }

    private func process(
        _ envelope: [String: HomeAssistantJSONValue],
        socket: URLSessionWebSocketTask,
        epoch: Int
    ) async throws {
        guard connectionEpoch.isCurrent(epoch) else { return }
        switch envelope["type"]?.stringValue {
        case "auth_required":
            try await sendAuthentication(using: socket)
        case "auth_ok":
            authenticated = true
            startHeartbeat(using: socket, epoch: epoch)
            authContinuation?.resume()
            authContinuation = nil
        case "auth_invalid":
            diagnostics.record(
                category: "home_assistant.websocket",
                name: "websocket_command_failed",
                operation: "authenticate",
                endpoint: endpointURL,
                error: HomeAssistantError.unauthorized
            )
            authContinuation?.resume(throwing: HomeAssistantError.unauthorized)
            authContinuation = nil
        case "result":
            guard let idValue = envelope["id"]?.doubleValue else { return }
            let id = Int(idValue)
            guard let command = pending.removeValue(forKey: id) else { return }
            if envelope["success"]?.boolValue == true {
                command.continuation.resume(returning: envelope["result"] ?? .null)
            } else {
                let commandError = HomeAssistantWebSocketCommandAdapter.commandError(
                    from: envelope["error"]
                )
                let responseData = try? JSONEncoder().encode(envelope["error"] ?? .null)
                var details = [
                    "stage": "result",
                    "commandID": String(id),
                    "connectionEpoch": String(connectionEpoch.current),
                ]
                if let errorCode = HomeAssistantWebSocketCommandAdapter.errorCode(
                    from: envelope["error"]
                ) {
                    details["errorCode"] = errorCode
                }
                diagnostics.record(
                    category: "home_assistant.websocket",
                    name: "websocket_command_failed",
                    operation: command.operation,
                    endpoint: endpointURL,
                    error: commandError,
                    responseData: responseData,
                    details: details
                )
                command.continuation.resume(throwing: commandError)
            }
        case "event":
            publishStateEvent(envelope["event"])
        case "ping":
            break
        default:
            break
        }
    }

    private func sendAuthentication(using socket: URLSessionWebSocketTask) async throws {
        let data = try JSONEncoder().encode([
            "type": HomeAssistantJSONValue.string("auth"),
            "access_token": HomeAssistantJSONValue.string(token),
        ])
        guard let text = String(data: data, encoding: .utf8) else { throw HomeAssistantError.invalidResponse }
        try await socket.send(.string(text))
    }

    private func publishStateEvent(_ value: HomeAssistantJSONValue?) {
        guard let event = value?.objectValue,
              let data = event["data"]?.objectValue,
              let newState = data["new_state"] else {
            diagnostics.record(
                category: "home_assistant.websocket",
                name: "state_event_decode_failed",
                operation: "state_changed",
                endpoint: endpointURL,
                responseData: value.flatMap { try? JSONEncoder().encode($0) },
                details: ["reason": "missing_new_state"]
            )
            return
        }
        do {
            let decoded = try HomeAssistantWebSocketPayloadDecoder.decodeState(newState)
            eventContinuation?.yield(decoded)
        } catch {
            diagnostics.record(
                category: "home_assistant.websocket",
                name: "state_event_decode_failed",
                operation: "state_changed",
                endpoint: endpointURL,
                error: error,
                responseData: try? JSONEncoder().encode(newState)
            )
        }
    }

    private func failConnection(_ error: Error, epoch: Int) {
        guard connectionEpoch.isCurrent(epoch) else { return }
        authenticated = false
        heartbeatTask?.cancel()
        heartbeatTask = nil
        authContinuation?.resume(throwing: error)
        authContinuation = nil
        for command in pending.values { command.continuation.resume(throwing: error) }
        pending.removeAll()
        eventContinuation?.finish()
        eventContinuation = nil
    }

    private func startHeartbeat(using socket: URLSessionWebSocketTask, epoch: Int) {
        heartbeatTask?.cancel()
        heartbeatTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(25))
                guard !Task.isCancelled, let self else { return }
                do {
                    guard await self.isCurrentConnection(epoch) else { return }
                    try await self.sendProtocolPing(using: socket)
                } catch {
                    guard !Task.isCancelled,
                          !HomeAssistantErrorClassifier.isCancellation(error) else { return }
                    await self.diagnostics.record(
                        category: "home_assistant.websocket",
                        name: "websocket_receive_failed",
                        operation: "heartbeat",
                        endpoint: self.endpointURL,
                        error: error
                    )
                    await self.failConnection(error, epoch: epoch)
                    return
                }
            }
        }
    }

    private func isCurrentConnection(_ epoch: Int) -> Bool {
        connectionEpoch.isCurrent(epoch)
    }

    private func sendProtocolPing(using socket: URLSessionWebSocketTask) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            socket.sendPing { error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume() }
            }
        }
    }

    private func decode<Value: Decodable>(
        _ type: Value.Type,
        from value: HomeAssistantJSONValue,
        operation: String
    ) throws -> Value {
        do {
            return try JSONDecoder().decode(Value.self, from: JSONEncoder().encode(value))
        } catch {
            recordDecodeFailure(operation: operation, value: value, error: error)
            throw HomeAssistantError.invalidResponse
        }
    }

    private func recordDecodeFailure(
        operation: String,
        value: HomeAssistantJSONValue,
        error: Error? = nil
    ) {
        diagnostics.record(
            category: "home_assistant.websocket",
            name: "response_decode_failed",
            operation: operation,
            endpoint: endpointURL,
            error: error,
            responseData: try? JSONEncoder().encode(value)
        )
    }
}

struct HomeAssistantWebSocketQueuedCommand: Equatable, Sendable {
    let id: Int
    let operation: String
    let text: String
    let epoch: Int
}

struct HomeAssistantWebSocketCommandQueue: Sendable {
    private var commands: [HomeAssistantWebSocketQueuedCommand] = []

    var isEmpty: Bool { commands.isEmpty }

    mutating func enqueue(_ command: HomeAssistantWebSocketQueuedCommand) {
        commands.append(command)
    }

    mutating func next(for epoch: Int) -> HomeAssistantWebSocketQueuedCommand? {
        while !commands.isEmpty {
            let command = commands.removeFirst()
            if command.epoch == epoch { return command }
        }
        return nil
    }

    mutating func removeAll() {
        commands.removeAll(keepingCapacity: true)
    }
}

enum HomeAssistantWebSocketCommandAdapter {
    static func serviceCallPayload(
        _ call: HomeAssistantServiceCall
    ) -> [String: HomeAssistantJSONValue] {
        var serviceData = call.data
        serviceData["entity_id"] = .string(call.targetEntityID)
        return [
            "domain": .string(call.domain),
            "service": .string(call.service),
            "service_data": .object(serviceData),
        ]
    }

    static func commandError(from value: HomeAssistantJSONValue?) -> HomeAssistantError {
        let object = value?.objectValue
        let message = normalized(object?["message"]?.stringValue)
        let code = normalized(object?["code"]?.stringValue)

        if let message, let code, !message.localizedCaseInsensitiveContains(code) {
            return .commandFailed("\(message)（\(code)）")
        }
        if let message { return .commandFailed(message) }
        if let code { return .commandFailed(code) }
        return .commandFailed("Home Assistant 未提供失败原因")
    }

    static func errorCode(from value: HomeAssistantJSONValue?) -> String? {
        normalized(value?.objectValue?["code"]?.stringValue)
    }

    private static func normalized(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else { return nil }
        return value
    }
}

struct HomeAssistantConnectionEpoch: Sendable {
    private(set) var current = 0

    @discardableResult
    mutating func advance() -> Int {
        current += 1
        return current
    }

    func isCurrent(_ value: Int) -> Bool {
        value == current
    }
}
