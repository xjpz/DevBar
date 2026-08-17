import Foundation

public enum HomeAssistantJSONValue: Codable, Equatable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: HomeAssistantJSONValue])
    case array([HomeAssistantJSONValue])
    case null

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(Double.self) { self = .number(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode([String: HomeAssistantJSONValue].self) { self = .object(value) }
        else { self = .array(try container.decode([HomeAssistantJSONValue].self)) }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }

    public var stringValue: String? {
        switch self {
        case .string(let value): value
        case .number(let value): value.formatted(.number.precision(.fractionLength(0...2)))
        case .bool(let value): value ? "true" : "false"
        default: nil
        }
    }

    public var doubleValue: Double? {
        switch self {
        case .number(let value): value
        case .string(let value): Double(value)
        default: nil
        }
    }

    public var boolValue: Bool? {
        switch self {
        case .bool(let value): value
        case .string("true"), .string("on"): true
        case .string("false"), .string("off"): false
        default: nil
        }
    }

    public var objectValue: [String: HomeAssistantJSONValue]? {
        guard case .object(let value) = self else { return nil }
        return value
    }

    public var arrayValue: [HomeAssistantJSONValue]? {
        guard case .array(let value) = self else { return nil }
        return value
    }
}

public struct HomeAssistantConnectionSettings: Codable, Equatable, Sendable {
    public var externalURL: String
    public var internalURL: String
    public var internalSSIDs: [String]
    public var lastKnownLocationName: String
    public var aiAnalysisEnabled: Bool
    public var showsDiagnosticEntities: Bool

    public init(
        externalURL: String = "",
        internalURL: String = "",
        internalSSIDs: [String] = [],
        lastKnownLocationName: String = "",
        aiAnalysisEnabled: Bool = false,
        showsDiagnosticEntities: Bool = false
    ) {
        self.externalURL = externalURL
        self.internalURL = internalURL
        self.internalSSIDs = internalSSIDs
        self.lastKnownLocationName = lastKnownLocationName
        self.aiAnalysisEnabled = aiAnalysisEnabled
        self.showsDiagnosticEntities = showsDiagnosticEntities
    }

    public var isConfigured: Bool {
        !externalURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private enum CodingKeys: String, CodingKey {
        case externalURL
        case internalURL
        case internalSSID
        case internalSSIDs
        case lastKnownLocationName
        case aiAnalysisEnabled
        case showsDiagnosticEntities
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        externalURL = try container.decodeIfPresent(String.self, forKey: .externalURL) ?? ""
        internalURL = try container.decodeIfPresent(String.self, forKey: .internalURL) ?? ""
        if let values = try container.decodeIfPresent([String].self, forKey: .internalSSIDs) {
            internalSSIDs = values
        } else if let legacyValue = try container.decodeIfPresent(String.self, forKey: .internalSSID), !legacyValue.isEmpty {
            internalSSIDs = [legacyValue]
        } else {
            internalSSIDs = []
        }
        lastKnownLocationName = try container.decodeIfPresent(String.self, forKey: .lastKnownLocationName) ?? ""
        aiAnalysisEnabled = try container.decodeIfPresent(Bool.self, forKey: .aiAnalysisEnabled) ?? false
        showsDiagnosticEntities = try container.decodeIfPresent(Bool.self, forKey: .showsDiagnosticEntities) ?? false
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(externalURL, forKey: .externalURL)
        try container.encode(internalURL, forKey: .internalURL)
        try container.encode(internalSSIDs, forKey: .internalSSIDs)
        try container.encode(lastKnownLocationName, forKey: .lastKnownLocationName)
        try container.encode(aiAnalysisEnabled, forKey: .aiAnalysisEnabled)
        try container.encode(showsDiagnosticEntities, forKey: .showsDiagnosticEntities)
    }
}

public enum HomeAssistantNetworkInterface: String, Equatable, Sendable {
    case wifi
    case cellular
    case other
    case unavailable
}

public enum HomeAssistantEndpointKind: String, Equatable, Sendable {
    case internalNetwork
    case externalNetwork
}

public struct HomeAssistantEndpointCandidate: Equatable, Sendable {
    public let kind: HomeAssistantEndpointKind
    public let url: URL

    public init(kind: HomeAssistantEndpointKind, url: URL) {
        self.kind = kind
        self.url = url
    }
}

public enum HomeAssistantConnectionState: Equatable, Sendable {
    case notConfigured
    case connecting(HomeAssistantEndpointKind)
    case connected(HomeAssistantEndpointKind)
    case reconnecting
    case offline
    case authenticationFailed
    case failed(String)
}

public struct HomeAssistantConfig: Codable, Equatable, Sendable {
    public let locationName: String
    public let timeZone: String?
    public let version: String?
    public let unitSystem: HomeAssistantUnitSystem?

    enum CodingKeys: String, CodingKey {
        case locationName = "location_name"
        case timeZone = "time_zone"
        case version
        case unitSystem = "unit_system"
    }
}

public struct HomeAssistantUnitSystem: Codable, Equatable, Sendable {
    public let temperature: String?
    public let length: String?
    public let mass: String?
    public let volume: String?
}

public struct HomeAssistantState: Codable, Equatable, Identifiable, Sendable {
    public let entityID: String
    public let state: String
    public let attributes: [String: HomeAssistantJSONValue]
    public let lastChanged: String?
    public let lastUpdated: String?

    public var id: String { entityID }
    public var domain: String { entityID.split(separator: ".", maxSplits: 1).first.map(String.init) ?? "" }
    public var friendlyName: String? { attributes["friendly_name"]?.stringValue }
    public var deviceClass: String? { attributes["device_class"]?.stringValue }

    enum CodingKeys: String, CodingKey {
        case entityID = "entity_id"
        case state
        case attributes
        case lastChanged = "last_changed"
        case lastUpdated = "last_updated"
    }
}

public struct HomeAssistantEntityRegistryEntry: Codable, Equatable, Identifiable, Sendable {
    public let entityID: String
    public let platform: String?
    public let translationKey: String?
    public let areaID: String?
    public let deviceID: String?
    public let name: String?
    public let icon: String?
    public let entityCategory: String?
    public let isHidden: Bool

    public var id: String { entityID }

    public init(
        entityID: String,
        platform: String? = nil,
        translationKey: String? = nil,
        areaID: String? = nil,
        deviceID: String? = nil,
        name: String? = nil,
        icon: String? = nil,
        entityCategory: String? = nil,
        isHidden: Bool = false
    ) {
        self.entityID = entityID
        self.platform = platform
        self.translationKey = translationKey
        self.areaID = areaID
        self.deviceID = deviceID
        self.name = name
        self.icon = icon
        self.entityCategory = entityCategory
        self.isHidden = isHidden
    }
}

public struct HomeAssistantArea: Codable, Equatable, Identifiable, Sendable {
    public let areaID: String
    public let name: String
    public let icon: String?
    public var id: String { areaID }

    enum CodingKeys: String, CodingKey {
        case areaID = "area_id"
        case name
        case icon
    }
}

public struct HomeAssistantDevice: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let name: String?
    public let nameByUser: String?
    public let areaID: String?
    public let manufacturer: String?
    public let model: String?

    public var displayName: String? { nameByUser?.nilIfBlank ?? name?.nilIfBlank }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case nameByUser = "name_by_user"
        case areaID = "area_id"
        case manufacturer
        case model
    }
}

public struct HomeAssistantService: Codable, Equatable, Sendable {
    public let domain: String
    public let services: [String: HomeAssistantJSONValue]

    public init(domain: String, services: [String: HomeAssistantJSONValue]) {
        self.domain = domain
        self.services = services
    }

    enum CodingKeys: String, CodingKey { case domain, services }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        domain = try container.decode(String.self, forKey: .domain)
        if let object = try? container.decode([String: HomeAssistantJSONValue].self, forKey: .services) {
            services = object
        } else {
            let names = try container.decode([String].self, forKey: .services)
            services = Dictionary(uniqueKeysWithValues: names.map { ($0, .null) })
        }
    }
}

public struct HomeAssistantRoom: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let icon: String?

    public init(id: String, name: String, icon: String? = nil) {
        self.id = id
        self.name = name
        self.icon = icon
    }
}

public struct HomeAssistantEntity: Codable, Equatable, Identifiable, Sendable {
    public let entityID: String
    public let deviceID: String?
    public let areaID: String?
    public let name: String
    public let domain: String
    public let deviceClass: String?
    public let icon: String?
    public let platform: String?
    public let translationKey: String?
    public let entityCategory: String?
    public let state: HomeAssistantState
    public let availableServices: Set<String>

    public var id: String { entityID }
    public var isAvailable: Bool { state.state != "unavailable" && state.state != "unknown" }
    public var isOn: Bool { ["on", "open", "unlocked", "playing", "home", "heat", "cool"].contains(state.state) }

    public init(
        entityID: String,
        deviceID: String?,
        areaID: String?,
        name: String,
        domain: String,
        deviceClass: String?,
        icon: String?,
        platform: String? = nil,
        translationKey: String? = nil,
        entityCategory: String? = nil,
        state: HomeAssistantState,
        availableServices: Set<String>
    ) {
        self.entityID = entityID
        self.deviceID = deviceID
        self.areaID = areaID
        self.name = name
        self.domain = domain
        self.deviceClass = deviceClass
        self.icon = icon
        self.platform = platform
        self.translationKey = translationKey
        self.entityCategory = entityCategory
        self.state = state
        self.availableServices = availableServices
    }
}

public struct HomeAssistantDeviceCard: Codable, Equatable, Identifiable, Sendable {
    public static let controllableDomains = Set([
        "light", "switch", "input_boolean", "fan", "cover", "climate", "lock",
        "scene", "script", "automation", "button",
    ])

    public let id: String
    public let name: String
    public let areaID: String?
    public let primaryEntityID: String
    public let entities: [HomeAssistantEntity]
    public let hasMultiplePrimaryControls: Bool

    public var primaryEntity: HomeAssistantEntity? {
        entities.first { $0.entityID == primaryEntityID }
    }

    public var controllableEntities: [HomeAssistantEntity] {
        entities.filter { Self.controllableDomains.contains($0.domain) }
    }

    public var sensorCount: Int {
        entities.count - controllableEntities.count
    }

    public var isAvailable: Bool {
        let controls = controllableEntities
        return (controls.isEmpty ? entities : controls).contains(where: \.isAvailable)
    }

    public var isActive: Bool {
        controllableEntities.contains { entity in
            switch entity.domain {
            case "light", "switch", "input_boolean", "fan":
                entity.isOn
            case "cover":
                ["open", "opening"].contains(entity.state.state)
            case "climate":
                entity.isAvailable && entity.state.state != "off"
            default:
                false
            }
        }
    }

    public var isVirtual: Bool { id.hasPrefix("entity:") }
}

public struct HomeAssistantSnapshot: Codable, Equatable, Sendable {
    public let config: HomeAssistantConfig
    public let rooms: [HomeAssistantRoom]
    public let entities: [HomeAssistantEntity]
    public let cards: [HomeAssistantDeviceCard]
    public let services: [HomeAssistantService]
    public let refreshedAt: Date

    public init(
        config: HomeAssistantConfig,
        rooms: [HomeAssistantRoom],
        entities: [HomeAssistantEntity],
        cards: [HomeAssistantDeviceCard],
        services: [HomeAssistantService],
        refreshedAt: Date = .now
    ) {
        self.config = config
        self.rooms = rooms
        self.entities = entities
        self.cards = cards
        self.services = services
        self.refreshedAt = refreshedAt
    }
}

public enum HomeAssistantSnapshotPhase: Codable, Equatable, Sendable {
    case empty
    case cached(savedAt: Date)
    case stateSynchronized
    case authoritative

    public var allowsControl: Bool {
        self == .authoritative
    }
}

public struct HomeAssistantSnapshotCacheEnvelope: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let instanceFingerprint: String
    public let savedAt: Date
    public let snapshot: HomeAssistantSnapshot

    public init(
        schemaVersion: Int,
        instanceFingerprint: String,
        savedAt: Date,
        snapshot: HomeAssistantSnapshot
    ) {
        self.schemaVersion = schemaVersion
        self.instanceFingerprint = instanceFingerprint
        self.savedAt = savedAt
        self.snapshot = snapshot
    }
}

public struct HomeAssistantDeviceVisibilitySettings: Codable, Equatable, Sendable {
    public var hiddenCardIDs: Set<String>

    public init(hiddenCardIDs: Set<String> = []) {
        self.hiddenCardIDs = hiddenCardIDs
    }
}

public enum HomeAssistantCardSize: String, Codable, CaseIterable, Equatable, Identifiable, Sendable {
    case compact
    case standard

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .compact: "小卡片"
        case .standard: "标准卡片"
        }
    }

    public var toggled: HomeAssistantCardSize {
        self == .compact ? .standard : .compact
    }
}

public struct HomeAssistantDashboardLayoutSettings: Codable, Equatable, Sendable {
    public static let schemaVersion = 1

    public let schemaVersion: Int
    public var cardOrderByRoom: [String: [String]]
    public var cardSizes: [String: HomeAssistantCardSize]

    public init(
        cardOrderByRoom: [String: [String]] = [:],
        cardSizes: [String: HomeAssistantCardSize] = [:],
        schemaVersion: Int = HomeAssistantDashboardLayoutSettings.schemaVersion
    ) {
        self.schemaVersion = schemaVersion
        self.cardOrderByRoom = cardOrderByRoom.mapValues(Self.uniqueNonEmptyValues)
        self.cardSizes = cardSizes
    }

    public mutating func setOrder(_ cardIDs: [String], forRoom roomID: String) {
        let normalized = Self.uniqueNonEmptyValues(cardIDs)
        if normalized.isEmpty {
            cardOrderByRoom.removeValue(forKey: roomID)
        } else {
            cardOrderByRoom[roomID] = normalized
        }
    }

    public mutating func setSize(_ size: HomeAssistantCardSize?, forCard cardID: String) {
        if let size {
            cardSizes[cardID] = size
        } else {
            cardSizes.removeValue(forKey: cardID)
        }
    }

    public mutating func preserveResolvedSize(_ size: HomeAssistantCardSize, forCard cardID: String) {
        guard cardSizes[cardID] == nil else { return }
        cardSizes[cardID] = size
    }

    private static func uniqueNonEmptyValues(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { !$0.isEmpty && seen.insert($0).inserted }
    }
}

public enum HomeAssistantDeviceDisplayType: String, Codable, CaseIterable, Equatable, Identifiable, Sendable {
    case switchDevice = "switch"
    case light
    case fan
    case airPurifier = "air.purifier"
    case airConditioner = "air.conditioner"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .switchDevice: "开关"
        case .light: "灯"
        case .fan: "风扇"
        case .airPurifier: "空气净化器"
        case .airConditioner: "空调"
        }
    }

    public var systemImage: String {
        switch self {
        case .switchDevice: "switch.2"
        case .light: "lightbulb.fill"
        case .fan: "fan.fill"
        case .airPurifier: "air.purifier.fill"
        case .airConditioner: "air.conditioner.horizontal.fill"
        }
    }

    public var systemImages: [String] {
        switch self {
        case .switchDevice:
            [
                "switch.2", "switch.programmable", "switch.programmable.fill",
                "lightswitch.on", "lightswitch.on.fill", "lightswitch.on.square",
                "lightswitch.on.square.fill", "lightswitch.off", "lightswitch.off.fill",
                "lightswitch.off.square", "lightswitch.off.square.fill", "powerplug.fill",
                "desktopcomputer",
            ]
        case .light:
            [
                "lightbulb.fill", "lightbulb.led.fill", "lightbulb.led.wide.fill",
                "lamp.table.fill", "lamp.floor.fill", "lamp.ceiling.fill", "chandelier.fill",
                "light.min", "light.max", "light.recessed", "light.recessed.fill",
                "light.recessed.3", "light.recessed.3.fill", "light.panel", "light.panel.fill",
                "light.ribbon", "light.ribbon.fill", "light.strip.2",
                "light.cylindrical.ceiling", "light.cylindrical.ceiling.fill",
                "light.overhead.right", "light.overhead.left", "light.beacon.min", "light.beacon.max",
            ]
        case .fan:
            [
                "fan.fill", "fan", "fan.circle", "fan.circle.fill", "fan.oscillation",
                "fan.oscillation.fill", "fan.desk", "fan.desk.fill", "fan.floor",
                "fan.floor.fill", "fan.ceiling", "fan.ceiling.fill", "fan.and.light.ceiling",
                "fan.badge.automatic", "fan.badge.automatic.fill", "fan.gauge.open",
            ]
        case .airPurifier:
            [
                "air.purifier.fill", "air.purifier", "aqi.low", "aqi.medium", "aqi.high",
                "wind", "wind.circle", "leaf.fill", "allergens.fill", "humidifier.fill",
                "dehumidifier.fill", "sensor.fill",
            ]
        case .airConditioner:
            [
                "air.conditioner.horizontal.fill", "air.conditioner", "air.conditioner.vertical",
                "air.conditioner.horizontal", "air.conditioner.vertical.fill",
                "snowflake", "snowflake.circle.fill", "thermometer.snowflake",
                "thermometer.medium", "wind.snow",
            ]
        }
    }

    public func normalizedSystemImage(_ systemImage: String?) -> String {
        guard let systemImage, systemImages.contains(systemImage) else { return self.systemImage }
        return systemImage
    }
}

public struct HomeAssistantDevicePresentation: Codable, Equatable, Sendable {
    public let customName: String?
    public let displayType: HomeAssistantDeviceDisplayType
    public let customSystemImage: String?
    public let customAreaID: String?

    public init(
        customName: String?,
        displayType: HomeAssistantDeviceDisplayType,
        systemImage: String? = nil,
        areaID: String? = nil
    ) {
        let normalizedName = customName?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .prefix(40)
        self.customName = normalizedName.map(String.init).flatMap { $0.isEmpty ? nil : $0 }
        self.displayType = displayType
        let normalizedSystemImage = displayType.normalizedSystemImage(systemImage)
        self.customSystemImage = normalizedSystemImage == displayType.systemImage ? nil : normalizedSystemImage
        self.customAreaID = areaID?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfBlank
    }

    public var systemImage: String {
        displayType.normalizedSystemImage(customSystemImage)
    }
}

public struct HomeAssistantDevicePresentationSettings: Codable, Equatable, Sendable {
    public var devices: [String: HomeAssistantDevicePresentation]

    public init(devices: [String: HomeAssistantDevicePresentation] = [:]) {
        self.devices = devices
    }
}

public struct HomeAssistantServiceCall: Equatable, Sendable {
    public let domain: String
    public let service: String
    public let targetEntityID: String
    public let data: [String: HomeAssistantJSONValue]
    public let requiresConfirmation: Bool

    public init(
        domain: String,
        service: String,
        targetEntityID: String,
        data: [String: HomeAssistantJSONValue] = [:],
        requiresConfirmation: Bool = false
    ) {
        self.domain = domain
        self.service = service
        self.targetEntityID = targetEntityID
        self.data = data
        self.requiresConfirmation = requiresConfirmation
    }
}

public struct HomeAssistantLayoutSuggestion: Codable, Equatable, Sendable {
    public let roomOrder: [String]
    public let featuredEntityIDs: [String]
    public let aliases: [String: String]
    public let suggestions: [String]

    public init(
        roomOrder: [String] = [],
        featuredEntityIDs: [String] = [],
        aliases: [String: String] = [:],
        suggestions: [String] = []
    ) {
        self.roomOrder = roomOrder
        self.featuredEntityIDs = featuredEntityIDs
        self.aliases = aliases
        self.suggestions = suggestions
    }
}

private extension String {
    var nilIfBlank: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
