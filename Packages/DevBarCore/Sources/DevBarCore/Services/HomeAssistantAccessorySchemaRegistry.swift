import Foundation

public struct HomeAssistantAccessorySchema: Equatable, Sendable {
    public let kind: HomeAssistantAccessoryKind
    public let primaryDomains: [String]
    public let supportedRoles: Set<HomeAssistantAccessoryRole>

    public init(
        kind: HomeAssistantAccessoryKind,
        primaryDomains: [String],
        supportedRoles: Set<HomeAssistantAccessoryRole>
    ) {
        self.kind = kind
        self.primaryDomains = primaryDomains
        self.supportedRoles = supportedRoles
    }

    public func acceptsPrimary(_ entity: HomeAssistantEntity) -> Bool {
        primaryDomains.contains(entity.domain)
    }
}

public enum HomeAssistantAccessorySchemaRegistry {
    public static func schema(for kind: HomeAssistantAccessoryKind) -> HomeAssistantAccessorySchema {
        schemas[kind] ?? schemas[.generic]!
    }

    public static func allowedDomains(
        for role: HomeAssistantAccessoryRole,
        kind: HomeAssistantAccessoryKind
    ) -> Set<String> {
        switch role {
        case .primaryControl:
            return Set(schema(for: kind).primaryDomains)
        case .power, .childControl, .indicator:
            return ["switch", "input_boolean", "light", "fan", "climate"]
        case .mode:
            return ["select", "input_select", "climate", "fan"]
        case .temperature, .humidity, .airQuality, .particulateMatter,
             .filterLife, .powerUsage, .energyUsage:
            return ["sensor", "number"]
        case .activity, .alert:
            return ["binary_sensor", "sensor", "fan", "climate", "switch"]
        case .action:
            return ["button", "scene", "script", "automation"]
        case .diagnostic:
            return []
        }
    }

    private static let schemas: [HomeAssistantAccessoryKind: HomeAssistantAccessorySchema] = [
        .switchDevice: .init(
            kind: .switchDevice,
            primaryDomains: ["switch", "input_boolean"],
            supportedRoles: [.primaryControl, .power, .childControl, .powerUsage, .energyUsage, .indicator, .alert, .action]
        ),
        .light: .init(
            kind: .light,
            primaryDomains: ["light", "switch"],
            supportedRoles: [.primaryControl, .power, .powerUsage, .energyUsage, .indicator, .alert, .action]
        ),
        .fan: .init(
            kind: .fan,
            primaryDomains: ["fan", "switch"],
            supportedRoles: [.primaryControl, .power, .childControl, .mode, .temperature, .humidity, .airQuality, .indicator, .activity, .alert, .action]
        ),
        .airPurifier: .init(
            kind: .airPurifier,
            primaryDomains: ["fan", "switch"],
            supportedRoles: [.primaryControl, .power, .childControl, .mode, .temperature, .humidity, .airQuality, .particulateMatter, .filterLife, .indicator, .activity, .alert, .action]
        ),
        .airConditioner: .init(
            kind: .airConditioner,
            primaryDomains: ["climate", "switch", "fan"],
            supportedRoles: [.primaryControl, .power, .childControl, .mode, .temperature, .humidity, .indicator, .activity, .alert, .action]
        ),
        .sensorGroup: .init(
            kind: .sensorGroup,
            primaryDomains: ["sensor", "binary_sensor"],
            supportedRoles: [.primaryControl, .temperature, .humidity, .airQuality, .particulateMatter, .filterLife, .powerUsage, .energyUsage, .activity, .alert]
        ),
        .generic: .init(
            kind: .generic,
            primaryDomains: ["light", "switch", "input_boolean", "fan", "cover", "climate", "lock"],
            supportedRoles: Set(HomeAssistantAccessoryRole.allCases)
        ),
    ]
}
