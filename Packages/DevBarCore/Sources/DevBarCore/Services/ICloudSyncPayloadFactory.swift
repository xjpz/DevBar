import Foundation

public enum ICloudSyncPayloadFactory {
    public static func memoPayload(
        id: UUID,
        title: String,
        content: String,
        encryptedData: Data?,
        isEncrypted: Bool,
        createdAt: Date,
        updatedAt: Date
    ) -> ICloudSyncRecord {
        var fields: [String: String] = [
            "title": title,
            "content": content,
            "isEncrypted": String(isEncrypted),
            "createdAt": encodeDate(createdAt),
            "updatedAt": encodeDate(updatedAt),
        ]
        if let encryptedData {
            fields["encryptedData"] = encryptedData.base64EncodedString()
        }
        return ICloudSyncRecord(
            id: recordID(entity: .memo, id: id),
            entity: .memo,
            localID: id.uuidString,
            updatedAt: updatedAt,
            fields: fields
        )
    }

    public static func markdownDocumentPayload(
        id: UUID,
        title: String,
        content: String,
        createdAt: Date,
        updatedAt: Date
    ) -> ICloudSyncRecord {
        ICloudSyncRecord(
            id: recordID(entity: .markdownDocument, id: id),
            entity: .markdownDocument,
            localID: id.uuidString,
            updatedAt: updatedAt,
            fields: [
                "title": title,
                "content": content,
                "createdAt": encodeDate(createdAt),
                "updatedAt": encodeDate(updatedAt),
            ]
        )
    }

    public static func apiRecordPayload(
        id: UUID,
        title: String,
        url: String,
        method: String,
        requestType: String,
        headers: String,
        body: String,
        provider: String?,
        tags: [String],
        notes: String,
        createdAt: Date,
        lastOpenedAt: Date,
        isFavorite: Bool,
        includeSensitiveFields: Bool
    ) -> ICloudSyncRecord {
        var fields: [String: String] = [
            "title": title,
            "url": url,
            "method": method,
            "requestType": requestType,
            "tags": encodeStringArray(tags),
            "notes": notes,
            "createdAt": encodeDate(createdAt),
            "lastOpenedAt": encodeDate(lastOpenedAt),
            "isFavorite": String(isFavorite),
        ]
        if let provider {
            fields["provider"] = provider
        }
        if includeSensitiveFields {
            fields["headers"] = headers
            fields["body"] = body
        }
        return ICloudSyncRecord(
            id: recordID(entity: .apiRecord, id: id),
            entity: .apiRecord,
            localID: id.uuidString,
            updatedAt: lastOpenedAt,
            fields: fields
        )
    }

    public static func terminalServerPayload(
        id: UUID,
        name: String,
        host: String,
        port: Int,
        username: String,
        authMethod: String,
        remoteOSFamily: String?,
        passwordSecretKey: String?,
        privateKeySecretKey: String?,
        privateKeyPassphraseSecretKey: String?,
        createdAt: Date,
        updatedAt: Date,
        lastConnectedAt: Date?
    ) -> ICloudSyncRecord {
        var fields: [String: String] = [
            "name": name,
            "host": host,
            "port": String(port),
            "username": username,
            "authMethod": authMethod,
            "createdAt": encodeDate(createdAt),
            "updatedAt": encodeDate(updatedAt),
        ]
        if let remoteOSFamily {
            fields["remoteOSFamily"] = remoteOSFamily
        }
        if let lastConnectedAt {
            fields["lastConnectedAt"] = encodeDate(lastConnectedAt)
        }
        return ICloudSyncRecord(
            id: recordID(entity: .terminalServer, id: id),
            entity: .terminalServer,
            localID: id.uuidString,
            updatedAt: updatedAt,
            fields: fields,
            needsCredentialRestore: passwordSecretKey != nil ||
                privateKeySecretKey != nil ||
                privateKeyPassphraseSecretKey != nil
        )
    }

    public static func chatConversationPayload(
        id: UUID,
        title: String,
        remark: String?,
        tag: String?,
        lastMessagePreview: String,
        messageCount: Int,
        providerRawValue: String?,
        remoteSessionId: String?,
        remoteSource: String?,
        lastSyncedAt: Date?,
        syncStateRawValue: String?,
        isArchived: Bool,
        createdAt: Date,
        updatedAt: Date,
        archivedAt: Date?
    ) -> ICloudSyncRecord {
        var fields: [String: String] = [
            "title": title,
            "lastMessagePreview": lastMessagePreview,
            "messageCount": String(messageCount),
            "isArchived": String(isArchived),
            "createdAt": encodeDate(createdAt),
            "updatedAt": encodeDate(updatedAt),
        ]
        fields["remark"] = remark
        fields["tag"] = tag
        fields["providerRawValue"] = providerRawValue
        fields["remoteSessionId"] = remoteSessionId
        fields["remoteSource"] = remoteSource
        fields["syncStateRawValue"] = syncStateRawValue
        if let lastSyncedAt {
            fields["lastSyncedAt"] = encodeDate(lastSyncedAt)
        }
        if let archivedAt {
            fields["archivedAt"] = encodeDate(archivedAt)
        }
        return ICloudSyncRecord(
            id: recordID(entity: .chatConversation, id: id),
            entity: .chatConversation,
            localID: id.uuidString,
            updatedAt: updatedAt,
            fields: fields
        )
    }

    public static func chatMessagePayload(
        id: UUID,
        conversationID: UUID,
        roleRawValue: String,
        content: String,
        contentFormatRawValue: String,
        isComplete: Bool,
        remoteMessageId: String?,
        sortIndex: Int?,
        createdAt: Date,
        completedAt: Date?,
        errorMessage: String?
    ) -> ICloudSyncRecord {
        let updatedAt = completedAt ?? createdAt
        var fields: [String: String] = [
            "conversationID": conversationID.uuidString,
            "roleRawValue": roleRawValue,
            "content": content,
            "contentFormatRawValue": contentFormatRawValue,
            "isComplete": String(isComplete),
            "createdAt": encodeDate(createdAt),
            "updatedAt": encodeDate(updatedAt),
        ]
        fields["remoteMessageId"] = remoteMessageId
        fields["errorMessage"] = errorMessage
        if let sortIndex {
            fields["sortIndex"] = String(sortIndex)
        }
        if let completedAt {
            fields["completedAt"] = encodeDate(completedAt)
        }
        return ICloudSyncRecord(
            id: recordID(entity: .chatMessage, id: id),
            entity: .chatMessage,
            localID: id.uuidString,
            updatedAt: updatedAt,
            fields: fields
        )
    }

    public static func recordID(entity: ICloudSyncEntity, id: UUID) -> String {
        "\(entity.rawValue):\(id.uuidString.lowercased())"
    }

    private static func encodeDate(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    private static func encodeStringArray(_ values: [String]) -> String {
        guard let data = try? JSONEncoder().encode(values),
              let encoded = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return encoded
    }
}
