import Foundation

public enum HomeAssistantAccessoryStateResolver {
    public static func resolve(
        _ accessory: HomeAssistantAccessory,
        translations: HomeAssistantTranslationCatalog? = nil,
        locale: Locale = .current
    ) -> HomeAssistantAccessorySemanticState {
        let statusOwner = accessory.powerEntity ?? accessory.primaryControlEntity
        let currentTemperature = resolvedCurrentTemperature(accessory)
        let aggregateControls = aggregateControlEntities(in: accessory)
        let usesAggregateState = accessory.needsReview
            && accessory.powerEntity == nil
            && aggregateControls.count > 1
        let availability = usesAggregateState
            ? resolvedAvailability(of: aggregateControls)
            : resolvedAvailability(accessory, statusOwner: statusOwner)
        let alerts = accessory.entities(for: .alert).compactMap { entity -> HomeAssistantAccessoryAlert? in
            guard entity.isAvailable, isAlertActive(entity) else { return nil }
            return HomeAssistantAccessoryAlert(
                entityID: entity.entityID,
                text: HomeAssistantStateFormatter.stateText(
                    for: entity,
                    role: .alert,
                    translations: translations,
                    locale: locale
                )
            )
        }

        if availability == .unavailable || availability == .unknown {
            return HomeAssistantAccessorySemanticState(
                availability: availability,
                power: .unknown,
                activity: nil,
                alerts: alerts,
                primaryText: availability == .unavailable ? "不可用" : "状态未知",
                secondaryText: auxiliaryText(
                    accessory,
                    excluding: statusOwner?.entityID,
                    translations: translations,
                    locale: locale
                ),
                currentTemperature: currentTemperature,
                tone: .unavailable,
                isCountedAsOn: false
            )
        }

        if usesAggregateState {
            let activeCount = aggregateControls.filter(isControlActive).count
            let availableCount = aggregateControls.filter(\.isAvailable).count
            let primaryText: String
            if availableCount == 0 {
                primaryText = "不可用"
            } else if activeCount == 0 {
                primaryText = "全部关闭"
            } else {
                primaryText = "\(activeCount) 个开启"
            }
            return HomeAssistantAccessorySemanticState(
                availability: availability,
                power: activeCount > 0 ? .on : .off,
                activity: resolvedActivity(accessory),
                alerts: alerts,
                primaryText: primaryText,
                secondaryText: "\(aggregateControls.count) 个控制，可在设置中拆分",
                currentTemperature: currentTemperature,
                tone: !alerts.isEmpty ? .warning : (activeCount > 0 ? .active : .neutral),
                isCountedAsOn: activeCount > 0
            )
        }

        let power = resolvedPower(statusOwner, kind: accessory.kind)
        let activity = resolvedActivity(accessory)
        let primaryText = primaryText(
            owner: statusOwner,
            power: power,
            kind: accessory.kind,
            translations: translations,
            locale: locale
        )
        return HomeAssistantAccessorySemanticState(
            availability: availability,
            power: power,
            activity: activity,
            alerts: alerts,
            primaryText: primaryText,
            secondaryText: auxiliaryText(
                accessory,
                excluding: statusOwner?.entityID,
                translations: translations,
                locale: locale
            ),
            currentTemperature: currentTemperature,
            tone: !alerts.isEmpty ? .warning : (power == .on ? .active : .neutral),
            isCountedAsOn: power == .on
        )
    }

    private static func resolvedAvailability(
        _ accessory: HomeAssistantAccessory,
        statusOwner: HomeAssistantEntity?
    ) -> HomeAssistantAccessoryAvailability {
        if let statusOwner {
            guard statusOwner.state.state != "unknown" else { return .unknown }
            guard statusOwner.isAvailable else { return .unavailable }
        }
        let availableCount = accessory.entities.filter(\.isAvailable).count
        if availableCount == 0 { return accessory.entities.isEmpty ? .unknown : .unavailable }
        if availableCount < accessory.entities.count { return .partiallyAvailable }
        return .available
    }

    private static func resolvedAvailability(
        of entities: [HomeAssistantEntity]
    ) -> HomeAssistantAccessoryAvailability {
        guard !entities.isEmpty else { return .unknown }
        let availableCount = entities.filter(\.isAvailable).count
        if availableCount == 0 {
            return entities.contains { $0.state.state == "unknown" } ? .unknown : .unavailable
        }
        return availableCount < entities.count ? .partiallyAvailable : .available
    }

    private static func aggregateControlEntities(
        in accessory: HomeAssistantAccessory
    ) -> [HomeAssistantEntity] {
        HomeAssistantAccessoryReconciler.splitCandidates(in: accessory.sourceCard)
    }

    private static func isControlActive(_ entity: HomeAssistantEntity) -> Bool {
        guard entity.isAvailable else { return false }
        switch entity.domain {
        case "light", "switch", "input_boolean", "fan":
            return entity.state.state == "on"
        case "cover":
            return ["open", "opening"].contains(entity.state.state)
        case "climate":
            return entity.state.state != "off"
        case "lock":
            return entity.state.state == "unlocked"
        default:
            return false
        }
    }

    private static func resolvedPower(
        _ entity: HomeAssistantEntity?,
        kind: HomeAssistantAccessoryKind
    ) -> HomeAssistantAccessoryPowerState {
        guard let entity else {
            return kind == .sensorGroup ? .notApplicable : .unknown
        }
        switch entity.domain {
        case "switch", "input_boolean", "light", "fan":
            return switch entity.state.state {
            case "on": .on
            case "off": .off
            default: .unknown
            }
        case "climate":
            return entity.state.state == "off" ? .off : .on
        case "cover":
            return switch entity.state.state {
            case "open", "opening": .on
            case "closed", "closing": .off
            default: .unknown
            }
        case "lock":
            return switch entity.state.state {
            case "locked": .off
            case "unlocked": .on
            default: .unknown
            }
        case "sensor", "binary_sensor":
            return .notApplicable
        default:
            return .unknown
        }
    }

    private static func primaryText(
        owner: HomeAssistantEntity?,
        power: HomeAssistantAccessoryPowerState,
        kind: HomeAssistantAccessoryKind,
        translations: HomeAssistantTranslationCatalog?,
        locale: Locale
    ) -> String {
        guard let owner else {
            return power == .notApplicable ? "查看状态" : "状态未知"
        }
        if owner.domain == "climate" || kind == .sensorGroup {
            return HomeAssistantStateFormatter.stateText(
                for: owner,
                role: .primaryControl,
                translations: translations,
                locale: locale
            )
        }
        switch power {
        case .on:
            return HomeAssistantStateFormatter.stateText(
                for: owner,
                role: .power,
                translations: translations,
                locale: locale
            )
        case .off:
            return HomeAssistantStateFormatter.stateText(
                for: owner,
                role: .power,
                translations: translations,
                locale: locale
            )
        case .standby: return "待机"
        case .notApplicable:
            return HomeAssistantStateFormatter.stateText(
                for: owner,
                translations: translations,
                locale: locale
            )
        case .unknown: return "状态未知"
        }
    }

    private static func resolvedActivity(_ accessory: HomeAssistantAccessory) -> HomeAssistantAccessoryActivityState? {
        let activityEntities = accessory.entities(for: .activity)
        if activityEntities.contains(where: { $0.domain == "fan" && $0.state.state == "on" }) { return .running }
        if activityEntities.contains(where: { $0.state.state == "on" }) { return .running }

        if accessory.powerEntity != nil,
           let primary = accessory.primaryControlEntity,
           primary.domain == "fan" {
            return primary.state.state == "on" ? .running : .idle
        }

        guard let climate = accessory.primaryControlEntity, climate.domain == "climate" else { return nil }
        let action = climate.state.attributes["hvac_action"]?.stringValue ?? climate.state.state
        switch action {
        case "heating", "heat": return .heating
        case "cooling", "cool": return .cooling
        case "drying", "dry": return .drying
        case "fan", "fan_only": return .fanOnly
        case "idle", "off": return .idle
        default: return .unknown
        }
    }

    private static func resolvedCurrentTemperature(_ accessory: HomeAssistantAccessory) -> Double? {
        if let climate = accessory.entities.first(where: { $0.domain == "climate" && $0.isAvailable }),
           let value = climate.state.attributes["current_temperature"]?.doubleValue,
           value.isFinite {
            return value
        }

        let boundTemperatureEntities = accessory.entities(for: .temperature)
        let boundTemperatureEntityIDs = Set(boundTemperatureEntities.map(\.entityID))
        let fallbackEntities = boundTemperatureEntities + accessory.entities.filter {
            $0.deviceClass == "temperature"
                && !boundTemperatureEntityIDs.contains($0.entityID)
        }
        return fallbackEntities.lazy.compactMap { entity -> Double? in
            guard entity.isAvailable, let value = Double(entity.state.state), value.isFinite else {
                return nil
            }
            return value
        }.first
    }

    private static func auxiliaryText(
        _ accessory: HomeAssistantAccessory,
        excluding entityID: String?,
        translations: HomeAssistantTranslationCatalog?,
        locale: Locale
    ) -> String? {
        if let primary = accessory.primaryControlEntity,
           primary.entityID != entityID,
           primary.isAvailable,
           ["fan", "climate"].contains(primary.domain),
           isAuxiliaryActive(primary) {
            return "运行状态 · \(HomeAssistantStateFormatter.stateText(for: primary, role: .activity, translations: translations, locale: locale))"
        }
        let priority: [HomeAssistantAccessoryRole] = [
            .activity, .particulateMatter, .airQuality, .temperature, .humidity,
            .filterLife, .powerUsage, .energyUsage, .indicator, .childControl,
        ]
        for role in priority {
            for entity in accessory.entities(for: role) where entity.entityID != entityID && entity.isAvailable {
                if [.indicator, .childControl, .activity].contains(role), !isAuxiliaryActive(entity) {
                    continue
                }
                let value = HomeAssistantStateFormatter.stateText(
                    for: entity,
                    role: role,
                    translations: translations,
                    locale: locale
                )
                return "\(role.displayName) · \(value)"
            }
        }
        return nil
    }

    private static func isAuxiliaryActive(_ entity: HomeAssistantEntity) -> Bool {
        switch entity.domain {
        case "switch", "input_boolean", "light", "fan", "binary_sensor": entity.state.state == "on"
        case "climate": entity.state.state != "off"
        default: false
        }
    }

    private static func isAlertActive(_ entity: HomeAssistantEntity) -> Bool {
        if entity.domain == "binary_sensor" { return entity.state.state == "on" }
        return !["off", "ok", "normal", "none", "0"].contains(entity.state.state)
    }
}
