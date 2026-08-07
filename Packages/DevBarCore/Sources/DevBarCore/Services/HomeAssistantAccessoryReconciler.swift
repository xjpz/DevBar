import Foundation

public enum HomeAssistantAccessoryReconciler {
    public static func accessories(
        from cards: [HomeAssistantDeviceCard],
        entities allEntities: [HomeAssistantEntity]? = nil,
        presentations: [String: HomeAssistantAccessoryPresentation] = [:],
        legacyPresentations: [String: HomeAssistantDevicePresentation] = [:],
        grouping: HomeAssistantAccessoryGroupingSettings = HomeAssistantAccessoryGroupingSettings()
    ) -> [HomeAssistantAccessory] {
        cards.flatMap { projections(for: $0, grouping: grouping) }.map { projection in
            let card = projection.card
            let stored = presentations[card.id]
            let legacy = legacyPresentations[card.id]
            let storedBindings = (stored?.bindings ?? []).compactMap { binding -> HomeAssistantRoleBinding? in
                let entityIDs = binding.entityIDs.filter {
                    !projection.excludedEntityIDs.contains($0)
                }
                return entityIDs.isEmpty ? nil : .init(role: binding.role, entityIDs: entityIDs)
            }
            let baseEntityIDs = Set(card.entities.map(\.entityID))
            let requestedEntityIDs = Set(storedBindings.flatMap(\.entityIDs))
            let supplementalEntities = (allEntities ?? [])
                .filter {
                    requestedEntityIDs.contains($0.entityID)
                        && !baseEntityIDs.contains($0.entityID)
                        && !projection.excludedEntityIDs.contains($0.entityID)
                }
            let classificationCard = HomeAssistantDeviceCard(
                id: card.id,
                name: card.name,
                areaID: card.areaID,
                primaryEntityID: card.primaryEntityID,
                entities: card.entities + supplementalEntities,
                hasMultiplePrimaryControls: card.hasMultiplePrimaryControls
            )
            let preferredKind = stored?.kind ?? legacy.map { HomeAssistantAccessoryKind($0.displayType) }
            let classification = HomeAssistantAccessoryClassifier.classify(
                card: classificationCard,
                preferredKind: preferredKind,
                explicitBindings: storedBindings
            )
            let requestedBindingPairs = Set(storedBindings.flatMap { binding in
                binding.entityIDs.map { "\(binding.role.rawValue)=\($0)" }
            })
            let resolvedBindingPairs = Set(classification.bindings.flatMap { binding in
                binding.entityIDs.map { "\(binding.role.rawValue)=\($0)" }
            })
            let unresolvedBindingPairs = requestedBindingPairs.subtracting(resolvedBindingPairs)
            let sourceDeviceIDs: [String]
            if let stored, !stored.sourceDeviceIDs.isEmpty {
                sourceDeviceIDs = stored.sourceDeviceIDs
            } else {
                sourceDeviceIDs = classificationCard.entities.compactMap(\.deviceID).uniqued()
            }
            let migrated = legacy.map {
                HomeAssistantAccessoryPresentation(
                    id: card.id,
                    sourceDeviceIDs: sourceDeviceIDs,
                    legacy: $0,
                    bindings: classification.bindings
                )
            }
            let effective = stored ?? migrated
            let kind = effective?.kind ?? classification.kind
            let customAreaID = effective?.customAreaID
            let areaID = customAreaID == HomeAssistantTopologyBuilder.unassignedAreaID
                ? nil
                : customAreaID ?? card.areaID
            let metadata: HomeAssistantClassificationMetadata
            if stored != nil {
                metadata = .init(
                    confidence: classification.metadata.needsReview || !unresolvedBindingPairs.isEmpty
                        ? classification.metadata.confidence
                        : 1,
                    source: .user,
                    reasons: classification.metadata.reasons + (unresolvedBindingPairs.isEmpty
                        ? []
                        : ["绑定已失效或与类型不兼容：\(unresolvedBindingPairs.sorted().joined(separator: "、"))"]),
                    needsReview: classification.metadata.needsReview || !unresolvedBindingPairs.isEmpty
                )
            } else if legacy != nil {
                metadata = .init(
                    confidence: classification.metadata.confidence,
                    source: .migrated,
                    reasons: classification.metadata.reasons + ["保留旧版名称、类型、图标和房间"],
                    needsReview: classification.metadata.needsReview
                )
            } else {
                metadata = classification.metadata
            }

            return HomeAssistantAccessory(
                id: card.id,
                sourceCard: classificationCard,
                sourceCardID: projection.sourceCardID,
                splitEntityID: projection.splitEntityID,
                kind: kind,
                name: effective?.customName ?? card.name,
                areaID: areaID,
                systemImage: effective?.systemImage ?? kind.systemImage,
                bindings: classification.bindings,
                classification: metadata,
                isUserConfigured: stored != nil
            )
        }
    }

    /// Returns only user-meaningful endpoints that may be separated from a physical device.
    /// This does not split anything by itself: the physical device remains the default accessory
    /// boundary until the user persists an explicit selection.
    public static func splitCandidates(in card: HomeAssistantDeviceCard) -> [HomeAssistantEntity] {
        card.entities
            .filter(isMeaningfulSplitCandidate)
            .sorted { lhs, rhs in
                if lhs.entityID == card.primaryEntityID { return true }
                if rhs.entityID == card.primaryEntityID { return false }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
    }

    private static func projections(
        for card: HomeAssistantDeviceCard,
        grouping: HomeAssistantAccessoryGroupingSettings
    ) -> [AccessoryProjection] {
        let candidates = splitCandidates(in: card)
        let requestedIDs = grouping.splitEntityIDs(for: card.id)
        let splitEntities = candidates.filter { requestedIDs.contains($0.entityID) }
        guard !splitEntities.isEmpty else {
            return [.init(
                card: card,
                sourceCardID: card.id,
                splitEntityID: nil,
                excludedEntityIDs: []
            )]
        }

        let splitIDs = Set(splitEntities.map(\.entityID))
        let remainingEntities = card.entities.filter { !splitIDs.contains($0.entityID) }
        let remainingControls = remainingEntities.filter {
            HomeAssistantDeviceCard.controllableDomains.contains($0.domain)
        }
        var result: [AccessoryProjection] = []

        if !remainingControls.isEmpty {
            let primaryEntityID: String
            if remainingEntities.contains(where: { $0.entityID == card.primaryEntityID }) {
                primaryEntityID = card.primaryEntityID
            } else {
                primaryEntityID = remainingControls[0].entityID
            }
            result.append(.init(
                card: HomeAssistantDeviceCard(
                    id: card.id,
                    name: card.name,
                    areaID: card.areaID,
                    primaryEntityID: primaryEntityID,
                    entities: remainingEntities,
                    hasMultiplePrimaryControls: splitCandidates(
                        in: HomeAssistantDeviceCard(
                            id: card.id,
                            name: card.name,
                            areaID: card.areaID,
                            primaryEntityID: primaryEntityID,
                            entities: remainingEntities,
                            hasMultiplePrimaryControls: false
                        )
                    ).count > 1
                ),
                sourceCardID: card.id,
                splitEntityID: nil,
                excludedEntityIDs: splitIDs
            ))
        }

        result.append(contentsOf: splitEntities.map { entity in
            AccessoryProjection(
                card: HomeAssistantDeviceCard(
                    id: "\(card.id)::\(entity.entityID)",
                    name: entity.name,
                    areaID: entity.areaID ?? card.areaID,
                    primaryEntityID: entity.entityID,
                    entities: [entity],
                    hasMultiplePrimaryControls: false
                ),
                sourceCardID: card.id,
                splitEntityID: entity.entityID,
                excludedEntityIDs: []
            )
        })
        return result
    }

    private static func isMeaningfulSplitCandidate(_ entity: HomeAssistantEntity) -> Bool {
        if ["light", "fan", "cover", "climate", "lock"].contains(entity.domain) {
            return !isAuxiliaryControl(entity)
        }
        return ["switch", "input_boolean"].contains(entity.domain)
            && !isDevicePowerEntity(entity)
            && !isAuxiliaryControl(entity)
    }

    private static func isDevicePowerEntity(_ entity: HomeAssistantEntity) -> Bool {
        let hint = "\(entity.entityID) \(entity.name)".lowercased()
        return [
            "device_power", "master", "main power", "power switch",
            "总开关", "总控", "电源", "整机",
        ].contains { hint.contains($0) }
            && !["indicator", "指示灯", "led"].contains { hint.contains($0) }
    }

    private static func isAuxiliaryControl(_ entity: HomeAssistantEntity) -> Bool {
        let hint = "\(entity.entityID) \(entity.name) \(entity.deviceClass ?? "")".lowercased()
        return [
            "indicator", "指示灯", "display", "屏幕", "led",
            "child lock", "童锁", "lock switch",
            "flex_switch", "滚动开关", "factory", "恢复出厂",
            "reset", "重置", "default_state", "默认状态",
            "dimming_mode", "灯光变化",
            "power_on_behavior", "断电记忆", "断电", "memory",
            "parameter", "参数", "custom", "自定义",
            "usage alert", "用电量提示", "overload", "过载",
            "protection", "保护", "fault", "故障",
            "camera control", "摄像机控制",
        ].contains { hint.contains($0) }
    }

    /// Refreshes entity states while preserving the already resolved accessory schema.
    ///
    /// State-change events cannot alter device membership, user bindings, names, rooms, or
    /// classification. Updating only the embedded entities avoids repeating classification for
    /// every live event while keeping accessory identity stable for SwiftUI.
    public static func applying(
        states: [HomeAssistantState],
        to accessories: [HomeAssistantAccessory]
    ) -> [HomeAssistantAccessory] {
        let statesByID = states.reduce(into: [String: HomeAssistantState]()) { result, state in
            result[state.entityID] = state
        }
        guard !statesByID.isEmpty else { return accessories }

        return accessories.map { accessory in
            guard accessory.entities.contains(where: { statesByID[$0.entityID] != nil }) else {
                return accessory
            }
            let sourceCard = accessory.sourceCard
            let updatedCard = HomeAssistantDeviceCard(
                id: sourceCard.id,
                name: sourceCard.name,
                areaID: sourceCard.areaID,
                primaryEntityID: sourceCard.primaryEntityID,
                entities: sourceCard.entities.map { entity in
                    guard let state = statesByID[entity.entityID] else { return entity }
                    return replacingState(of: entity, with: state)
                },
                hasMultiplePrimaryControls: sourceCard.hasMultiplePrimaryControls
            )
            return HomeAssistantAccessory(
                id: accessory.id,
                sourceCard: updatedCard,
                sourceCardID: accessory.sourceCardID,
                splitEntityID: accessory.splitEntityID,
                kind: accessory.kind,
                name: accessory.name,
                areaID: accessory.areaID,
                systemImage: accessory.systemImage,
                bindings: accessory.bindings,
                classification: accessory.classification,
                isUserConfigured: accessory.isUserConfigured
            )
        }
    }

    private static func replacingState(
        of entity: HomeAssistantEntity,
        with state: HomeAssistantState
    ) -> HomeAssistantEntity {
        HomeAssistantEntity(
            entityID: entity.entityID,
            deviceID: entity.deviceID,
            areaID: entity.areaID,
            name: entity.name,
            domain: entity.domain,
            deviceClass: entity.deviceClass,
            icon: entity.icon,
            platform: entity.platform,
            translationKey: entity.translationKey,
            state: state,
            availableServices: entity.availableServices
        )
    }
}

private struct AccessoryProjection {
    let card: HomeAssistantDeviceCard
    let sourceCardID: String
    let splitEntityID: String?
    let excludedEntityIDs: Set<String>
}

private extension Sequence where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
