import CloudKit
import Combine
import DevBarCore
import Foundation
import SwiftData

enum IOSICloudSyncAvailability: Equatable {
    case notChecked
    case checking
    case available
    case unavailable(String)

    var title: String {
        switch self {
        case .notChecked:
            return "未检查"
        case .checking:
            return "正在检查 iCloud"
        case .available:
            return "iCloud 可用"
        case .unavailable(let message):
            return message
        }
    }
}

enum IOSICloudSyncRunState: Equatable {
    case idle
    case syncing
    case completed(Date)
    case failed(String)

    var title: String {
        switch self {
        case .idle:
            return "未同步"
        case .syncing:
            return "同步中"
        case .completed(let date):
            return "已同步 \(date.formatted(date: .omitted, time: .shortened))"
        case .failed(let message):
            return message
        }
    }
}

@MainActor
final class ICloudSyncCoordinator: ObservableObject {
    static let shared = ICloudSyncCoordinator()

    @Published private(set) var settings: ICloudSyncSettings
    @Published private(set) var availability: IOSICloudSyncAvailability = .notChecked
    @Published private(set) var runState: IOSICloudSyncRunState = .idle
    @Published private(set) var lastCheckedAt: Date?

    private let settingsStore: ICloudSyncSettingsStore
    private let container: CKContainer
    private var pendingAssetURLs: [URL] = []
    private let zoneID = CKRecordZone.ID(zoneName: "DevBarUserDataV1", ownerName: CKCurrentUserDefaultName)

    init(
        settingsStore: ICloudSyncSettingsStore = UserDefaultsICloudSyncSettingsStore(),
        container: CKContainer = CKContainer(identifier: DevBarCoreConstants.ICloud.containerIdentifier)
    ) {
        self.settingsStore = settingsStore
        self.container = container
        self.settings = settingsStore.load()
    }

    func setEnabled(_ isEnabled: Bool) {
        settings.isEnabled = isEnabled
        persist()
        if isEnabled {
            Task { await refreshAvailability() }
        }
    }

    func setEntity(_ entity: ICloudSyncEntity, enabled: Bool) {
        if enabled {
            settings.enabledEntities.insert(entity)
        } else {
            settings.enabledEntities.remove(entity)
        }
        persist()
    }

    func setSyncAPISensitiveFields(_ enabled: Bool) {
        settings.syncAPISensitiveFields = enabled
        persist()
    }

    func setSyncTerminalSecrets(_ enabled: Bool) {
        settings.syncTerminalSecrets = enabled
        persist()
    }

    func setSyncProviderCredentials(_ enabled: Bool) {
        settings.syncProviderCredentials = enabled
        persist()
    }

    func refreshAvailability() async {
        availability = .checking
        do {
            let status = try await container.accountStatus()
            lastCheckedAt = Date()
            switch status {
            case .available:
                availability = .available
            case .couldNotDetermine:
                availability = .unavailable("无法确认 iCloud 状态")
            case .noAccount:
                availability = .unavailable("未登录 iCloud")
            case .restricted:
                availability = .unavailable("iCloud 受限制")
            case .temporarilyUnavailable:
                availability = .unavailable("iCloud 暂时不可用")
            @unknown default:
                availability = .unavailable("iCloud 状态未知")
            }
        } catch {
            lastCheckedAt = Date()
            availability = .unavailable(error.localizedDescription)
        }
    }

    func syncNow(modelContext: ModelContext) async {
        guard settings.isEnabled else {
            runState = .failed("请先开启 iCloud 同步")
            return
        }
        guard case .available = availability else {
            await refreshAvailability()
            guard case .available = availability else {
                runState = .failed("iCloud 不可用，无法同步")
                return
            }
            return await syncNow(modelContext: modelContext)
        }

        runState = .syncing
        do {
            try await ensureZoneExists()
        } catch {
            runState = .failed(Self.syncErrorMessage(error, stage: "创建云端区域"))
            return
        }

        let remoteRecords: [ICloudSyncRecord]
        do {
            remoteRecords = try await fetchRemoteRecords()
        } catch {
            runState = .failed(Self.syncErrorMessage(error, stage: "读取云端数据"))
            return
        }

        do {
            try importRemoteRecords(remoteRecords, modelContext: modelContext)
            try modelContext.save()
        } catch {
            runState = .failed("导入本地数据失败：\(error.localizedDescription)")
            return
        }

        let localRecords: [ICloudSyncRecord]
        do {
            localRecords = try exportLocalRecords(modelContext: modelContext)
        } catch {
            runState = .failed("读取本地数据失败：\(error.localizedDescription)")
            return
        }

        do {
            let uploadResult = try await upload(localRecords)
            runState = .completed(Date())
            if uploadResult.skippedCount > 0 {
                runState = .failed("已同步 \(uploadResult.uploadedCount) 条，跳过 \(uploadResult.skippedCount) 条过大的记录")
            }
        } catch {
            runState = .failed(Self.syncErrorMessage(error, stage: "上传本地数据"))
        }
    }

    private func persist() {
        settingsStore.save(settings)
    }

    private func ensureZoneExists() async throws {
        let zone = CKRecordZone(zoneID: zoneID)
        _ = try await container.privateCloudDatabase.modifyRecordZones(saving: [zone], deleting: [])
    }

    private func upload(_ records: [ICloudSyncRecord]) async throws -> ICloudSyncUploadResult {
        pendingAssetURLs.removeAll()
        defer { cleanupPendingAssets() }

        var uploadedCount = 0
        var skippedCount = 0
        for syncRecord in records {
            do {
                let ckRecord = try makeCloudRecord(from: syncRecord)
                _ = try await container.privateCloudDatabase.modifyRecords(
                    saving: [ckRecord],
                    deleting: [],
                    savePolicy: .changedKeys,
                    atomically: true
                )
                uploadedCount += 1
            } catch is ICloudSyncPayloadTooLargeError {
                skippedCount += 1
            } catch {
                throw ICloudSyncUploadError(record: syncRecord, underlying: error)
            }
        }
        return ICloudSyncUploadResult(uploadedCount: uploadedCount, skippedCount: skippedCount)
    }

    private func fetchRemoteRecords() async throws -> [ICloudSyncRecord] {
        var records: [ICloudSyncRecord] = []
        for entity in settings.enabledEntities where entity.isFirstVersionCloudKitEntity {
            do {
                records += try await fetchRemoteRecords(for: entity)
            } catch {
                if Self.isRecoverableEmptyRemoteQueryError(error) {
                    continue
                }
                throw error
            }
        }
        return records
    }

    private func fetchRemoteRecords(for entity: ICloudSyncEntity) async throws -> [ICloudSyncRecord] {
        var records: [ICloudSyncRecord] = []
        var cursor: CKQueryOperation.Cursor?
        repeat {
            let result: (matchResults: [(CKRecord.ID, Result<CKRecord, Error>)], queryCursor: CKQueryOperation.Cursor?)
            if let cursor {
                result = try await container.privateCloudDatabase.records(continuingMatchFrom: cursor)
            } else {
                let query = CKQuery(recordType: entity.cloudRecordType, predicate: NSPredicate(value: true))
                result = try await container.privateCloudDatabase.records(
                    matching: query,
                    inZoneWith: zoneID,
                    desiredKeys: ["payload", "payloadAsset", "entity", "localID", "updatedAt", "deletedAt", "needsCredentialRestore"],
                    resultsLimit: CKQueryOperation.maximumResults
                )
            }

            for (_, recordResult) in result.matchResults {
                guard let record = try? recordResult.get(),
                      let decoded = decodeCloudRecord(record) else {
                    continue
                }
                records.append(decoded)
            }
            cursor = result.queryCursor
        } while cursor != nil
        return records
    }

    private static func isRecoverableEmptyRemoteQueryError(_ error: Error) -> Bool {
        switch cloudKitErrorCode(from: error) {
        case .serverRejectedRequest, .unknownItem:
            return true
        case .partialFailure:
            return partialCloudKitErrors(from: error)?.allSatisfy(isRecoverableEmptyRemoteQueryError) == true
        default:
            return false
        }
    }

    private static func syncErrorMessage(_ error: Error, stage: String) -> String {
        if let uploadError = error as? ICloudSyncUploadError {
            let payloadBytes = uploadError.record.encodedPayloadByteCount
            return "\(stage)失败：\(uploadError.record.entity.rawValue) \(uploadError.record.localID) payload=\(payloadBytes)B，\(syncErrorMessage(uploadError.underlying, stage: "CloudKit"))"
        }
        guard let code = cloudKitErrorCode(from: error) else {
            return "\(stage)失败：\(error.localizedDescription)"
        }

        var message = "\(stage)失败：CloudKit \(code.rawValue): \(error.localizedDescription)"
        let nsError = error as NSError
        let detailKeys = [
            "CKErrorDescription",
            "CKErrorServerDescription",
            NSLocalizedFailureReasonErrorKey,
            NSDebugDescriptionErrorKey,
        ]
        for key in detailKeys {
            guard let detail = nsError.userInfo[key] as? String,
                  !detail.isEmpty,
                  !message.contains(detail) else { continue }
            message += " - \(detail)"
        }
        if let partialErrors = partialCloudKitErrors(from: error), !partialErrors.isEmpty {
            let details = partialErrors
                .prefix(3)
                .map { syncErrorMessage($0, stage: "部分记录") }
                .joined(separator: "；")
            message += " - \(details)"
        }
        return message
    }

    private static func cloudKitErrorCode(from error: Error) -> CKError.Code? {
        if let ckError = error as? CKError {
            return ckError.code
        }
        let nsError = error as NSError
        guard nsError.domain == CKError.errorDomain else {
            return nil
        }
        return CKError.Code(rawValue: nsError.code)
    }

    private static func partialCloudKitErrors(from error: Error) -> [Error]? {
        if let ckError = error as? CKError {
            return ckError.partialErrorsByItemID?.values.map { $0 }
        }
        let nsError = error as NSError
        guard nsError.domain == CKError.errorDomain else {
            return nil
        }
        let errorsByID = nsError.userInfo[CKPartialErrorsByItemIDKey] as? [AnyHashable: Error]
        return errorsByID?.values.map { $0 }
    }

    private static func syncErrorMessage(_ error: Error) -> String {
        guard let code = cloudKitErrorCode(from: error) else {
            return error.localizedDescription
        }
        return "CloudKit \(code.rawValue): \(error.localizedDescription)"
    }

    private func exportLocalRecords(modelContext: ModelContext) throws -> [ICloudSyncRecord] {
        var records: [ICloudSyncRecord] = []
        if settings.isSyncEnabled(for: .memo) {
            let memos = try modelContext.fetch(FetchDescriptor<IOSMemoItem>())
            records += memos.map {
                ICloudSyncPayloadFactory.memoPayload(
                    id: $0.id,
                    title: $0.title,
                    content: $0.content,
                    encryptedData: $0.encryptedData,
                    isEncrypted: $0.isEncrypted,
                    createdAt: $0.createdAt,
                    updatedAt: $0.updatedAt
                )
            }
        }
        if settings.isSyncEnabled(for: .markdownDocument) {
            let documents = try modelContext.fetch(FetchDescriptor<IOSMarkdownDocument>())
            records += documents.map {
                ICloudSyncPayloadFactory.markdownDocumentPayload(
                    id: $0.id,
                    title: $0.title,
                    content: $0.content,
                    createdAt: $0.createdAt,
                    updatedAt: $0.updatedAt
                )
            }
        }
        if settings.isSyncEnabled(for: .terminalServer) {
            let servers = try modelContext.fetch(FetchDescriptor<IOSTerminalServer>())
            records += servers.map {
                ICloudSyncPayloadFactory.terminalServerPayload(
                    id: $0.id,
                    name: $0.name,
                    host: $0.host,
                    port: $0.port,
                    username: $0.username,
                    authMethod: $0.authMethodRawValue,
                    remoteOSFamily: $0.remoteOSFamilyRawValue,
                    passwordSecretKey: $0.passwordSecretKey,
                    privateKeySecretKey: $0.privateKeySecretKey,
                    privateKeyPassphraseSecretKey: $0.privateKeyPassphraseSecretKey,
                    createdAt: $0.createdAt,
                    updatedAt: $0.updatedAt,
                    lastConnectedAt: $0.lastConnectedAt
                )
            }
        }
        if settings.isSyncEnabled(for: .chatConversation) {
            let conversations = try modelContext.fetch(FetchDescriptor<IOSHermesConversation>())
            records += conversations.map {
                ICloudSyncPayloadFactory.chatConversationPayload(
                    id: $0.id,
                    title: $0.title,
                    remark: $0.remark,
                    tag: $0.tag,
                    lastMessagePreview: $0.lastMessagePreview,
                    messageCount: $0.messageCount,
                    providerRawValue: $0.providerRawValue,
                    remoteSessionId: $0.remoteSessionId,
                    remoteSource: $0.remoteSource,
                    lastSyncedAt: $0.lastSyncedAt,
                    syncStateRawValue: $0.syncStateRawValue,
                    isArchived: $0.isArchived,
                    createdAt: $0.createdAt,
                    updatedAt: $0.updatedAt,
                    archivedAt: $0.archivedAt
                )
            }
        }
        if settings.isSyncEnabled(for: .chatMessage) {
            let messages = try modelContext.fetch(FetchDescriptor<IOSHermesMessage>())
            records += messages.compactMap { message in
                guard let conversationID = message.conversation?.id else {
                    return nil
                }
                return ICloudSyncPayloadFactory.chatMessagePayload(
                    id: message.id,
                    conversationID: conversationID,
                    roleRawValue: message.roleRawValue,
                    content: message.content,
                    contentFormatRawValue: message.contentFormatRawValue,
                    isComplete: message.isComplete,
                    remoteMessageId: message.remoteMessageId,
                    sortIndex: message.sortIndex,
                    createdAt: message.createdAt,
                    completedAt: message.completedAt,
                    errorMessage: message.errorMessage
                )
            }
        }
        return records
    }

    private func importRemoteRecords(_ records: [ICloudSyncRecord], modelContext: ModelContext) throws {
        try importMemos(records.filter { $0.entity == .memo }, modelContext: modelContext)
        try importMarkdownDocuments(records.filter { $0.entity == .markdownDocument }, modelContext: modelContext)
        try importTerminalServers(records.filter { $0.entity == .terminalServer }, modelContext: modelContext)
        try importChatConversations(records.filter { $0.entity == .chatConversation }, modelContext: modelContext)
        try importChatMessages(records.filter { $0.entity == .chatMessage }, modelContext: modelContext)
    }

    private func importMemos(_ records: [ICloudSyncRecord], modelContext: ModelContext) throws {
        let existing = try modelContext.fetch(FetchDescriptor<IOSMemoItem>())
        var byID = Dictionary(uniqueKeysWithValues: existing.map { ($0.id.uuidString.lowercased(), $0) })
        for record in records {
            guard let id = UUID(uuidString: record.localID),
                  let updatedAt = record.dateField("updatedAt") else { continue }
            let item = byID[id.uuidString.lowercased()] ?? IOSMemoItem(id: id)
            if item.updatedAt > updatedAt {
                continue
            }
            item.title = record.fields["title"] ?? ""
            item.content = record.fields["content"] ?? ""
            item.encryptedData = record.fields["encryptedData"].flatMap { Data(base64Encoded: $0) }
            item.isEncrypted = record.boolField("isEncrypted") ?? false
            item.createdAt = record.dateField("createdAt") ?? item.createdAt
            item.updatedAt = updatedAt
            if byID[id.uuidString.lowercased()] == nil {
                modelContext.insert(item)
                byID[id.uuidString.lowercased()] = item
            }
        }
    }

    private func importMarkdownDocuments(_ records: [ICloudSyncRecord], modelContext: ModelContext) throws {
        let existing = try modelContext.fetch(FetchDescriptor<IOSMarkdownDocument>())
        var byID = Dictionary(uniqueKeysWithValues: existing.map { ($0.id.uuidString.lowercased(), $0) })
        for record in records {
            guard let id = UUID(uuidString: record.localID),
                  let updatedAt = record.dateField("updatedAt") else { continue }
            let document = byID[id.uuidString.lowercased()] ?? IOSMarkdownDocument(id: id)
            if document.updatedAt > updatedAt {
                continue
            }
            document.title = record.fields["title"] ?? ""
            document.content = record.fields["content"] ?? ""
            document.createdAt = record.dateField("createdAt") ?? document.createdAt
            document.updatedAt = updatedAt
            if byID[id.uuidString.lowercased()] == nil {
                modelContext.insert(document)
                byID[id.uuidString.lowercased()] = document
            }
        }
    }

    private func importTerminalServers(_ records: [ICloudSyncRecord], modelContext: ModelContext) throws {
        let existing = try modelContext.fetch(FetchDescriptor<IOSTerminalServer>())
        var byID = Dictionary(uniqueKeysWithValues: existing.map { ($0.id.uuidString.lowercased(), $0) })
        for record in records {
            guard let id = UUID(uuidString: record.localID),
                  let name = record.fields["name"],
                  let host = record.fields["host"],
                  let portText = record.fields["port"],
                  let port = Int(portText),
                  let username = record.fields["username"] else {
                continue
            }
            let remoteUpdatedAt = record.dateField("updatedAt")
            let server = byID[id.uuidString.lowercased()] ?? IOSTerminalServer(
                id: id,
                name: name,
                host: host,
                port: port,
                username: username
            )
            if let remoteUpdatedAt,
               server.updatedAt > remoteUpdatedAt {
                continue
            }
            server.name = name
            server.host = host
            server.port = port
            server.username = username
            server.authMethodRawValue = record.fields["authMethod"] ?? server.authMethodRawValue
            server.remoteOSFamilyRawValue = record.fields["remoteOSFamily"]
            server.createdAt = record.dateField("createdAt") ?? server.createdAt
            server.updatedAt = remoteUpdatedAt ?? server.updatedAt
            server.lastConnectedAt = record.dateField("lastConnectedAt")
            if byID[id.uuidString.lowercased()] == nil {
                modelContext.insert(server)
                byID[id.uuidString.lowercased()] = server
            }
        }
    }

    private func importChatConversations(_ records: [ICloudSyncRecord], modelContext: ModelContext) throws {
        let existing = try modelContext.fetch(FetchDescriptor<IOSHermesConversation>())
        var byID = Dictionary(uniqueKeysWithValues: existing.map { ($0.id.uuidString.lowercased(), $0) })
        for record in records {
            guard let id = UUID(uuidString: record.localID),
                  let updatedAt = record.dateField("updatedAt") else { continue }
            let key = id.uuidString.lowercased()
            let conversation = byID[key] ?? IOSHermesConversation(id: id)
            if conversation.updatedAt > updatedAt {
                continue
            }
            conversation.title = record.fields["title"] ?? conversation.title
            conversation.remark = record.fields["remark"]
            conversation.tag = record.fields["tag"]
            conversation.lastMessagePreview = record.fields["lastMessagePreview"] ?? ""
            conversation.messageCount = record.intField("messageCount") ?? 0
            conversation.providerRawValue = record.fields["providerRawValue"]
            conversation.remoteSessionId = record.fields["remoteSessionId"]
            conversation.remoteSource = record.fields["remoteSource"]
            conversation.lastSyncedAt = record.dateField("lastSyncedAt")
            conversation.syncStateRawValue = record.fields["syncStateRawValue"] ?? "synced"
            conversation.isArchived = record.boolField("isArchived") ?? false
            conversation.createdAt = record.dateField("createdAt") ?? conversation.createdAt
            conversation.updatedAt = updatedAt
            conversation.archivedAt = record.dateField("archivedAt")
            if byID[key] == nil {
                modelContext.insert(conversation)
                byID[key] = conversation
            }
        }
    }

    private func importChatMessages(_ records: [ICloudSyncRecord], modelContext: ModelContext) throws {
        let conversations = try modelContext.fetch(FetchDescriptor<IOSHermesConversation>())
        let conversationsByID = Dictionary(uniqueKeysWithValues: conversations.map { ($0.id.uuidString.lowercased(), $0) })
        let existing = try modelContext.fetch(FetchDescriptor<IOSHermesMessage>())
        var messagesByID = Dictionary(uniqueKeysWithValues: existing.map { ($0.id.uuidString.lowercased(), $0) })

        for record in records {
            guard let id = UUID(uuidString: record.localID),
                  let conversationIDText = record.fields["conversationID"],
                  let conversationID = UUID(uuidString: conversationIDText),
                  let conversation = conversationsByID[conversationID.uuidString.lowercased()] else {
                continue
            }
            let remoteUpdatedAt = record.dateField("updatedAt") ?? record.updatedAt
            let key = id.uuidString.lowercased()
            let roleRawValue = record.fields["roleRawValue"] ?? HermesChatRole.assistant.rawValue
            let formatRawValue = record.fields["contentFormatRawValue"] ?? IOSHermesMessageContentFormat.markdown.rawValue
            let message = messagesByID[key] ?? IOSHermesMessage(
                id: id,
                role: HermesChatRole(rawValue: roleRawValue) ?? .assistant,
                content: record.fields["content"] ?? "",
                contentFormat: IOSHermesMessageContentFormat(rawValue: formatRawValue) ?? .markdown,
                isComplete: record.boolField("isComplete") ?? true,
                remoteMessageId: record.fields["remoteMessageId"],
                sortIndex: record.intField("sortIndex"),
                createdAt: record.dateField("createdAt") ?? remoteUpdatedAt,
                completedAt: record.dateField("completedAt"),
                errorMessage: record.fields["errorMessage"],
                conversation: conversation
            )
            let localUpdatedAt = message.completedAt ?? message.createdAt
            if localUpdatedAt > remoteUpdatedAt {
                continue
            }
            message.roleRawValue = roleRawValue
            message.content = record.fields["content"] ?? ""
            message.contentFormatRawValue = formatRawValue
            message.isComplete = record.boolField("isComplete") ?? true
            message.remoteMessageId = record.fields["remoteMessageId"]
            message.sortIndex = record.intField("sortIndex")
            message.createdAt = record.dateField("createdAt") ?? message.createdAt
            message.completedAt = record.dateField("completedAt")
            message.errorMessage = record.fields["errorMessage"]
            message.conversation = conversation
            if messagesByID[key] == nil {
                modelContext.insert(message)
                messagesByID[key] = message
            }
        }
    }

    private func makeCloudRecord(from syncRecord: ICloudSyncRecord) throws -> CKRecord {
        let recordID = CKRecord.ID(recordName: syncRecord.id, zoneID: zoneID)
        let record = CKRecord(recordType: syncRecord.entity.cloudRecordType, recordID: recordID)
        record["entity"] = syncRecord.entity.rawValue as CKRecordValue
        record["localID"] = syncRecord.localID as CKRecordValue
        record["updatedAt"] = syncRecord.updatedAt as CKRecordValue
        record["needsCredentialRestore"] = NSNumber(value: syncRecord.needsCredentialRestore)
        if let deletedAt = syncRecord.deletedAt {
            record["deletedAt"] = deletedAt as CKRecordValue
        }
        let payload = try JSONEncoder().encode(syncRecord)
        record["payloadAsset"] = try makePayloadAsset(from: payload, recordID: syncRecord.id)
        return record
    }

    private func makePayloadAsset(from payload: Data, recordID: String) throws -> CKAsset {
        guard payload.count <= 50 * 1024 * 1024 else {
            throw ICloudSyncPayloadTooLargeError()
        }
        let directory = FileManager.default.temporaryDirectory.appending(path: "DevBarICloudSync", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let safeName = recordID
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: "/", with: "-")
        let url = directory.appending(path: "\(safeName)-\(UUID().uuidString).json", directoryHint: .notDirectory)
        try payload.write(to: url, options: .atomic)
        pendingAssetURLs.append(url)
        return CKAsset(fileURL: url)
    }

    private func cleanupPendingAssets() {
        for url in pendingAssetURLs {
            try? FileManager.default.removeItem(at: url)
        }
        pendingAssetURLs.removeAll()
    }

    private func decodeCloudRecord(_ record: CKRecord) -> ICloudSyncRecord? {
        if let payload = record["payload"] as? Data,
           let decoded = try? JSONDecoder().decode(ICloudSyncRecord.self, from: payload) {
            return decoded
        }
        if let asset = record["payloadAsset"] as? CKAsset,
           let fileURL = asset.fileURL,
           let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode(ICloudSyncRecord.self, from: data) {
            return decoded
        }
        guard let entityRawValue = record["entity"] as? String,
              let entity = ICloudSyncEntity(rawValue: entityRawValue),
              let localID = record["localID"] as? String,
              let updatedAt = record["updatedAt"] as? Date else {
            return nil
        }
        return ICloudSyncRecord(
            id: record.recordID.recordName,
            entity: entity,
            localID: localID,
            updatedAt: updatedAt,
            deletedAt: record["deletedAt"] as? Date,
            fields: [:],
            needsCredentialRestore: (record["needsCredentialRestore"] as? Int) == 1
        )
    }
}

private struct ICloudSyncUploadResult {
    var uploadedCount: Int
    var skippedCount: Int
}

private struct ICloudSyncUploadError: Error {
    var record: ICloudSyncRecord
    var underlying: Error
}

private struct ICloudSyncPayloadTooLargeError: Error {}

private extension ICloudSyncRecord {
    var encodedPayloadByteCount: Int {
        (try? JSONEncoder().encode(self).count) ?? 0
    }
}

private extension ICloudSyncEntity {
    var cloudRecordType: String {
        switch self {
        case .memo:
            return "Memo"
        case .markdownDocument:
            return "MarkdownDocument"
        case .chatConversation:
            return "ChatConversation"
        case .chatMessage:
            return "ChatMessage"
        case .apiRecord:
            return "APIRecord"
        case .terminalServer:
            return "TerminalServer"
        case .webHistoryRecord:
            return "WebHistoryRecord"
        }
    }

    var isFirstVersionCloudKitEntity: Bool {
        switch self {
        case .memo, .markdownDocument, .chatConversation, .chatMessage, .terminalServer:
            return true
        case .apiRecord, .webHistoryRecord:
            return false
        }
    }
}

private extension ICloudSyncRecord {
    func dateField(_ key: String) -> Date? {
        guard let value = fields[key] else { return nil }
        return ISO8601DateFormatter().date(from: value)
    }

    func boolField(_ key: String) -> Bool? {
        guard let value = fields[key] else { return nil }
        return Bool(value)
    }

    func intField(_ key: String) -> Int? {
        guard let value = fields[key] else { return nil }
        return Int(value)
    }
}
