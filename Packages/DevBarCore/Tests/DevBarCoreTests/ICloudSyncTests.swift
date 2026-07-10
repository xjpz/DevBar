import Foundation
import Testing
@testable import DevBarCore

@Test
func iCloudSyncSettingsDefaultToSafeRecoverableDataTypes() {
    let settings = ICloudSyncSettings.default

    #expect(!settings.isEnabled)
    #expect(settings.isSyncEnabled(for: .memo))
    #expect(settings.isSyncEnabled(for: .markdownDocument))
    #expect(settings.isSyncEnabled(for: .chatConversation))
    #expect(settings.isSyncEnabled(for: .chatMessage))
    #expect(!settings.isSyncEnabled(for: .apiRecord))
    #expect(settings.isSyncEnabled(for: .terminalServer))
    #expect(!settings.isSyncEnabled(for: .webHistoryRecord))
    #expect(!settings.syncAPISensitiveFields)
    #expect(!settings.syncTerminalSecrets)
    #expect(!settings.syncProviderCredentials)
}

@Test
func iCloudSyncSettingsStoreNormalizesUnsupportedSavedEntities() throws {
    let suiteName = "DevBarCoreTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defaults.removePersistentDomain(forName: suiteName)
    let store = UserDefaultsICloudSyncSettingsStore(defaults: defaults)
    let settings = ICloudSyncSettings(
        isEnabled: true,
        enabledEntities: [.memo, .chatConversation, .chatMessage, .apiRecord, .terminalServer, .webHistoryRecord]
    )

    store.save(settings)
    let loaded = store.load()

    #expect(loaded.enabledEntities == [.memo, .chatConversation, .chatMessage, .terminalServer])
}

@Test
func iCloudSyncSettingsStoreRoundTripsValues() throws {
    let suiteName = "DevBarCoreTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defaults.removePersistentDomain(forName: suiteName)
    let store = UserDefaultsICloudSyncSettingsStore(defaults: defaults)
    let settings = ICloudSyncSettings(
        isEnabled: true,
        enabledEntities: [.memo, .terminalServer],
        syncAPISensitiveFields: true,
        syncTerminalSecrets: false,
        syncProviderCredentials: true
    )

    store.save(settings)

    #expect(store.load() == settings)
}

@Test
func apiRecordPayloadExcludesSensitiveFieldsByDefault() {
    let payload = ICloudSyncPayloadFactory.apiRecordPayload(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000101")!,
        title: "Create issue",
        url: "https://api.example.com/issues",
        method: "POST",
        requestType: "JSON",
        headers: "Authorization: Bearer secret",
        body: "{\"token\":\"secret\"}",
        provider: "example",
        tags: ["work"],
        notes: "Important",
        createdAt: Date(timeIntervalSince1970: 10),
        lastOpenedAt: Date(timeIntervalSince1970: 20),
        isFavorite: true,
        includeSensitiveFields: false
    )

    #expect(payload.fields["title"] == "Create issue")
    #expect(payload.fields["url"] == "https://api.example.com/issues")
    #expect(payload.fields["headers"] == nil)
    #expect(payload.fields["body"] == nil)
}

@Test
func apiRecordPayloadIncludesSensitiveFieldsWhenAllowed() {
    let payload = ICloudSyncPayloadFactory.apiRecordPayload(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000102")!,
        title: "Create issue",
        url: "https://api.example.com/issues",
        method: "POST",
        requestType: "JSON",
        headers: "Authorization: Bearer secret",
        body: "{\"token\":\"secret\"}",
        provider: nil,
        tags: [],
        notes: "",
        createdAt: Date(timeIntervalSince1970: 10),
        lastOpenedAt: Date(timeIntervalSince1970: 20),
        isFavorite: false,
        includeSensitiveFields: true
    )

    #expect(payload.fields["headers"] == "Authorization: Bearer secret")
    #expect(payload.fields["body"] == "{\"token\":\"secret\"}")
}

@Test
func terminalServerPayloadExcludesSecretReferenceKeys() {
    let payload = ICloudSyncPayloadFactory.terminalServerPayload(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000201")!,
        name: "Production",
        host: "server.example.com",
        port: 22,
        username: "deploy",
        authMethod: "privateKey",
        remoteOSFamily: "ubuntu",
        passwordSecretKey: "ios.terminal.server.password",
        privateKeySecretKey: "ios.terminal.server.privateKey",
        privateKeyPassphraseSecretKey: "ios.terminal.server.passphrase",
        createdAt: Date(timeIntervalSince1970: 10),
        updatedAt: Date(timeIntervalSince1970: 20),
        lastConnectedAt: Date(timeIntervalSince1970: 30)
    )

    #expect(payload.fields["name"] == "Production")
    #expect(payload.fields["host"] == "server.example.com")
    #expect(payload.fields["passwordSecretKey"] == nil)
    #expect(payload.fields["privateKeySecretKey"] == nil)
    #expect(payload.fields["privateKeyPassphraseSecretKey"] == nil)
    #expect(payload.needsCredentialRestore)
}

@Test
func chatConversationPayloadIncludesRecoverableMetadata() {
    let payload = ICloudSyncPayloadFactory.chatConversationPayload(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000401")!,
        title: "Deploy plan",
        remark: "Work",
        tag: "Hermes",
        lastMessagePreview: "Ship it",
        messageCount: 3,
        providerRawValue: "hermes",
        remoteSessionId: "remote-1",
        remoteSource: "server",
        lastSyncedAt: Date(timeIntervalSince1970: 40),
        syncStateRawValue: "synced",
        isArchived: false,
        createdAt: Date(timeIntervalSince1970: 10),
        updatedAt: Date(timeIntervalSince1970: 20),
        archivedAt: nil
    )

    #expect(payload.entity == .chatConversation)
    #expect(payload.fields["title"] == "Deploy plan")
    #expect(payload.fields["messageCount"] == "3")
    #expect(payload.fields["providerRawValue"] == "hermes")
    #expect(payload.fields["remoteSessionId"] == "remote-1")
    #expect(payload.fields["isArchived"] == "false")
}

@Test
func chatMessagePayloadLinksBackToConversation() {
    let conversationID = UUID(uuidString: "00000000-0000-0000-0000-000000000501")!
    let payload = ICloudSyncPayloadFactory.chatMessagePayload(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000502")!,
        conversationID: conversationID,
        roleRawValue: "user",
        content: "Hello",
        contentFormatRawValue: "markdown",
        isComplete: true,
        remoteMessageId: "message-1",
        sortIndex: 2,
        createdAt: Date(timeIntervalSince1970: 10),
        completedAt: Date(timeIntervalSince1970: 12),
        errorMessage: nil
    )

    #expect(payload.entity == .chatMessage)
    #expect(payload.fields["conversationID"] == conversationID.uuidString)
    #expect(payload.fields["roleRawValue"] == "user")
    #expect(payload.fields["content"] == "Hello")
    #expect(payload.fields["sortIndex"] == "2")
    #expect(payload.fields["completedAt"] != nil)
}

@Test
func chatMessagesMergeByIDAndSortDeterministically() {
    let idA = UUID(uuidString: "00000000-0000-0000-0000-000000000301")!
    let idB = UUID(uuidString: "00000000-0000-0000-0000-000000000302")!
    let idC = UUID(uuidString: "00000000-0000-0000-0000-000000000303")!
    let local = [
        ICloudChatMessageSnapshot(id: idB, sortIndex: 2, createdAt: Date(timeIntervalSince1970: 2), updatedAt: Date(timeIntervalSince1970: 2), content: "old B"),
        ICloudChatMessageSnapshot(id: idA, sortIndex: 1, createdAt: Date(timeIntervalSince1970: 1), updatedAt: Date(timeIntervalSince1970: 1), content: "A")
    ]
    let remote = [
        ICloudChatMessageSnapshot(id: idB, sortIndex: 2, createdAt: Date(timeIntervalSince1970: 2), updatedAt: Date(timeIntervalSince1970: 5), content: "new B"),
        ICloudChatMessageSnapshot(id: idC, sortIndex: nil, createdAt: Date(timeIntervalSince1970: 3), updatedAt: Date(timeIntervalSince1970: 3), content: "C")
    ]

    let merged = ICloudSyncMergePolicy.mergeChatMessages(local: local, remote: remote)

    #expect(merged.map(\.id) == [idA, idB, idC])
    #expect(merged.map(\.content) == ["A", "new B", "C"])
}

@Test
func newerRecordWinsUnlessNewerSideIsDeleted() {
    let old = ICloudSyncRecord(
        id: "memo:1",
        entity: .memo,
        localID: "1",
        updatedAt: Date(timeIntervalSince1970: 10),
        deletedAt: nil,
        fields: ["content": "old"]
    )
    let newer = ICloudSyncRecord(
        id: "memo:1",
        entity: .memo,
        localID: "1",
        updatedAt: Date(timeIntervalSince1970: 20),
        deletedAt: nil,
        fields: ["content": "new"]
    )
    let deleted = ICloudSyncRecord(
        id: "memo:1",
        entity: .memo,
        localID: "1",
        updatedAt: Date(timeIntervalSince1970: 30),
        deletedAt: Date(timeIntervalSince1970: 30),
        fields: [:]
    )

    #expect(ICloudSyncMergePolicy.resolve(local: old, remote: newer) == newer)
    #expect(ICloudSyncMergePolicy.resolve(local: newer, remote: deleted) == deleted)
}
