import Foundation

public enum IOSToolOrder {
    public static func resolvedOrder(savedOrder: [String], defaultOrder: [String]) -> [String] {
        var seen = Set<String>()
        let validIDs = Set(defaultOrder)
        var result: [String] = []

        for id in savedOrder where validIDs.contains(id) && !seen.contains(id) {
            result.append(id)
            seen.insert(id)
        }

        for id in defaultOrder where !seen.contains(id) {
            result.append(id)
        }

        return result
    }

    public static func moving(_ source: String, before target: String, in order: [String]) -> [String] {
        guard source != target,
              order.contains(source),
              order.contains(target) else {
            return order
        }

        var updated = order
        updated.removeAll { $0 == source }

        guard let targetIndex = updated.firstIndex(of: target) else {
            return order
        }

        updated.insert(source, at: targetIndex)
        return updated
    }
}
