import Foundation

public enum IOSToolVisibility {
    public static func resolvedHiddenIDs(
        savedHiddenIDs: [String],
        availableIDs: [String]
    ) -> [String] {
        let availableIDSet = Set(availableIDs)
        var seen = Set<String>()

        return savedHiddenIDs.filter { id in
            availableIDSet.contains(id) && seen.insert(id).inserted
        }
    }

    public static func hiding(_ id: String, in savedHiddenIDs: [String]) -> [String] {
        guard !id.isEmpty, !savedHiddenIDs.contains(id) else {
            return savedHiddenIDs
        }

        return savedHiddenIDs + [id]
    }

    public static func showing(_ id: String, in savedHiddenIDs: [String]) -> [String] {
        savedHiddenIDs.filter { $0 != id }
    }

    public static func visibleIDs(orderedIDs: [String], hiddenIDs: [String]) -> [String] {
        let hiddenIDSet = Set(hiddenIDs)
        return orderedIDs.filter { !hiddenIDSet.contains($0) }
    }

    public static func mergingVisibleOrder(
        _ visibleOrder: [String],
        into fullOrder: [String],
        hiddenIDs: [String]
    ) -> [String] {
        let hiddenIDSet = Set(hiddenIDs)
        let originalVisibleOrder = fullOrder.filter { !hiddenIDSet.contains($0) }
        let visibleIDSet = Set(originalVisibleOrder)
        var seen = Set<String>()
        var resolvedVisibleOrder = visibleOrder.filter { id in
            visibleIDSet.contains(id) && seen.insert(id).inserted
        }

        for id in originalVisibleOrder where seen.insert(id).inserted {
            resolvedVisibleOrder.append(id)
        }

        var visibleIndex = 0
        return fullOrder.map { id in
            guard !hiddenIDSet.contains(id), visibleIndex < resolvedVisibleOrder.count else {
                return id
            }

            defer { visibleIndex += 1 }
            return resolvedVisibleOrder[visibleIndex]
        }
    }
}
