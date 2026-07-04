import Foundation

public enum IOSToolTabSelection {
    public static let defaultLimit = 3

    public static func resolvedPinnedTabs(
        savedIDs: [String],
        availableIDs: [String],
        limit: Int = defaultLimit
    ) -> [String] {
        guard limit > 0 else { return [] }

        let availableIDSet = Set(availableIDs)
        var seen = Set<String>()
        var result: [String] = []

        for id in savedIDs where availableIDSet.contains(id) && !seen.contains(id) {
            result.append(id)
            seen.insert(id)

            if result.count == limit {
                break
            }
        }

        return result
    }

    public static func adding(
        _ id: String,
        to savedIDs: [String],
        availableIDs: [String],
        limit: Int = defaultLimit
    ) -> [String] {
        let resolved = resolvedPinnedTabs(
            savedIDs: savedIDs,
            availableIDs: availableIDs,
            limit: limit
        )

        guard availableIDs.contains(id),
              !resolved.contains(id),
              resolved.count < limit else {
            return resolved
        }

        return resolved + [id]
    }

    public static func removing(_ id: String, from savedIDs: [String]) -> [String] {
        savedIDs.filter { $0 != id }
    }
}
