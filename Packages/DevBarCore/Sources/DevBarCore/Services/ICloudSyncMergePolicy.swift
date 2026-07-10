import Foundation

public enum ICloudSyncMergePolicy {
    public static func resolve(local: ICloudSyncRecord, remote: ICloudSyncRecord) -> ICloudSyncRecord {
        if let localDeletedAt = local.deletedAt,
           localDeletedAt >= remote.updatedAt {
            return local
        }
        if let remoteDeletedAt = remote.deletedAt,
           remoteDeletedAt >= local.updatedAt {
            return remote
        }
        if remote.updatedAt > local.updatedAt {
            return remote
        }
        if local.updatedAt > remote.updatedAt {
            return local
        }
        return remote.id >= local.id ? remote : local
    }

    public static func mergeChatMessages(
        local: [ICloudChatMessageSnapshot],
        remote: [ICloudChatMessageSnapshot]
    ) -> [ICloudChatMessageSnapshot] {
        var byID: [UUID: ICloudChatMessageSnapshot] = [:]
        for message in local {
            byID[message.id] = message
        }
        for message in remote {
            if let existing = byID[message.id],
               existing.updatedAt > message.updatedAt {
                continue
            }
            byID[message.id] = message
        }
        return byID.values.sorted { lhs, rhs in
            let lhsSortIndex = lhs.sortIndex ?? Int.max
            let rhsSortIndex = rhs.sortIndex ?? Int.max
            if lhsSortIndex != rhsSortIndex {
                return lhsSortIndex < rhsSortIndex
            }
            if lhs.createdAt != rhs.createdAt {
                return lhs.createdAt < rhs.createdAt
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }
}

