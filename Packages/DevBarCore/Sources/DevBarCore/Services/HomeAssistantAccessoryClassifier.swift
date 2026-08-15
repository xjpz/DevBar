import Foundation

public struct HomeAssistantAccessoryClassification: Equatable, Sendable {
    public let kind: HomeAssistantAccessoryKind
    public let bindings: [HomeAssistantRoleBinding]
    public let metadata: HomeAssistantClassificationMetadata

    public init(
        kind: HomeAssistantAccessoryKind,
        bindings: [HomeAssistantRoleBinding],
        metadata: HomeAssistantClassificationMetadata
    ) {
        self.kind = kind
        self.bindings = bindings
        self.metadata = metadata
    }
}

public enum HomeAssistantAccessoryClassifier {
    public static func classify(
        card: HomeAssistantDeviceCard,
        preferredKind: HomeAssistantAccessoryKind? = nil,
        explicitBindings: [HomeAssistantRoleBinding] = [],
        explicitlyUnboundRoles: Set<HomeAssistantAccessoryRole> = []
    ) -> HomeAssistantAccessoryClassification {
        let kind = preferredKind ?? inferredKind(for: card)
        let schema = HomeAssistantAccessorySchemaRegistry.schema(for: kind)
        let availableEntityIDs = Set(card.entities.map(\.entityID))
        let validExplicitBindings = explicitBindings.compactMap { binding -> HomeAssistantRoleBinding? in
            guard schema.supportedRoles.contains(binding.role) else { return nil }
            let allowedDomains = HomeAssistantAccessorySchemaRegistry.allowedDomains(
                for: binding.role,
                kind: kind
            )
            let ids = binding.entityIDs.filter { entityID in
                guard availableEntityIDs.contains(entityID),
                      let entity = card.entities.first(where: { $0.entityID == entityID }) else { return false }
                return allowedDomains.isEmpty || allowedDomains.contains(entity.domain)
            }
            return ids.isEmpty ? nil : HomeAssistantRoleBinding(role: binding.role, entityIDs: ids)
        }

        let explicitlyBoundRoles = Set(validExplicitBindings.map(\.role))
        let suppressedRoles = explicitlyUnboundRoles.subtracting(explicitlyBoundRoles)

        if !validExplicitBindings.isEmpty || !suppressedRoles.isEmpty {
            let hasPrimary = validExplicitBindings.contains { [.primaryControl, .power].contains($0.role) }
            return HomeAssistantAccessoryClassification(
                kind: kind,
                bindings: supplementedBindings(
                    validExplicitBindings,
                    card: card,
                    kind: kind,
                    preservesControlRoles: true,
                    suppressedRoles: suppressedRoles
                ),
                metadata: .init(
                    confidence: hasPrimary ? 1 : 0.65,
                    source: .user,
                    reasons: hasPrimary ? ["使用用户确认的实体角色"] : ["用户配置缺少主控制实体"],
                    needsReview: !hasPrimary
                )
            )
        }

        let candidates = card.entities.filter { entity in
            guard schema.acceptsPrimary(entity) else { return false }
            guard let role = inferredRole(for: entity, kind: kind) else { return true }
            return ![.diagnostic, .indicator].contains(role)
        }
        let rankedCandidates = candidates.sorted { lhs, rhs in
            let left = primaryRank(lhs, kind: kind)
            let right = primaryRank(rhs, kind: kind)
            if left != right { return left < right }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
        let primary = rankedCandidates.first ?? fallbackPrimary(in: card)
        let explicitPower = card.entities.first { entity in
            entity.entityID != primary?.entityID && isPowerEntity(entity)
        }

        var bindings: [HomeAssistantRoleBinding] = []
        if let primary {
            bindings.append(.init(role: .primaryControl, entityIDs: [primary.entityID]))
        }
        if let explicitPower {
            bindings.append(.init(role: .power, entityIDs: [explicitPower.entityID]))
        }
        bindings = supplementedBindings(bindings, card: card, kind: kind, preservesControlRoles: false)

        let topRank = rankedCandidates.first.map { primaryRank($0, kind: kind) }
        let equivalentPrimaryCount = topRank.map { rank in
            rankedCandidates.filter { primaryRank($0, kind: kind) == rank }.count
        } ?? 0
        let unresolvedMultipleControls = equivalentPrimaryCount > 1 && explicitPower == nil
        let hasPrimary = primary != nil
        let nameOnlyKind = preferredKind == nil && kindWasInferredFromName(card: card, kind: kind)
        let confidence: Double
        if unresolvedMultipleControls {
            confidence = 0.55
        } else if !hasPrimary {
            confidence = 0.35
        } else if nameOnlyKind {
            confidence = 0.72
        } else if explicitPower != nil {
            confidence = 0.92
        } else {
            confidence = 0.88
        }

        var reasons = ["根据 Domain、Device Class 与可用能力识别"]
        if let explicitPower { reasons.append("识别总开关：\(explicitPower.name)") }
        if unresolvedMultipleControls { reasons.append("存在多个同级主控制候选") }
        if !hasPrimary { reasons.append("没有可确认的主控制实体") }

        return HomeAssistantAccessoryClassification(
            kind: kind,
            bindings: bindings,
            metadata: .init(
                confidence: confidence,
                source: .automatic,
                reasons: reasons,
                needsReview: confidence < 0.6 || unresolvedMultipleControls || !hasPrimary
            )
        )
    }

    public static func inferredKind(for card: HomeAssistantDeviceCard) -> HomeAssistantAccessoryKind {
        let hint = ([card.name] + card.entities.map(\.name) + card.entities.compactMap(\.deviceClass))
            .joined(separator: " ")
            .lowercased()
        if containsAny(hint, ["空气净化", "净化器", "purifier", "air purifier"]) { return .airPurifier }
        if card.entities.contains(where: { $0.domain == "climate" }) { return .airConditioner }
        if card.entities.contains(where: { $0.domain == "light" }) { return .light }
        if card.entities.contains(where: { $0.domain == "fan" }) { return .fan }
        if card.entities.contains(where: { ["switch", "input_boolean"].contains($0.domain) }) { return .switchDevice }
        if card.entities.allSatisfy({ ["sensor", "binary_sensor"].contains($0.domain) }) { return .sensorGroup }
        return .generic
    }

    private static func supplementedBindings(
        _ initial: [HomeAssistantRoleBinding],
        card: HomeAssistantDeviceCard,
        kind: HomeAssistantAccessoryKind,
        preservesControlRoles: Bool,
        suppressedRoles: Set<HomeAssistantAccessoryRole> = []
    ) -> [HomeAssistantRoleBinding] {
        var roleEntityIDs = initial.reduce(into: [HomeAssistantAccessoryRole: [String]]()) { result, binding in
            for entityID in binding.entityIDs where !result[binding.role, default: []].contains(entityID) {
                result[binding.role, default: []].append(entityID)
            }
        }
        let alreadyBound = Set(initial.flatMap(\.entityIDs))
        let supportedRoles = HomeAssistantAccessorySchemaRegistry.schema(for: kind).supportedRoles

        for entity in card.entities where !alreadyBound.contains(entity.entityID) {
            guard let role = inferredRole(for: entity, kind: kind), supportedRoles.contains(role) else { continue }
            guard !suppressedRoles.contains(role) else { continue }
            if preservesControlRoles && [.primaryControl, .power].contains(role) { continue }
            roleEntityIDs[role, default: []].append(entity.entityID)
        }

        return HomeAssistantAccessoryRole.allCases.compactMap { role in
            guard let ids = roleEntityIDs[role], !ids.isEmpty else { return nil }
            return HomeAssistantRoleBinding(role: role, entityIDs: ids)
        }
    }

    private static func inferredRole(
        for entity: HomeAssistantEntity,
        kind: HomeAssistantAccessoryKind
    ) -> HomeAssistantAccessoryRole? {
        let hint = "\(entity.entityID) \(entity.name) \(entity.deviceClass ?? "")".lowercased()
        switch entity.domain {
        case "sensor", "number":
            switch entity.deviceClass {
            case "temperature": return .temperature
            case "humidity": return .humidity
            case "aqi", "carbon_dioxide", "volatile_organic_compounds": return .airQuality
            case "pm1", "pm10", "pm25": return .particulateMatter
            case "power", "current", "voltage": return .powerUsage
            case "energy": return .energyUsage
            default:
                if containsAny(hint, ["filter", "滤芯", "滤网"]) { return .filterLife }
                if containsAny(hint, ["pm2.5", "pm25", "颗粒物"]) { return .particulateMatter }
                if containsAny(hint, ["air quality", "空气质量", "aqi"]) { return .airQuality }
                return nil
            }
        case "binary_sensor":
            if ["problem", "safety", "smoke", "gas", "moisture"].contains(entity.deviceClass ?? "") {
                return .alert
            }
            if ["running", "motion", "occupancy", "presence"].contains(entity.deviceClass ?? "") {
                return .activity
            }
            return nil
        case "select", "input_select":
            return .mode
        case "button", "scene", "script", "automation":
            return .action
        case "switch", "input_boolean":
            if isPowerEntity(entity) { return .power }
            if containsAny(hint, ["indicator", "指示灯", "display", "屏幕", "led"]) { return .indicator }
            if containsAny(hint, [
                "reset", "重置", "factory", "参数", "child lock", "童锁",
                "power_on_behavior", "断电记忆", "断电", "memory",
                "usage alert", "用电量提示", "overload", "过载",
                "protection", "保护", "fault", "故障",
                "camera control", "摄像机控制", "custom", "自定义",
            ]) { return .diagnostic }
            return .childControl
        case "fan":
            return kind == .fan || kind == .airPurifier ? .activity : .childControl
        default:
            return nil
        }
    }

    private static func fallbackPrimary(in card: HomeAssistantDeviceCard) -> HomeAssistantEntity? {
        card.entities.first { HomeAssistantDeviceCard.controllableDomains.contains($0.domain) }
            ?? card.primaryEntity
    }

    private static func primaryRank(
        _ entity: HomeAssistantEntity,
        kind: HomeAssistantAccessoryKind
    ) -> Int {
        let order: [String]
        switch kind {
        case .airConditioner: order = ["climate", "switch", "fan"]
        case .airPurifier: order = ["fan", "switch"]
        case .fan: order = ["fan", "switch"]
        case .light: order = ["light", "switch"]
        case .switchDevice: order = ["switch", "input_boolean"]
        case .sensorGroup: order = ["sensor", "binary_sensor"]
        case .generic: order = ["light", "climate", "fan", "cover", "lock", "switch", "input_boolean"]
        }
        return order.firstIndex(of: entity.domain) ?? Int.max
    }

    private static func isPowerEntity(_ entity: HomeAssistantEntity) -> Bool {
        guard ["switch", "input_boolean"].contains(entity.domain) else { return false }
        let hint = "\(entity.entityID) \(entity.name)".lowercased()
        return containsAny(hint, [
            "device_power", "master", "main power", "power switch", "总开关", "总控", "电源", "整机",
        ]) && !containsAny(hint, ["indicator", "指示灯", "led"])
    }

    private static func kindWasInferredFromName(
        card: HomeAssistantDeviceCard,
        kind: HomeAssistantAccessoryKind
    ) -> Bool {
        guard kind == .airPurifier else { return false }
        return !card.entities.contains { $0.deviceClass == "air_purifier" }
    }

    private static func containsAny(_ value: String, _ needles: [String]) -> Bool {
        needles.contains { value.contains($0) }
    }
}
