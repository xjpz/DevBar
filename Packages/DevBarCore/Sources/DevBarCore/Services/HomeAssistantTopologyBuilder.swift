import Foundation

public enum HomeAssistantTopologyBuilder {
    public static let unassignedAreaID = "__unassigned__"

    public static func build(
        config: HomeAssistantConfig,
        states: [HomeAssistantState],
        registryEntries: [HomeAssistantEntityRegistryEntry],
        areas: [HomeAssistantArea],
        devices: [HomeAssistantDevice],
        services: [HomeAssistantService],
        showsDiagnosticEntities: Bool = false,
        refreshedAt: Date = .now
    ) -> HomeAssistantSnapshot {
        let registryByID = Dictionary(uniqueKeysWithValues: registryEntries.map { ($0.entityID, $0) })
        let deviceByID = Dictionary(uniqueKeysWithValues: devices.map { ($0.id, $0) })
        let discoveredServices = Dictionary(uniqueKeysWithValues: services.map { ($0.domain, Set($0.services.keys)) })

        let entities = states.compactMap { state -> HomeAssistantEntity? in
            let entry = registryByID[state.entityID]
            if entry?.isHidden == true { return nil }
            if !showsDiagnosticEntities {
                if entry?.entityCategory == "diagnostic" { return nil }
                if entry?.entityCategory == "config" {
                    guard entry?.deviceID != nil,
                          retainedConfigurationControlDomains.contains(state.domain) else { return nil }
                }
            }

            let device = entry?.deviceID.flatMap { deviceByID[$0] }
            let areaID = entry?.areaID ?? device?.areaID
            let name = entry?.name?.trimmedNonEmpty
                ?? state.friendlyName?.trimmedNonEmpty
                ?? device?.displayName
                ?? state.entityID
            return HomeAssistantEntity(
                entityID: state.entityID,
                deviceID: entry?.deviceID,
                areaID: areaID,
                name: name,
                domain: state.domain,
                deviceClass: state.deviceClass,
                icon: entry?.icon ?? state.attributes["icon"]?.stringValue,
                platform: entry?.platform,
                translationKey: entry?.translationKey,
                entityCategory: entry?.entityCategory,
                state: state,
                availableServices: (discoveredServices[state.domain] ?? []).union(standardServices[state.domain] ?? [])
            )
        }.sorted { lhs, rhs in
            lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }

        let grouped = Dictionary(grouping: entities) { entity in
            entity.deviceID ?? "entity:\(entity.entityID)"
        }
        let cards = grouped.compactMap { groupID, values -> HomeAssistantDeviceCard? in
            let isPhysicalDevice = values.first?.deviceID != nil
            guard isPhysicalDevice || values.contains(where: { HomeAssistantDeviceCard.controllableDomains.contains($0.domain) }) else {
                return nil
            }
            let presented = presentedEntities(from: values, isPhysicalDevice: isPhysicalDevice)
            if isPhysicalDevice, presented.allSatisfy({ $0.entityCategory == "config" }) {
                return nil
            }
            let ranked = HomeAssistantPrimaryEntityPolicy.rankedCandidates(
                presented,
                rank: HomeAssistantPrimaryEntityPolicy.topologyRank
            )
            let best = HomeAssistantPrimaryEntityPolicy.equivalentTopCandidates(
                ranked,
                rank: HomeAssistantPrimaryEntityPolicy.topologyRank
            )
            let primary = ranked.first
            let bestRank = primary.map(HomeAssistantPrimaryEntityPolicy.topologyRank) ?? Int.max
            let device = values.first?.deviceID.flatMap { deviceByID[$0] }
            return HomeAssistantDeviceCard(
                id: groupID,
                name: device?.displayName ?? primary?.name ?? groupID,
                areaID: values.compactMap(\.areaID).first,
                primaryEntityID: primary?.entityID ?? presented[0].entityID,
                entities: presented.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending },
                hasMultiplePrimaryControls: best.count > 1 && bestRank < 3
            )
        }.sorted { lhs, rhs in
            lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }

        let knownAreaIDs = Set(cards.compactMap(\.areaID))
        var rooms = areas
            .filter { knownAreaIDs.contains($0.areaID) }
            .map { HomeAssistantRoom(id: $0.areaID, name: $0.name, icon: $0.icon) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        if cards.contains(where: { $0.areaID == nil }) {
            rooms.append(HomeAssistantRoom(id: unassignedAreaID, name: "未分配", icon: "questionmark.circle"))
        }

        return HomeAssistantSnapshot(
            config: config,
            rooms: rooms,
            entities: entities,
            cards: cards,
            services: services,
            refreshedAt: refreshedAt
        )
    }

    public static func applying(
        state: HomeAssistantState,
        to snapshot: HomeAssistantSnapshot
    ) -> HomeAssistantSnapshot {
        let states = snapshot.entities.map { entity in
            entity.entityID == state.entityID ? state : entity.state
        }
        let registry = snapshot.entities.map { entity in
            HomeAssistantEntityRegistryEntry(
                entityID: entity.entityID,
                platform: entity.platform,
                translationKey: entity.translationKey,
                areaID: entity.areaID,
                deviceID: entity.deviceID,
                name: entity.name,
                icon: entity.icon,
                entityCategory: entity.entityCategory
            )
        }
        let areas = snapshot.rooms.compactMap { room -> HomeAssistantArea? in
            guard room.id != unassignedAreaID else { return nil }
            return HomeAssistantArea(areaID: room.id, name: room.name, icon: room.icon)
        }
        return build(
            config: snapshot.config,
            states: states,
            registryEntries: registry,
            areas: areas,
            devices: [],
            services: snapshot.services,
            showsDiagnosticEntities: true,
            refreshedAt: snapshot.refreshedAt
        )
    }

    private static func presentedEntities(
        from entities: [HomeAssistantEntity],
        isPhysicalDevice: Bool
    ) -> [HomeAssistantEntity] {
        guard isPhysicalDevice else { return entities }

        let majorControlDomains = Set(["light", "fan", "cover", "climate", "lock"])
        let majorControls = entities.filter { majorControlDomains.contains($0.domain) }
        let genericControls = entities.filter {
            ["switch", "input_boolean"].contains($0.domain) && !isLikelyConfigurationHelper($0)
        }
        let selectableControls = entities.filter {
            ["select", "input_select"].contains($0.domain) && !isLikelyConfigurationHelper($0)
        }
        let configurationActions = entities.filter {
            $0.domain == "button"
                && $0.entityCategory == "config"
                && !isLikelyConfigurationHelper($0)
        }
        let persistentControls = majorControls + genericControls + selectableControls + configurationActions
        let informativeEntities = entities.filter(isInformativeEntity)
        let result = persistentControls + informativeEntities

        if !result.isEmpty { return result.uniquedByEntityID() }

        let actions = entities.filter { ["scene", "script", "automation", "button"].contains($0.domain) }
        if !actions.isEmpty { return actions }

        return entities.sorted {
            HomeAssistantPrimaryEntityPolicy.topologyRank($0)
                < HomeAssistantPrimaryEntityPolicy.topologyRank($1)
        }.prefix(1).map { $0 }
    }

    private static func isLikelyConfigurationHelper(_ entity: HomeAssistantEntity) -> Bool {
        let hint = "\(entity.entityID) \(entity.name)".lowercased()
        return [
            "flex_switch", "滚动开关", "factory_reset", "恢复出厂", "参数重置",
            "factory", "reset", "校准", "calibration", "firmware", "固件",
            "default_state", "默认状态", "dimming_mode", "灯光变化",
        ].contains { hint.contains($0) }
    }

    private static func isInformativeEntity(_ entity: HomeAssistantEntity) -> Bool {
        switch entity.domain {
        case "sensor":
            return informativeSensorClasses.contains(entity.deviceClass ?? "")
        case "binary_sensor":
            return informativeBinarySensorClasses.contains(entity.deviceClass ?? "")
        default:
            return false
        }
    }

    private static let informativeSensorClasses = Set([
        "aqi", "battery", "carbon_dioxide", "carbon_monoxide", "current", "energy",
        "gas", "humidity", "illuminance", "moisture", "pm1", "pm10", "pm25",
        "power", "pressure", "signal_strength", "temperature", "volatile_organic_compounds",
        "voltage", "water",
    ])

    private static let informativeBinarySensorClasses = Set([
        "battery", "battery_charging", "connectivity", "door", "garage_door", "gas",
        "heat", "lock", "moisture", "motion", "moving", "occupancy", "opening", "plug",
        "power", "presence", "problem", "running", "safety", "smoke", "sound", "tamper",
        "vibration", "window",
    ])

    private static let standardServices: [String: Set<String>] = [
        "light": ["turn_on", "turn_off", "toggle"],
        "switch": ["turn_on", "turn_off", "toggle"],
        "input_boolean": ["turn_on", "turn_off", "toggle"],
        "fan": ["turn_on", "turn_off", "toggle", "set_percentage", "set_preset_mode", "oscillate", "set_direction"],
        "cover": ["open_cover", "close_cover", "stop_cover", "set_cover_position"],
        "climate": [
            "turn_on", "turn_off", "toggle", "set_temperature", "set_hvac_mode",
            "set_fan_mode", "set_preset_mode", "set_swing_mode", "set_swing_horizontal_mode",
        ],
        "select": ["select_option"],
        "input_select": ["select_option"],
        "lock": ["lock", "unlock"],
        "scene": ["turn_on"],
        "script": ["turn_on"],
        "automation": ["trigger"],
        "button": ["press"],
    ]

    private static let retainedConfigurationControlDomains = Set([
        "switch", "input_boolean", "select", "input_select", "button",
    ])
}

private extension Array where Element == HomeAssistantEntity {
    func uniquedByEntityID() -> [HomeAssistantEntity] {
        var seen = Set<String>()
        return filter { seen.insert($0.entityID).inserted }
    }
}

private extension String {
    var trimmedNonEmpty: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
