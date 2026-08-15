import Foundation

public enum HomeAssistantAccessoryKind: String, Codable, CaseIterable, Equatable, Identifiable, Sendable {
    case switchDevice = "switch"
    case light
    case fan
    case airPurifier = "air.purifier"
    case airConditioner = "air.conditioner"
    case sensorGroup = "sensor.group"
    case generic

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .switchDevice: "开关"
        case .light: "灯"
        case .fan: "风扇"
        case .airPurifier: "空气净化器"
        case .airConditioner: "空调"
        case .sensorGroup: "传感器"
        case .generic: "通用设备"
        }
    }

    public var systemImage: String {
        if let legacyDisplayType { return legacyDisplayType.systemImage }
        return switch self {
        case .sensorGroup: "sensor.fill"
        case .generic: "square.stack.3d.up.fill"
        default: "powerplug.fill"
        }
    }

    public var systemImages: [String] {
        if let legacyDisplayType { return legacyDisplayType.systemImages }
        return switch self {
        case .sensorGroup:
            ["sensor.fill", "thermometer.medium", "humidity.fill", "aqi.medium"]
        case .generic:
            ["square.stack.3d.up.fill", "powerplug.fill", "slider.horizontal.3"]
        default:
            [systemImage]
        }
    }

    public var legacyDisplayType: HomeAssistantDeviceDisplayType? {
        switch self {
        case .switchDevice: .switchDevice
        case .light: .light
        case .fan: .fan
        case .airPurifier: .airPurifier
        case .airConditioner: .airConditioner
        case .sensorGroup, .generic: nil
        }
    }

    public init(_ displayType: HomeAssistantDeviceDisplayType) {
        switch displayType {
        case .switchDevice: self = .switchDevice
        case .light: self = .light
        case .fan: self = .fan
        case .airPurifier: self = .airPurifier
        case .airConditioner: self = .airConditioner
        }
    }

    public func normalizedSystemImage(_ systemImage: String?) -> String {
        guard let systemImage, systemImages.contains(systemImage) else { return self.systemImage }
        return systemImage
    }
}

public enum HomeAssistantAccessoryRole: String, Codable, CaseIterable, Equatable, Identifiable, Sendable {
    case primaryControl
    case power
    case childControl
    case mode
    case temperature
    case humidity
    case airQuality
    case particulateMatter
    case filterLife
    case powerUsage
    case energyUsage
    case indicator
    case activity
    case alert
    case action
    case diagnostic

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .primaryControl: "主要控制"
        case .power: "总开关"
        case .childControl: "辅助控制"
        case .mode: "模式"
        case .temperature: "温度"
        case .humidity: "湿度"
        case .airQuality: "空气质量"
        case .particulateMatter: "颗粒物"
        case .filterLife: "滤芯寿命"
        case .powerUsage: "当前功率"
        case .energyUsage: "累计电量"
        case .indicator: "指示状态"
        case .activity: "运行状态"
        case .alert: "告警"
        case .action: "操作"
        case .diagnostic: "诊断"
        }
    }
}

public struct HomeAssistantRoleBinding: Codable, Equatable, Sendable {
    public let role: HomeAssistantAccessoryRole
    public let entityIDs: [String]

    public init(role: HomeAssistantAccessoryRole, entityIDs: [String]) {
        self.role = role
        self.entityIDs = entityIDs.reduce(into: []) { result, entityID in
            if !entityID.isEmpty, !result.contains(entityID) { result.append(entityID) }
        }
    }
}

public enum HomeAssistantClassificationSource: String, Codable, Equatable, Sendable {
    case automatic
    case migrated
    case user
}

public struct HomeAssistantClassificationMetadata: Codable, Equatable, Sendable {
    public let confidence: Double
    public let source: HomeAssistantClassificationSource
    public let reasons: [String]
    public let needsReview: Bool

    public init(
        confidence: Double,
        source: HomeAssistantClassificationSource,
        reasons: [String],
        needsReview: Bool
    ) {
        self.confidence = min(1, max(0, confidence))
        self.source = source
        self.reasons = reasons
        self.needsReview = needsReview
    }
}

public struct HomeAssistantAccessoryPresentation: Codable, Equatable, Identifiable, Sendable {
    public static let schemaVersion = 2

    public let schemaVersion: Int
    public let id: String
    public let sourceDeviceIDs: [String]
    public let kind: HomeAssistantAccessoryKind
    public let bindings: [HomeAssistantRoleBinding]
    public let explicitlyUnboundRoles: Set<HomeAssistantAccessoryRole>?
    public let autoClassification: HomeAssistantClassificationMetadata?
    public let customName: String?
    public let customAreaID: String?
    public let customSystemImage: String?

    public init(
        id: String,
        sourceDeviceIDs: [String] = [],
        kind: HomeAssistantAccessoryKind,
        bindings: [HomeAssistantRoleBinding] = [],
        explicitlyUnboundRoles: Set<HomeAssistantAccessoryRole> = [],
        autoClassification: HomeAssistantClassificationMetadata? = nil,
        customName: String? = nil,
        customAreaID: String? = nil,
        customSystemImage: String? = nil,
        schemaVersion: Int = HomeAssistantAccessoryPresentation.schemaVersion
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.sourceDeviceIDs = sourceDeviceIDs.reduce(into: []) { result, deviceID in
            if !deviceID.isEmpty, !result.contains(deviceID) { result.append(deviceID) }
        }
        self.kind = kind
        self.bindings = bindings
        self.explicitlyUnboundRoles = explicitlyUnboundRoles.isEmpty
            ? nil
            : explicitlyUnboundRoles
        self.autoClassification = autoClassification
        self.customName = Self.normalizedText(customName, maximumLength: 40)
        self.customAreaID = Self.normalizedText(customAreaID, maximumLength: 128)
        let normalizedImage = kind.normalizedSystemImage(customSystemImage)
        self.customSystemImage = normalizedImage == kind.systemImage ? nil : normalizedImage
    }

    public init(
        id: String,
        sourceDeviceIDs: [String],
        legacy: HomeAssistantDevicePresentation,
        bindings: [HomeAssistantRoleBinding] = []
    ) {
        self.init(
            id: id,
            sourceDeviceIDs: sourceDeviceIDs,
            kind: HomeAssistantAccessoryKind(legacy.displayType),
            bindings: bindings,
            autoClassification: .init(
                confidence: bindings.isEmpty ? 0.7 : 1,
                source: .migrated,
                reasons: ["从旧版设备展示设置迁移"],
                needsReview: bindings.isEmpty
            ),
            customName: legacy.customName,
            customAreaID: legacy.customAreaID,
            customSystemImage: legacy.customSystemImage
        )
    }

    public var systemImage: String {
        kind.normalizedSystemImage(customSystemImage)
    }

    public func entityIDs(for role: HomeAssistantAccessoryRole) -> [String] {
        bindings.first(where: { $0.role == role })?.entityIDs ?? []
    }

    private static func normalizedText(_ value: String?, maximumLength: Int) -> String? {
        guard let value else { return nil }
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }
        return String(normalized.prefix(maximumLength))
    }
}

public struct HomeAssistantAccessoryPresentationSettings: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public var accessories: [String: HomeAssistantAccessoryPresentation]

    public init(
        schemaVersion: Int = HomeAssistantAccessoryPresentation.schemaVersion,
        accessories: [String: HomeAssistantAccessoryPresentation] = [:]
    ) {
        self.schemaVersion = schemaVersion
        self.accessories = accessories
    }
}

public struct HomeAssistantAccessoryGroupingSettings: Codable, Equatable, Sendable {
    public static let schemaVersion = 1

    public let schemaVersion: Int
    public var splitEntityIDsBySourceCardID: [String: [String]]

    public init(
        splitEntityIDsBySourceCardID: [String: [String]] = [:],
        schemaVersion: Int = HomeAssistantAccessoryGroupingSettings.schemaVersion
    ) {
        self.schemaVersion = schemaVersion
        self.splitEntityIDsBySourceCardID = splitEntityIDsBySourceCardID.reduce(
            into: [String: [String]]()
        ) { result, pair in
            let sourceCardID = pair.key.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !sourceCardID.isEmpty else { return }
            var seen = Set<String>()
            let entityIDs = pair.value
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty && seen.insert($0).inserted }
            if !entityIDs.isEmpty {
                result[sourceCardID] = entityIDs
            }
        }
    }

    public func splitEntityIDs(for sourceCardID: String) -> Set<String> {
        Set(splitEntityIDsBySourceCardID[sourceCardID] ?? [])
    }

    public mutating func setSplitEntityIDs(_ entityIDs: Set<String>, for sourceCardID: String) {
        let normalized = entityIDs
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .sorted()
        if normalized.isEmpty {
            splitEntityIDsBySourceCardID.removeValue(forKey: sourceCardID)
        } else {
            splitEntityIDsBySourceCardID[sourceCardID] = normalized
        }
    }
}

public struct HomeAssistantAccessory: Equatable, Identifiable, Sendable {
    public let id: String
    public let sourceCard: HomeAssistantDeviceCard
    public let sourceCardID: String
    public let splitEntityID: String?
    public let kind: HomeAssistantAccessoryKind
    public let name: String
    public let areaID: String?
    public let systemImage: String
    public let bindings: [HomeAssistantRoleBinding]
    public let classification: HomeAssistantClassificationMetadata
    public let isUserConfigured: Bool

    public init(
        id: String,
        sourceCard: HomeAssistantDeviceCard,
        sourceCardID: String? = nil,
        splitEntityID: String? = nil,
        kind: HomeAssistantAccessoryKind,
        name: String,
        areaID: String?,
        systemImage: String,
        bindings: [HomeAssistantRoleBinding],
        classification: HomeAssistantClassificationMetadata,
        isUserConfigured: Bool
    ) {
        self.id = id
        self.sourceCard = sourceCard
        self.sourceCardID = sourceCardID ?? sourceCard.id
        self.splitEntityID = splitEntityID
        self.kind = kind
        self.name = name
        self.areaID = areaID
        self.systemImage = systemImage
        self.bindings = bindings
        self.classification = classification
        self.isUserConfigured = isUserConfigured
    }

    public var entities: [HomeAssistantEntity] { sourceCard.entities }
    public var needsReview: Bool { classification.needsReview }
    public var isSplitAccessory: Bool { splitEntityID != nil }

    public func entityIDs(for role: HomeAssistantAccessoryRole) -> [String] {
        bindings.first(where: { $0.role == role })?.entityIDs ?? []
    }

    public func entities(for role: HomeAssistantAccessoryRole) -> [HomeAssistantEntity] {
        let ids = Set(entityIDs(for: role))
        return entities.filter { ids.contains($0.entityID) }
    }

    public var primaryControlEntity: HomeAssistantEntity? {
        entities(for: .primaryControl).first
    }

    public var powerEntity: HomeAssistantEntity? {
        entities(for: .power).first
    }

    public var quickControlEntity: HomeAssistantEntity? {
        guard !needsReview else { return nil }
        return powerEntity ?? primaryControlEntity
    }

    public var boundEntityIDs: Set<String> {
        Set(bindings.flatMap(\.entityIDs))
    }

    public var otherEntities: [HomeAssistantEntity] {
        entities.filter { !boundEntityIDs.contains($0.entityID) }
    }
}

public struct HomeAssistantAccessoryControlProjection: Equatable, Sendable {
    public let masterEntity: HomeAssistantEntity?
    public let childEntities: [HomeAssistantEntity]
    public let usesChildControlGrid: Bool

    public init(accessory: HomeAssistantAccessory) {
        let masterEntity = accessory.powerEntity ?? accessory.primaryControlEntity
        self.masterEntity = masterEntity

        let directlyControllableDomains = Set([
            "switch", "input_boolean", "light", "fan",
        ])
        let roles: [HomeAssistantAccessoryRole] = [
            .power, .primaryControl, .childControl, .indicator,
        ]
        var seenEntityIDs = Set<String>()
        childEntities = roles
            .flatMap { accessory.entities(for: $0) }
            .filter { entity in
                entity.entityID != masterEntity?.entityID
                    && directlyControllableDomains.contains(entity.domain)
                    && seenEntityIDs.insert(entity.entityID).inserted
            }
        usesChildControlGrid = accessory.kind == .switchDevice
            && masterEntity != nil
            && !childEntities.isEmpty
    }
}

public enum HomeAssistantAccessoryAvailability: String, Codable, Equatable, Sendable {
    case available
    case partiallyAvailable
    case unavailable
    case unknown
}

public enum HomeAssistantAccessoryPowerState: String, Codable, Equatable, Sendable {
    case on
    case off
    case standby
    case notApplicable
    case unknown
}

public enum HomeAssistantAccessoryActivityState: String, Codable, Equatable, Sendable {
    case idle
    case running
    case heating
    case cooling
    case drying
    case fanOnly
    case opening
    case closing
    case unknown
}

public enum HomeAssistantAccessoryTone: String, Codable, Equatable, Sendable {
    case neutral
    case active
    case warning
    case unavailable
}

public struct HomeAssistantAccessoryAlert: Codable, Equatable, Identifiable, Sendable {
    public let entityID: String
    public let text: String
    public var id: String { entityID }

    public init(entityID: String, text: String) {
        self.entityID = entityID
        self.text = text
    }
}

public struct HomeAssistantAccessorySemanticState: Equatable, Sendable {
    public let availability: HomeAssistantAccessoryAvailability
    public let power: HomeAssistantAccessoryPowerState
    public let activity: HomeAssistantAccessoryActivityState?
    public let alerts: [HomeAssistantAccessoryAlert]
    public let primaryText: String
    public let secondaryText: String?
    public let tone: HomeAssistantAccessoryTone
    public let isCountedAsOn: Bool

    public init(
        availability: HomeAssistantAccessoryAvailability,
        power: HomeAssistantAccessoryPowerState,
        activity: HomeAssistantAccessoryActivityState?,
        alerts: [HomeAssistantAccessoryAlert],
        primaryText: String,
        secondaryText: String?,
        tone: HomeAssistantAccessoryTone,
        isCountedAsOn: Bool
    ) {
        self.availability = availability
        self.power = power
        self.activity = activity
        self.alerts = alerts
        self.primaryText = primaryText
        self.secondaryText = secondaryText
        self.tone = tone
        self.isCountedAsOn = isCountedAsOn
    }
}

public struct HomeAssistantStatePresentation: Equatable, Sendable {
    public let title: String
    public let detail: String?
    public let accessibilityText: String
    public let tone: HomeAssistantAccessoryTone

    public init(
        title: String,
        detail: String? = nil,
        accessibilityText: String? = nil,
        tone: HomeAssistantAccessoryTone = .neutral
    ) {
        self.title = title
        self.detail = detail
        self.accessibilityText = accessibilityText ?? [title, detail].compactMap { $0 }.joined(separator: "，")
        self.tone = tone
    }
}
