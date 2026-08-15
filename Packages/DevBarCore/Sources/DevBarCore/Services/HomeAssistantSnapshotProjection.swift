import Foundation

public enum HomeAssistantSnapshotProjection {
    public static func cacheSnapshot(from snapshot: HomeAssistantSnapshot) -> HomeAssistantSnapshot {
        let cards = snapshot.cards.map { card in
            replacingEntities(in: card, with: card.entities.map(sanitizedEntity))
        }
        let entitiesByID = cards
            .flatMap(\.entities)
            .reduce(into: [String: HomeAssistantEntity]()) { result, entity in
                result[entity.entityID] = entity
            }
        let services = snapshot.services.map { service in
            HomeAssistantService(
                domain: service.domain,
                services: Dictionary(uniqueKeysWithValues: service.services.keys.map { ($0, .null) })
            )
        }
        return HomeAssistantSnapshot(
            config: snapshot.config,
            rooms: snapshot.rooms,
            entities: entitiesByID.values.sorted { $0.entityID < $1.entityID },
            cards: cards,
            services: services,
            refreshedAt: snapshot.refreshedAt
        )
    }

    public static func merging(
        states: [HomeAssistantState],
        into snapshot: HomeAssistantSnapshot,
        refreshedAt: Date = .now
    ) -> HomeAssistantSnapshot {
        let statesByID = Dictionary(uniqueKeysWithValues: states.map { ($0.entityID, $0) })
        let update: (HomeAssistantEntity) -> HomeAssistantEntity = { entity in
            let state = statesByID[entity.entityID] ?? unavailableState(from: entity.state)
            return replacingState(of: entity, with: state)
        }
        return HomeAssistantSnapshot(
            config: snapshot.config,
            rooms: snapshot.rooms,
            entities: snapshot.entities.map(update),
            cards: snapshot.cards.map { card in
                replacingEntities(in: card, with: card.entities.map(update))
            },
            services: snapshot.services,
            refreshedAt: refreshedAt
        )
    }

    /// Applies state-change events without treating entities absent from the event batch as unavailable.
    ///
    /// Home Assistant's `state_changed` stream is incremental, whereas `merging(states:into:)`
    /// consumes a complete `/api/states` response. Keeping these paths separate prevents a
    /// one-entity event from forcing a full topology rebuild or invalidating unrelated entities.
    public static func applying(
        states: [HomeAssistantState],
        to snapshot: HomeAssistantSnapshot,
        refreshedAt: Date = .now
    ) -> HomeAssistantSnapshot {
        let statesByID = states.reduce(into: [String: HomeAssistantState]()) { result, state in
            result[state.entityID] = state
        }
        guard !statesByID.isEmpty else { return snapshot }
        let update: (HomeAssistantEntity) -> HomeAssistantEntity = { entity in
            guard let state = statesByID[entity.entityID] else { return entity }
            return replacingState(of: entity, with: state)
        }
        return HomeAssistantSnapshot(
            config: snapshot.config,
            rooms: snapshot.rooms,
            entities: snapshot.entities.map(update),
            cards: snapshot.cards.map { card in
                replacingEntities(in: card, with: card.entities.map(update))
            },
            services: snapshot.services,
            refreshedAt: refreshedAt
        )
    }

    public static func visibleSnapshot(
        from snapshot: HomeAssistantSnapshot,
        hiddenCardIDs: Set<String>
    ) -> HomeAssistantSnapshot {
        let cards = snapshot.cards.filter { !hiddenCardIDs.contains($0.id) }
        let entityIDs = Set(cards.flatMap(\.entities).map(\.entityID))
        let areaIDs = Set(cards.compactMap(\.areaID))
        let hasUnassigned = cards.contains { $0.areaID == nil }
        let rooms = snapshot.rooms.filter { room in
            areaIDs.contains(room.id)
                || (hasUnassigned && room.id == HomeAssistantTopologyBuilder.unassignedAreaID)
        }
        return HomeAssistantSnapshot(
            config: snapshot.config,
            rooms: rooms,
            entities: snapshot.entities.filter { entityIDs.contains($0.entityID) },
            cards: cards,
            services: snapshot.services,
            refreshedAt: snapshot.refreshedAt
        )
    }

    public static func isValidCacheSnapshot(_ snapshot: HomeAssistantSnapshot) -> Bool {
        let entityIDs = Set(snapshot.entities.map(\.entityID))
        return snapshot.cards.allSatisfy { card in
            !card.id.isEmpty
                && !card.primaryEntityID.isEmpty
                && card.entities.contains(where: { $0.entityID == card.primaryEntityID })
                && card.entities.allSatisfy { entityIDs.contains($0.entityID) }
        }
    }

    private static func sanitizedEntity(_ entity: HomeAssistantEntity) -> HomeAssistantEntity {
        let attributes = entity.state.attributes.filter { cachedAttributeKeys.contains($0.key) }
        let state = HomeAssistantState(
            entityID: entity.state.entityID,
            state: entity.state.state,
            attributes: attributes,
            lastChanged: entity.state.lastChanged,
            lastUpdated: entity.state.lastUpdated
        )
        return replacingState(of: entity, with: state)
    }

    private static func replacingEntities(
        in card: HomeAssistantDeviceCard,
        with entities: [HomeAssistantEntity]
    ) -> HomeAssistantDeviceCard {
        let ranked = HomeAssistantPrimaryEntityPolicy.rankedCandidates(
            entities,
            preferredEntityID: card.primaryEntityID,
            rank: HomeAssistantPrimaryEntityPolicy.topologyRank
        )
        let primaryEntityID = ranked.first?.entityID ?? card.primaryEntityID
        let equivalentPrimaryCount = HomeAssistantPrimaryEntityPolicy.equivalentTopCandidates(
            ranked,
            rank: HomeAssistantPrimaryEntityPolicy.topologyRank
        ).count
        let primaryRank = ranked.first.map(HomeAssistantPrimaryEntityPolicy.topologyRank) ?? Int.max
        return HomeAssistantDeviceCard(
            id: card.id,
            name: card.name,
            areaID: card.areaID,
            primaryEntityID: primaryEntityID,
            entities: entities,
            hasMultiplePrimaryControls: equivalentPrimaryCount > 1 && primaryRank < 3
        )
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

    private static func unavailableState(from state: HomeAssistantState) -> HomeAssistantState {
        HomeAssistantState(
            entityID: state.entityID,
            state: "unavailable",
            attributes: state.attributes,
            lastChanged: state.lastChanged,
            lastUpdated: state.lastUpdated
        )
    }

    private static let cachedAttributeKeys = Set([
        "brightness", "color_mode", "color_temp", "current_position", "current_temperature",
        "device_class", "fan_mode", "fan_modes", "hvac_action", "hvac_modes", "max_temp",
        "min_temp", "percentage", "percentage_step", "preset_mode", "preset_modes", "rgb_color",
        "supported_color_modes", "supported_features", "target_temp_high", "target_temp_low",
        "target_temp_step", "temperature", "unit_of_measurement",
    ])
}
