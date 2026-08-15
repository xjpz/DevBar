import Foundation

enum HomeAssistantPrimaryEntityPolicy {
    static func rankedCandidates(
        _ entities: [HomeAssistantEntity],
        preferredEntityID: String? = nil,
        rank: (HomeAssistantEntity) -> Int
    ) -> [HomeAssistantEntity] {
        entities.sorted { lhs, rhs in
            let leftRank = rank(lhs)
            let rightRank = rank(rhs)
            if leftRank != rightRank { return leftRank < rightRank }
            if lhs.isAvailable != rhs.isAvailable { return lhs.isAvailable }
            if lhs.entityID == preferredEntityID { return true }
            if rhs.entityID == preferredEntityID { return false }
            let nameOrder = lhs.name.localizedStandardCompare(rhs.name)
            if nameOrder != .orderedSame { return nameOrder == .orderedAscending }
            return lhs.entityID < rhs.entityID
        }
    }

    static func preferred(
        from entities: [HomeAssistantEntity],
        preferredEntityID: String? = nil,
        rank: (HomeAssistantEntity) -> Int
    ) -> HomeAssistantEntity? {
        rankedCandidates(
            entities,
            preferredEntityID: preferredEntityID,
            rank: rank
        ).first
    }

    static func equivalentTopCandidates(
        _ rankedCandidates: [HomeAssistantEntity],
        rank: (HomeAssistantEntity) -> Int
    ) -> [HomeAssistantEntity] {
        guard let first = rankedCandidates.first else { return [] }
        let firstRank = rank(first)
        return rankedCandidates.filter {
            rank($0) == firstRank && $0.isAvailable == first.isAvailable
        }
    }

    static func topologyRank(_ entity: HomeAssistantEntity) -> Int {
        switch entity.domain {
        case "light", "lock", "climate", "cover", "fan", "switch", "input_boolean": 0
        case "scene", "script", "automation", "button": 1
        case "binary_sensor": 2
        case "sensor": 3
        default: 4
        }
    }
}
