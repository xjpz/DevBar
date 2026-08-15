import Combine
import DevBarCore
import Foundation
import Network

@MainActor
final class IOSHomeAssistantViewModel: ObservableObject {
    @Published private(set) var settings: HomeAssistantConnectionSettings
    @Published private(set) var connectionState: HomeAssistantConnectionState
    @Published private(set) var snapshot: HomeAssistantSnapshot?
    @Published private(set) var snapshotPhase: HomeAssistantSnapshotPhase = .empty
    @Published private(set) var hiddenCardIDs = Set<String>()
    @Published private(set) var dashboardLayout = HomeAssistantDashboardLayoutSettings()
    @Published private(set) var devicePresentations: [String: HomeAssistantDevicePresentation] = [:]
    @Published private(set) var accessoryPresentations: [String: HomeAssistantAccessoryPresentation] = [:]
    @Published private(set) var accessoryGrouping = HomeAssistantAccessoryGroupingSettings()
    @Published private(set) var translationCatalog: HomeAssistantTranslationCatalog
    @Published private(set) var cacheSavedAt: Date?
    @Published private(set) var layoutSuggestion = HomeAssistantLayoutSuggestion()
    @Published private(set) var pendingEntityIDs = Set<String>()
    @Published private(set) var isLoading = false
    @Published private(set) var isAnalyzing = false
    @Published private(set) var pendingLayoutSuggestion: HomeAssistantLayoutSuggestion?
    @Published private(set) var allAccessories: [HomeAssistantAccessory] = []
    @Published var selectedRoomID: String?
    @Published var errorMessage: String?

    private let settingsStore: HomeAssistantSettingsStore
    private let restClient: HomeAssistantRESTClient
    private let socket: HomeAssistantWebSocketClient
    private let snapshotCacheStore: HomeAssistantSnapshotCacheStore
    private let hermesClient: HermesAPIClient
    private let diagnostics: HomeAssistantDiagnosticReporter
    private let pathMonitor: NWPathMonitor
    private let wifiSSIDProvider: any IOSWiFiSSIDProviding
    private let monitorQueue = DispatchQueue(label: "cc.xjpz.DevBar.home-assistant.network")

    private var networkInterface: HomeAssistantNetworkInterface = .other
    private var connectedCandidate: HomeAssistantEndpointCandidate?
    private var eventTask: Task<Void, Never>?
    private var connectionTask: Task<Void, Never>?
    private var connectionGeneration = 0
    private var stateProjectionTask: Task<Void, Never>?
    private var cacheSaveTask: Task<Void, Never>?
    private var translationTask: Task<Void, Never>?
    private var observers = Set<AnyCancellable>()
    private var hasRestoredCache = false
    private var cacheWritesSuspended = false
    private var rawStatesByID: [String: HomeAssistantState] = [:]
    private var pendingStateUpdates: [String: HomeAssistantState] = [:]
    private var semanticStatesByAccessoryID: [String: HomeAssistantAccessorySemanticState] = [:]
    private var registryEntries: [HomeAssistantEntityRegistryEntry] = []
    private var areas: [HomeAssistantArea] = []
    private var devices: [HomeAssistantDevice] = []
    private var services: [HomeAssistantService] = []
    private var config: HomeAssistantConfig?

    init(
        settingsStore: HomeAssistantSettingsStore = HomeAssistantSettingsStore(),
        restClient: HomeAssistantRESTClient = HomeAssistantRESTClient(),
        socket: HomeAssistantWebSocketClient = HomeAssistantWebSocketClient(),
        snapshotCacheStore: HomeAssistantSnapshotCacheStore = HomeAssistantSnapshotCacheStore(),
        hermesClient: HermesAPIClient = HermesAPIClient(),
        diagnostics: HomeAssistantDiagnosticReporter = .shared,
        pathMonitor: NWPathMonitor = NWPathMonitor(),
        wifiSSIDProvider: (any IOSWiFiSSIDProviding)? = nil
    ) {
        self.settingsStore = settingsStore
        self.restClient = restClient
        self.socket = socket
        self.snapshotCacheStore = snapshotCacheStore
        self.hermesClient = hermesClient
        self.diagnostics = diagnostics
        self.pathMonitor = pathMonitor
        self.wifiSSIDProvider = wifiSSIDProvider ?? IOSWiFiSSIDProvider()
        self.translationCatalog = HomeAssistantTranslationCatalog(language: Self.preferredTranslationLanguage)
        let settings = settingsStore.load()
        self.settings = settings
        self.connectionState = settings.isConfigured ? .offline : .notConfigured
        if let fingerprint = HomeAssistantSnapshotCacheStore.instanceFingerprint(externalURL: settings.externalURL) {
            self.hiddenCardIDs = settingsStore.loadDeviceVisibility(
                instanceFingerprint: fingerprint
            ).hiddenCardIDs
            self.dashboardLayout = settingsStore.loadDashboardLayout(instanceFingerprint: fingerprint)
            self.devicePresentations = settingsStore.loadDevicePresentations(
                instanceFingerprint: fingerprint
            ).devices
            self.accessoryPresentations = settingsStore.loadAccessoryPresentations(
                instanceFingerprint: fingerprint
            ).accessories
            self.accessoryGrouping = settingsStore.loadAccessoryGrouping(
                instanceFingerprint: fingerprint
            )
            self.translationCatalog = settingsStore.loadTranslationCatalog(
                instanceFingerprint: fingerprint,
                language: Self.preferredTranslationLanguage
            )
            if let envelope = snapshotCacheStore.load(instanceFingerprint: fingerprint) {
                self.snapshot = envelope.snapshot
                self.snapshotPhase = .cached(savedAt: envelope.savedAt)
                self.cacheSavedAt = envelope.savedAt
                self.hasRestoredCache = true
                let topologyHash = HomeAssistantLayoutAnalyzer.topologyHash(for: envelope.snapshot)
                self.layoutSuggestion = settingsStore.loadLayoutSuggestion(topologyHash: topologyHash)
                    ?? HomeAssistantLayoutAnalyzer.deterministicSuggestion(
                        for: HomeAssistantSnapshotProjection.visibleSnapshot(
                            from: envelope.snapshot,
                            hiddenCardIDs: self.hiddenCardIDs
                        )
                    )
            }
        }
        rebuildAccessoryProjection()
        monitorNetwork()
        observeICloudSettingsChanges()
    }

    deinit {
        pathMonitor.cancel()
        eventTask?.cancel()
        connectionTask?.cancel()
        stateProjectionTask?.cancel()
        cacheSaveTask?.cancel()
        translationTask?.cancel()
    }

    var token: String { settingsStore.loadToken() }
    var isConfigured: Bool { settings.isConfigured && !token.isEmpty }
    var homeDisplayName: String {
        let liveName = snapshot?.config.locationName.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !liveName.isEmpty { return liveName }
        let savedName = settings.lastKnownLocationName.trimmingCharacters(in: .whitespacesAndNewlines)
        return savedName.isEmpty ? "我的家" : savedName
    }
    var canControlDevices: Bool {
        snapshotPhase.allowsControl && connectedCandidate != nil
    }

    var visibleSnapshot: HomeAssistantSnapshot? {
        snapshot.map {
            HomeAssistantSnapshotProjection.visibleSnapshot(from: $0, hiddenCardIDs: hiddenCardIDs)
        }
    }

    var allVisibleCards: [HomeAssistantDeviceCard] {
        visibleSnapshot?.cards ?? []
    }

    var allVisibleAccessories: [HomeAssistantAccessory] {
        allAccessories.filter {
            !hiddenCardIDs.contains($0.id) && $0.areaID != nil
        }
    }

    var hiddenAccessories: [HomeAssistantAccessory] {
        allAccessories
            .filter { hiddenCardIDs.contains($0.id) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    var pendingAccessories: [HomeAssistantAccessory] {
        allAccessories
            .filter {
                !hiddenCardIDs.contains($0.id)
                    && ($0.areaID == nil || needsAccessoryOrganization($0))
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    var hiddenCards: [HomeAssistantDeviceCard] {
        snapshot?.cards
            .filter { hiddenCardIDs.contains($0.id) }
            .sorted { displayName(for: $0).localizedStandardCompare(displayName(for: $1)) == .orderedAscending } ?? []
    }

    var visibleEntities: [HomeAssistantEntity] {
        var seenEntityIDs = Set<String>()
        return allVisibleAccessories
            .flatMap(\.entities)
            .filter { seenEntityIDs.insert($0.entityID).inserted }
    }

    var cards: [HomeAssistantDeviceCard] {
        guard snapshot != nil else { return [] }
        let filtered: [HomeAssistantDeviceCard]
        if let selectedRoomID {
            if selectedRoomID == HomeAssistantTopologyBuilder.unassignedAreaID {
                filtered = allVisibleCards.filter { areaID(for: $0) == nil }
            } else {
                filtered = allVisibleCards.filter { areaID(for: $0) == selectedRoomID }
            }
        } else {
            filtered = allVisibleCards
        }

        let featuredOrder = Dictionary(uniqueKeysWithValues: layoutSuggestion.featuredEntityIDs.enumerated().map { ($1, $0) })
        return filtered.sorted { lhs, rhs in
            if lhs.isAvailable != rhs.isAvailable { return lhs.isAvailable }
            let left = featuredOrder[lhs.primaryEntityID] ?? Int.max
            let right = featuredOrder[rhs.primaryEntityID] ?? Int.max
            if left != right { return left < right }
            return displayName(for: lhs).localizedStandardCompare(displayName(for: rhs)) == .orderedAscending
        }
    }

    var accessories: [HomeAssistantAccessory] {
        let filtered: [HomeAssistantAccessory]
        if let selectedRoomID {
            if selectedRoomID == HomeAssistantTopologyBuilder.unassignedAreaID {
                filtered = allVisibleAccessories.filter { $0.areaID == nil }
            } else {
                filtered = allVisibleAccessories.filter { $0.areaID == selectedRoomID }
            }
        } else {
            filtered = allVisibleAccessories
        }

        let featuredOrder = Dictionary(
            uniqueKeysWithValues: layoutSuggestion.featuredEntityIDs.enumerated().map { ($1, $0) }
        )
        return filtered.sorted { lhs, rhs in
            let leftState = semanticState(for: lhs)
            let rightState = semanticState(for: rhs)
            let leftAvailable = leftState.availability == .available || leftState.availability == .partiallyAvailable
            let rightAvailable = rightState.availability == .available || rightState.availability == .partiallyAvailable
            if leftAvailable != rightAvailable { return leftAvailable }
            let left = lhs.primaryControlEntity.map { featuredOrder[$0.entityID] ?? Int.max } ?? Int.max
            let right = rhs.primaryControlEntity.map { featuredOrder[$0.entityID] ?? Int.max } ?? Int.max
            if left != right { return left < right }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    var rooms: [HomeAssistantRoom] {
        guard let snapshot else { return [] }
        let visibleAccessories = allVisibleAccessories
        let areaIDs = Set(visibleAccessories.compactMap(\.areaID))
        let rooms = snapshot.rooms.filter {
            $0.id != HomeAssistantTopologyBuilder.unassignedAreaID && areaIDs.contains($0.id)
        }
        let order = Dictionary(uniqueKeysWithValues: layoutSuggestion.roomOrder.enumerated().map { ($1, $0) })
        return rooms.sorted { lhs, rhs in
            let left = order[lhs.id] ?? Int.max
            let right = order[rhs.id] ?? Int.max
            if left != right { return left < right }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    var editableRooms: [HomeAssistantRoom] {
        snapshot?.rooms
            .filter { $0.id != HomeAssistantTopologyBuilder.unassignedAreaID }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending } ?? []
    }

    func displayName(for entity: HomeAssistantEntity) -> String {
        layoutSuggestion.aliases[entity.entityID] ?? entity.name
    }

    func displayName(for card: HomeAssistantDeviceCard) -> String {
        devicePresentations[card.id]?.customName ?? defaultDisplayName(for: card)
    }

    func displayType(for card: HomeAssistantDeviceCard) -> HomeAssistantDeviceDisplayType {
        devicePresentations[card.id]?.displayType ?? inferredDisplayType(for: card)
    }

    func systemImage(for card: HomeAssistantDeviceCard) -> String {
        if let presentation = devicePresentations[card.id] {
            return presentation.systemImage
        }
        guard let entity = card.primaryEntity else { return "square.stack.3d.up" }
        if let inferred = inferredDisplayTypeIfSupported(for: card) {
            return inferred.systemImage
        }
        return switch entity.domain {
        case "cover": "curtains.closed"
        case "lock": entity.state.state == "locked" ? "lock.fill" : "lock.open.fill"
        case "scene": "sparkles"
        case "script", "automation", "button": "play.circle.fill"
        case "sensor", "binary_sensor": "sensor.fill"
        default: "powerplug.fill"
        }
    }

    func areaID(for card: HomeAssistantDeviceCard) -> String? {
        guard let customAreaID = devicePresentations[card.id]?.customAreaID else { return card.areaID }
        return customAreaID == HomeAssistantTopologyBuilder.unassignedAreaID ? nil : customAreaID
    }

    func semanticState(for accessory: HomeAssistantAccessory) -> HomeAssistantAccessorySemanticState {
        semanticStatesByAccessoryID[accessory.id]
            ?? HomeAssistantAccessoryStateResolver.resolve(accessory, translations: translationCatalog)
    }

    func stateText(for entity: HomeAssistantEntity, role: HomeAssistantAccessoryRole? = nil) -> String {
        HomeAssistantStateFormatter.stateText(
            for: entity,
            role: role,
            translations: translationCatalog
        )
    }

    func attributeName(_ key: String, entity: HomeAssistantEntity) -> String {
        HomeAssistantStateFormatter.attributeName(key, entity: entity, translations: translationCatalog)
    }

    func attributeValue(
        key: String,
        value: HomeAssistantJSONValue,
        entity: HomeAssistantEntity
    ) -> String? {
        HomeAssistantStateFormatter.attributeValue(
            key: key,
            value: value,
            entity: entity,
            translations: translationCatalog
        )
    }

    func roomName(for accessory: HomeAssistantAccessory) -> String {
        guard let areaID = accessory.areaID else { return "未分配" }
        return snapshot?.rooms.first(where: { $0.id == areaID })?.name ?? "未分配"
    }

    func accessory(id: String) -> HomeAssistantAccessory? {
        allAccessories.first { $0.id == id }
    }

    func start() async {
        guard isConfigured else {
            connectionState = .notConfigured
            return
        }
        restoreCachedSnapshotIfNeeded()
        await reconnect()
    }

    func resume() async {
        restoreCachedSnapshotIfNeeded()
        let preferredCandidate = await endpointCandidates().first
        if connectedCandidate == preferredCandidate {
            await refresh()
        } else {
            await reconnect()
        }
    }

    func saveAndConnect(
        externalURL: String,
        internalURL: String,
        internalSSIDs: [String],
        token: String,
        aiAnalysisEnabled: Bool,
        showsDiagnosticEntities: Bool
    ) async throws {
        let previousFingerprint = instanceFingerprint
        let settings = HomeAssistantConnectionSettings(
            externalURL: externalURL,
            internalURL: internalURL,
            internalSSIDs: internalSSIDs,
            lastKnownLocationName: HomeAssistantSnapshotCacheStore.instanceFingerprint(externalURL: externalURL)
                == previousFingerprint ? self.settings.lastKnownLocationName : "",
            aiAnalysisEnabled: aiAnalysisEnabled,
            showsDiagnosticEntities: showsDiagnosticEntities
        )
        if !internalURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           internalSSIDs.contains(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            _ = await wifiSSIDProvider.currentSSID(requestAuthorization: true)
        }
        try settingsStore.save(settings, token: token)
        self.settings = settingsStore.load()
        let nextFingerprint = instanceFingerprint
        if previousFingerprint != nextFingerprint {
            resetSnapshotState()
            cacheWritesSuspended = false
            hasRestoredCache = false
            if let nextFingerprint {
                hiddenCardIDs = settingsStore.loadDeviceVisibility(
                    instanceFingerprint: nextFingerprint
                ).hiddenCardIDs
                dashboardLayout = settingsStore.loadDashboardLayout(instanceFingerprint: nextFingerprint)
                devicePresentations = settingsStore.loadDevicePresentations(
                    instanceFingerprint: nextFingerprint
                ).devices
                accessoryPresentations = settingsStore.loadAccessoryPresentations(
                    instanceFingerprint: nextFingerprint
                ).accessories
                accessoryGrouping = settingsStore.loadAccessoryGrouping(
                    instanceFingerprint: nextFingerprint
                )
                translationCatalog = settingsStore.loadTranslationCatalog(
                    instanceFingerprint: nextFingerprint,
                    language: Self.preferredTranslationLanguage
                )
            } else {
                hiddenCardIDs = []
                dashboardLayout = HomeAssistantDashboardLayoutSettings()
                devicePresentations = [:]
                accessoryPresentations = [:]
                accessoryGrouping = HomeAssistantAccessoryGroupingSettings()
                translationCatalog = HomeAssistantTranslationCatalog(language: Self.preferredTranslationLanguage)
            }
            restoreCachedSnapshotIfNeeded()
        }
        try await connectUsingAvailableEndpoint()
    }

    func detectCurrentSSID() async -> String? {
        await wifiSSIDProvider.currentSSID(requestAuthorization: true)
    }

    func updatePreferences(aiAnalysisEnabled: Bool, showsDiagnosticEntities: Bool) throws {
        var updated = settings
        updated.aiAnalysisEnabled = aiAnalysisEnabled
        updated.showsDiagnosticEntities = showsDiagnosticEntities
        try settingsStore.save(updated, token: nil)
        settings = settingsStore.load()
        rebuildSnapshot()
    }

    func clearConfiguration() {
        connectionGeneration += 1
        connectionTask?.cancel()
        eventTask?.cancel()
        cacheSaveTask?.cancel()
        translationTask?.cancel()
        cacheWritesSuspended = true
        if let instanceFingerprint {
            snapshotCacheStore.clear(instanceFingerprint: instanceFingerprint)
        }
        settingsStore.clear()
        settings = HomeAssistantConnectionSettings()
        resetSnapshotState()
        hiddenCardIDs = []
        dashboardLayout = HomeAssistantDashboardLayoutSettings()
        devicePresentations = [:]
        accessoryPresentations = [:]
        accessoryGrouping = HomeAssistantAccessoryGroupingSettings()
        translationCatalog = HomeAssistantTranslationCatalog(language: Self.preferredTranslationLanguage)
        layoutSuggestion = HomeAssistantLayoutSuggestion()
        pendingLayoutSuggestion = nil
        connectedCandidate = nil
        connectionState = .notConfigured
        Task { await socket.disconnect() }
    }

    func reconnect() async {
        connectionGeneration += 1
        let generation = connectionGeneration
        let previousTask = connectionTask
        previousTask?.cancel()
        if let previousTask { await previousTask.value }
        guard !Task.isCancelled, generation == connectionGeneration else { return }

        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await connectUsingAvailableEndpoint()
            } catch let error where HomeAssistantErrorClassifier.isCancellation(error) {
                return
            } catch {
                handle(error)
            }
        }
        connectionTask = task
        await task.value
    }

    func refresh() async {
        guard connectedCandidate != nil else {
            await reconnect()
            return
        }
        do {
            let states = try await socket.fetchStates()
            if snapshotPhase.allowsControl, config != nil {
                rawStatesByID = Self.indexedStates(states)
                rebuildSnapshot(phase: .authoritative)
            } else {
                applyFastStateSynchronization(states)
                try await loadAuthoritativeSnapshot(states: states, hadExistingSnapshot: snapshot != nil)
            }
        } catch {
            guard !Task.isCancelled, !HomeAssistantErrorClassifier.isCancellation(error) else { return }
            await reconnect()
        }
    }

    func performQuickAction(on entity: HomeAssistantEntity) async throws -> HomeAssistantServiceCall? {
        guard canControlDevices else { throw HomeAssistantError.disconnected }
        guard let action = HomeAssistantControlPolicy.quickAction(for: entity) else { return nil }
        let call = try HomeAssistantControlPolicy.serviceCall(entity: entity, action: action)
        if call.requiresConfirmation { return call }
        try await execute(call)
        return nil
    }

    func execute(_ call: HomeAssistantServiceCall) async throws {
        guard canControlDevices else { throw HomeAssistantError.disconnected }
        pendingEntityIDs.insert(call.targetEntityID)
        defer { pendingEntityIDs.remove(call.targetEntityID) }
        _ = try await socket.callService(call)
        try? await Task.sleep(for: .milliseconds(600))
        await refresh()
    }

    func analyzeWithHermes(settings hermesSettings: HermesSettings, apiKey: String) async {
        guard settings.aiAnalysisEnabled, let snapshot = visibleSnapshot else { return }
        guard !hermesSettings.apiBaseURL.isEmpty, !apiKey.isEmpty else {
            errorMessage = "请先在设置中配置 Hermes，或关闭 Home Assistant AI 整理"
            return
        }
        isAnalyzing = true
        defer { isAnalyzing = false }
        do {
            let prompt = try HomeAssistantLayoutAnalyzer.prompt(for: snapshot)
            let response = try await hermesClient.sendMessage(
                baseURL: hermesSettings.apiBaseURL,
                apiKey: apiKey,
                messages: [
                    HermesChatRequestMessage(role: .system, content: "只返回请求指定的 JSON，不能生成或执行设备控制。"),
                    HermesChatRequestMessage(role: .user, content: prompt),
                ],
                model: hermesSettings.hermesModel,
                stream: false
            )
            pendingLayoutSuggestion = try HomeAssistantLayoutAnalyzer.validatedSuggestion(from: response, snapshot: snapshot)
        } catch {
            errorMessage = "AI 整理失败：\(error.localizedDescription)"
        }
    }

    func applyPendingLayoutSuggestion() {
        guard let pendingLayoutSuggestion, let snapshot else { return }
        layoutSuggestion = pendingLayoutSuggestion
        settingsStore.saveLayoutSuggestion(
            pendingLayoutSuggestion,
            topologyHash: HomeAssistantLayoutAnalyzer.topologyHash(for: snapshot)
        )
        self.pendingLayoutSuggestion = nil
    }

    func discardPendingLayoutSuggestion() {
        pendingLayoutSuggestion = nil
    }

    func resetLayoutSuggestion() {
        settingsStore.clearLayoutSuggestion()
        if let snapshot = visibleSnapshot {
            layoutSuggestion = HomeAssistantLayoutAnalyzer.deterministicSuggestion(for: snapshot)
        } else {
            layoutSuggestion = HomeAssistantLayoutSuggestion()
        }
    }

    func updateRoomOrder(_ roomIDs: [String]) {
        guard let snapshot else { return }
        let currentRooms = rooms
        let validIDs = Set(currentRooms.map(\.id))
        let normalized = roomIDs.reduce(into: [String]()) { result, id in
            if validIDs.contains(id), !result.contains(id) { result.append(id) }
        }
        let missing = currentRooms.map(\.id).filter { !normalized.contains($0) }
        let updated = HomeAssistantLayoutSuggestion(
            roomOrder: normalized + missing,
            featuredEntityIDs: layoutSuggestion.featuredEntityIDs,
            aliases: layoutSuggestion.aliases,
            suggestions: layoutSuggestion.suggestions
        )
        layoutSuggestion = updated
        settingsStore.saveLayoutSuggestion(
            updated,
            topologyHash: HomeAssistantLayoutAnalyzer.topologyHash(for: snapshot)
        )
    }

    func accessories(inRoom roomID: String) -> [HomeAssistantAccessory] {
        let roomAccessories = allVisibleAccessories.filter { dashboardRoomID(for: $0) == roomID }
        let order = dashboardLayout.cardOrderByRoom[roomID] ?? []
        let accessoriesByID = Dictionary(uniqueKeysWithValues: roomAccessories.map { ($0.id, $0) })
        var ordered = order.compactMap { accessoriesByID[$0] }
        let orderedIDs = Set(ordered.map(\.id))
        let featuredOrder = Dictionary(
            uniqueKeysWithValues: layoutSuggestion.featuredEntityIDs.enumerated().map { ($1, $0) }
        )
        let missing = roomAccessories
            .filter { !orderedIDs.contains($0.id) }
            .sorted { defaultAccessoryOrder($0, $1, featuredOrder: featuredOrder) }
        ordered.append(contentsOf: missing)

        // Preserve the existing product rule that unavailable accessories stay at the bottom,
        // while retaining the user's relative order inside each availability group.
        return ordered.filter(isAccessoryAvailable) + ordered.filter { !isAccessoryAvailable($0) }
    }

    func cardSize(for accessory: HomeAssistantAccessory) -> HomeAssistantCardSize {
        dashboardLayout.cardSizes[accessory.id] ?? defaultCardSize(for: accessory)
    }

    func toggleCardSize(accessoryID: String) {
        guard let accessory = allAccessories.first(where: { $0.id == accessoryID }) else { return }
        let nextSize = cardSize(for: accessory).toggled
        let defaultSize = defaultCardSize(for: accessory)
        dashboardLayout.setSize(nextSize == defaultSize ? nil : nextSize, forCard: accessoryID)
        saveDashboardLayout()
    }

    func moveAccessory(_ sourceID: String, before targetID: String, inRoom roomID: String) {
        guard sourceID != targetID else { return }
        let roomAccessories = accessories(inRoom: roomID)
        guard roomAccessories.contains(where: { $0.id == sourceID }),
              roomAccessories.contains(where: { $0.id == targetID }) else { return }
        var cardIDs = roomAccessories.map(\.id)
        guard let sourceIndex = cardIDs.firstIndex(of: sourceID) else { return }
        cardIDs.remove(at: sourceIndex)
        guard let targetIndex = cardIDs.firstIndex(of: targetID) else { return }
        cardIDs.insert(sourceID, at: targetIndex)
        dashboardLayout.setOrder(cardIDs, forRoom: roomID)
        saveDashboardLayout()
    }

    func resetDashboardLayout() {
        dashboardLayout = HomeAssistantDashboardLayoutSettings()
        saveDashboardLayout()
    }

    func dashboardRoomID(for accessory: HomeAssistantAccessory) -> String {
        accessory.areaID ?? HomeAssistantTopologyBuilder.unassignedAreaID
    }

    func hideDevice(_ cardID: String) {
        guard allAccessories.contains(where: { $0.id == cardID }) else { return }
        hiddenCardIDs.insert(cardID)
        saveDeviceVisibility()
        normalizeSelectedRoom()
    }

    func showDevice(_ cardID: String) {
        hiddenCardIDs.remove(cardID)
        saveDeviceVisibility()
    }

    func showAllDevices() {
        hiddenCardIDs.removeAll()
        saveDeviceVisibility()
    }

    func updateDevicePresentation(
        cardID: String,
        customName: String,
        displayType: HomeAssistantDeviceDisplayType,
        systemImage: String? = nil,
        areaID: String? = nil
    ) {
        guard snapshot?.cards.contains(where: { $0.id == cardID }) == true else { return }
        devicePresentations[cardID] = HomeAssistantDevicePresentation(
            customName: customName,
            displayType: displayType,
            systemImage: systemImage,
            areaID: areaID
        )
        saveDevicePresentations()
        rebuildAccessoryProjection()
        normalizeSelectedRoom()
    }

    func updateAccessoryPresentation(
        accessoryID: String,
        customName: String,
        kind: HomeAssistantAccessoryKind,
        systemImage: String? = nil,
        areaID: String? = nil,
        bindings: [HomeAssistantRoleBinding]
    ) {
        guard let accessory = allAccessories.first(where: { $0.id == accessoryID }) else { return }
        let explicitlyBoundRoles = Set(bindings.map(\.role))
        let explicitlyUnboundRoles = HomeAssistantAccessorySchemaRegistry
            .schema(for: kind)
            .supportedRoles
            .subtracting(explicitlyBoundRoles)
        let selectedEntityIDs = Set(bindings.flatMap(\.entityIDs))
        let boundEntities = (snapshot?.entities ?? accessory.entities).filter {
            selectedEntityIDs.contains($0.entityID)
        }
        let sourceDeviceIDs = (accessory.sourceCard.entities + boundEntities)
            .compactMap(\.deviceID)
            .reduce(into: [String]()) {
            if !$0.contains($1) { $0.append($1) }
        }
        accessoryPresentations[accessoryID] = HomeAssistantAccessoryPresentation(
            id: accessoryID,
            sourceDeviceIDs: sourceDeviceIDs,
            kind: kind,
            bindings: bindings,
            explicitlyUnboundRoles: explicitlyUnboundRoles,
            autoClassification: .init(
                confidence: 1,
                source: .user,
                reasons: ["用户确认设备类型与实体角色"],
                needsReview: !bindings.contains { [.primaryControl, .power].contains($0.role) }
            ),
            customName: customName,
            customAreaID: areaID,
            customSystemImage: systemImage
        )
        saveAccessoryPresentations()
        rebuildAccessoryProjection()
        normalizeSelectedRoom()
    }

    func sourceCard(for accessory: HomeAssistantAccessory) -> HomeAssistantDeviceCard? {
        snapshot?.cards.first { $0.id == accessory.sourceCardID }
    }

    func splitCandidates(for accessory: HomeAssistantAccessory) -> [HomeAssistantEntity] {
        guard let sourceCard = sourceCard(for: accessory) else { return [] }
        return HomeAssistantAccessoryReconciler.splitCandidates(in: sourceCard)
    }

    func splitEntityIDs(for accessory: HomeAssistantAccessory) -> Set<String> {
        accessoryGrouping.splitEntityIDs(for: accessory.sourceCardID)
    }

    func updateAccessoryGrouping(
        sourceCardID: String,
        splitEntityIDs: Set<String>
    ) {
        guard let sourceCard = snapshot?.cards.first(where: { $0.id == sourceCardID }) else { return }
        let validIDs = Set(
            HomeAssistantAccessoryReconciler.splitCandidates(in: sourceCard).map(\.entityID)
        )
        accessoryGrouping.setSplitEntityIDs(
            splitEntityIDs.intersection(validIDs),
            for: sourceCardID
        )
        saveAccessoryGrouping()
        rebuildAccessoryProjection()
        normalizeSelectedRoom()
    }

    func mergeAccessory(_ accessory: HomeAssistantAccessory) {
        guard let splitEntityID = accessory.splitEntityID else { return }
        var splitEntityIDs = accessoryGrouping.splitEntityIDs(for: accessory.sourceCardID)
        splitEntityIDs.remove(splitEntityID)
        updateAccessoryGrouping(
            sourceCardID: accessory.sourceCardID,
            splitEntityIDs: splitEntityIDs
        )
    }

    func sourceAccessoryName(for accessory: HomeAssistantAccessory) -> String {
        guard let sourceCard = sourceCard(for: accessory) else { return "原设备" }
        return accessoryPresentations[sourceCard.id]?.customName
            ?? devicePresentations[sourceCard.id]?.customName
            ?? sourceCard.name
    }

    func resetDevicePresentation(cardID: String) {
        devicePresentations.removeValue(forKey: cardID)
        accessoryPresentations.removeValue(forKey: cardID)
        saveDevicePresentations()
        saveAccessoryPresentations()
        rebuildAccessoryProjection()
    }

    func roomName(for card: HomeAssistantDeviceCard) -> String {
        guard let areaID = areaID(for: card) else { return "未分配" }
        return snapshot?.rooms.first(where: { $0.id == areaID })?.name ?? "未分配"
    }

    func clearSnapshotCache() {
        cacheSaveTask?.cancel()
        cacheWritesSuspended = true
        if let instanceFingerprint {
            snapshotCacheStore.clear(instanceFingerprint: instanceFingerprint)
        }
        cacheSavedAt = nil
        if !snapshotPhase.allowsControl {
            snapshot = nil
            rebuildAccessoryProjection()
            snapshotPhase = .empty
        }
    }

    func flushSnapshotCache() {
        scheduleSnapshotCacheSave(delay: .zero)
    }

    private func monitorNetwork() {
        pathMonitor.pathUpdateHandler = { [weak self] path in
            let interface: HomeAssistantNetworkInterface
            if path.status != .satisfied {
                interface = .unavailable
            } else if path.usesInterfaceType(.wifi) {
                interface = .wifi
            } else if path.usesInterfaceType(.cellular) {
                interface = .cellular
            } else {
                interface = .other
            }

            Task { @MainActor [weak self] in
                guard let self, self.networkInterface != interface else { return }
                self.networkInterface = interface
                if interface == .unavailable {
                    self.connectionGeneration += 1
                    self.connectionTask?.cancel()
                    self.eventTask?.cancel()
                    self.connectionState = .offline
                    self.connectedCandidate = nil
                    await self.socket.disconnect()
                } else if self.isConfigured {
                    await self.reconnect()
                }
            }
        }
        pathMonitor.start(queue: monitorQueue)
    }

    private func connectUsingAvailableEndpoint() async throws {
        guard isConfigured else { throw HomeAssistantError.emptyToken }
        let candidates = await endpointCandidates()
        guard !candidates.isEmpty else {
            connectionState = .offline
            return
        }
        isLoading = true
        defer { isLoading = false }
        errorMessage = nil
        eventTask?.cancel()
        translationTask?.cancel()
        await socket.disconnect()
        connectedCandidate = nil

        var lastError: Error = HomeAssistantError.disconnected
        for candidate in candidates {
            if Task.isCancelled { throw CancellationError() }
            connectionState = .connecting(candidate.kind)
            do {
                try await restClient.checkConnection(baseURL: candidate.url, token: token)
                try await socket.connect(baseURL: candidate.url, token: token)
                connectedCandidate = candidate
                let hadExistingSnapshot = snapshot != nil
                let states = try await socket.fetchStates()
                applyFastStateSynchronization(states)
                try await loadAuthoritativeSnapshot(
                    states: states,
                    hadExistingSnapshot: hadExistingSnapshot
                )
                let eventStream = await socket.events()
                try await socket.subscribeStateChanges()
                startEventConsumption(eventStream)
                connectionState = .connected(candidate.kind)
                return
            } catch {
                if Task.isCancelled || HomeAssistantErrorClassifier.isCancellation(error) {
                    await socket.disconnect()
                    throw CancellationError()
                }
                diagnostics.record(
                    category: "home_assistant.connection",
                    name: "connection_attempt_failed",
                    operation: "connect_candidate",
                    endpoint: candidate.url,
                    error: error,
                    details: ["endpointKind": candidate.kind.rawValue]
                )
                lastError = error
                await socket.disconnect()
            }
        }
        throw lastError
    }

    private func endpointCandidates() async -> [HomeAssistantEndpointCandidate] {
        let currentSSID: String?
        if networkInterface == .wifi, !settings.internalSSIDs.isEmpty {
            currentSSID = await wifiSSIDProvider.currentSSID(requestAuthorization: false)
        } else {
            currentSSID = nil
        }
        return HomeAssistantEndpointSelector.candidates(
            settings: settings,
            interface: networkInterface,
            currentSSID: currentSSID
        )
    }

    private func loadAuthoritativeSnapshot(
        states: [HomeAssistantState],
        hadExistingSnapshot: Bool
    ) async throws {
        async let configResult = socket.fetchConfig()
        async let servicesResult = socket.fetchServices()
        async let registryResult: [HomeAssistantEntityRegistryEntry]? = try? await socket.fetchEntityRegistry()
        async let areasResult: [HomeAssistantArea]? = try? await socket.fetchAreas()
        async let devicesResult: [HomeAssistantDevice]? = try? await socket.fetchDevices()

        let fetchedConfig = try await configResult
        let fetchedServices = try await servicesResult
        let fetchedRegistry = await registryResult
        let fetchedAreas = await areasResult
        let fetchedDevices = await devicesResult
        let cachedHasPhysicalDevices = snapshot?.cards.contains(where: { !$0.isVirtual }) == true
        let cachedHasAssignedRooms = snapshot?.cards.contains(where: { $0.areaID != nil }) == true
        if hadExistingSnapshot,
           (fetchedRegistry == nil && cachedHasPhysicalDevices)
            || (fetchedDevices == nil && cachedHasPhysicalDevices)
            || (fetchedAreas == nil && cachedHasAssignedRooms) {
            diagnostics.record(
                category: "home_assistant.connection",
                name: "connection_attempt_failed",
                operation: "load_authoritative_snapshot",
                endpoint: connectedCandidate?.url,
                error: HomeAssistantError.invalidResponse,
                details: [
                    "missingRegistry": String(fetchedRegistry == nil),
                    "missingDevices": String(fetchedDevices == nil),
                    "missingAreas": String(fetchedAreas == nil),
                    "cachedHasPhysicalDevices": String(cachedHasPhysicalDevices),
                    "cachedHasAssignedRooms": String(cachedHasAssignedRooms),
                ]
            )
            throw HomeAssistantError.invalidResponse
        }

        persistLastKnownLocationName(fetchedConfig.locationName)
        config = fetchedConfig
        rawStatesByID = Self.indexedStates(states)
        services = fetchedServices
        registryEntries = fetchedRegistry ?? []
        areas = fetchedAreas ?? []
        devices = fetchedDevices ?? []
        cacheWritesSuspended = false
        rebuildSnapshot(phase: .authoritative)
        refreshTranslationCatalog()
    }

    private func persistLastKnownLocationName(_ locationName: String) {
        let normalizedName = locationName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedName.isEmpty, settings.lastKnownLocationName != normalizedName else { return }
        var updatedSettings = settings
        updatedSettings.lastKnownLocationName = normalizedName
        do {
            try settingsStore.save(updatedSettings, token: nil)
        } catch {
            return
        }
        settings = settingsStore.load()
    }

    private func observeICloudSettingsChanges() {
        NotificationCenter.default.publisher(for: .iCloudSyncedPreferencesDidChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.reloadICloudSyncedSettings()
                }
            }
            .store(in: &observers)
    }

    private func reloadICloudSyncedSettings() {
        settings = settingsStore.load()
        guard let fingerprint = instanceFingerprint else {
            hiddenCardIDs = []
            dashboardLayout = HomeAssistantDashboardLayoutSettings()
            devicePresentations = [:]
            accessoryPresentations = [:]
            accessoryGrouping = HomeAssistantAccessoryGroupingSettings()
            rebuildAccessoryProjection()
            return
        }
        hiddenCardIDs = settingsStore.loadDeviceVisibility(instanceFingerprint: fingerprint).hiddenCardIDs
        dashboardLayout = settingsStore.loadDashboardLayout(instanceFingerprint: fingerprint)
        devicePresentations = settingsStore.loadDevicePresentations(instanceFingerprint: fingerprint).devices
        accessoryPresentations = settingsStore.loadAccessoryPresentations(instanceFingerprint: fingerprint).accessories
        accessoryGrouping = settingsStore.loadAccessoryGrouping(instanceFingerprint: fingerprint)
        rebuildAccessoryProjection()
        normalizeSelectedRoom()
    }

    private func startEventConsumption(_ stream: HomeAssistantWebSocketClient.EventStream) {
        eventTask?.cancel()
        eventTask = Task { @MainActor [weak self] in
            guard let self else { return }
            for await state in stream {
                guard !Task.isCancelled else { return }
                rawStatesByID[state.entityID] = state
                pendingStateUpdates[state.entityID] = state
                scheduleStateProjection()
                pendingEntityIDs.remove(state.entityID)
            }
            guard !Task.isCancelled, isConfigured else { return }
            connectionState = .reconnecting
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            await reconnect()
        }
    }

    private func rebuildSnapshot(phase: HomeAssistantSnapshotPhase? = nil) {
        guard let config else { return }
        stateProjectionTask?.cancel()
        stateProjectionTask = nil
        pendingStateUpdates.removeAll()
        let snapshot = HomeAssistantTopologyBuilder.build(
            config: config,
            states: rawStatesByID.values.sorted { $0.entityID < $1.entityID },
            registryEntries: registryEntries,
            areas: areas,
            devices: devices,
            services: services,
            showsDiagnosticEntities: settings.showsDiagnosticEntities
        )
        self.snapshot = snapshot
        rebuildAccessoryProjection(from: snapshot)
        if let phase { snapshotPhase = phase }
        loadLayoutSuggestion(for: snapshot)
        normalizeSelectedRoom()
        if snapshotPhase.allowsControl { scheduleSnapshotCacheSave() }
    }

    private func scheduleStateProjection() {
        guard stateProjectionTask == nil else { return }
        stateProjectionTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(80))
            guard !Task.isCancelled else { return }
            guard let self else { return }
            let states = Array(pendingStateUpdates.values)
            pendingStateUpdates.removeAll()
            stateProjectionTask = nil
            applyIncrementalStateUpdates(states)
        }
    }

    private var instanceFingerprint: String? {
        HomeAssistantSnapshotCacheStore.instanceFingerprint(externalURL: settings.externalURL)
    }

    private func restoreCachedSnapshotIfNeeded() {
        guard !hasRestoredCache else { return }
        hasRestoredCache = true
        guard let instanceFingerprint else { return }
        hiddenCardIDs = settingsStore.loadDeviceVisibility(
            instanceFingerprint: instanceFingerprint
        ).hiddenCardIDs
        dashboardLayout = settingsStore.loadDashboardLayout(instanceFingerprint: instanceFingerprint)
        devicePresentations = settingsStore.loadDevicePresentations(
            instanceFingerprint: instanceFingerprint
        ).devices
        accessoryPresentations = settingsStore.loadAccessoryPresentations(
            instanceFingerprint: instanceFingerprint
        ).accessories
        accessoryGrouping = settingsStore.loadAccessoryGrouping(
            instanceFingerprint: instanceFingerprint
        )
        translationCatalog = settingsStore.loadTranslationCatalog(
            instanceFingerprint: instanceFingerprint,
            language: Self.preferredTranslationLanguage
        )
        guard let envelope = snapshotCacheStore.load(instanceFingerprint: instanceFingerprint) else { return }
        snapshot = envelope.snapshot
        rebuildAccessoryProjection(from: envelope.snapshot)
        snapshotPhase = .cached(savedAt: envelope.savedAt)
        cacheSavedAt = envelope.savedAt
        loadLayoutSuggestion(for: envelope.snapshot)
        normalizeSelectedRoom()
    }

    private func applyFastStateSynchronization(_ states: [HomeAssistantState]) {
        rawStatesByID = Self.indexedStates(states)
        guard let snapshot else { return }
        let updatedSnapshot = HomeAssistantSnapshotProjection.merging(states: states, into: snapshot)
        self.snapshot = updatedSnapshot
        rebuildAccessoryProjection(from: updatedSnapshot)
        snapshotPhase = .stateSynchronized
        normalizeSelectedRoom()
    }

    private func applyIncrementalStateUpdates(_ states: [HomeAssistantState]) {
        guard !states.isEmpty, let snapshot else { return }
        let updatedSnapshot = HomeAssistantSnapshotProjection.applying(states: states, to: snapshot)
        let updatedAccessories = HomeAssistantAccessoryReconciler.applying(states: states, to: allAccessories)
        let affectedEntityIDs = Set(states.map(\.entityID))
        var semanticStates = semanticStatesByAccessoryID
        for accessory in updatedAccessories
        where accessory.entities.contains(where: { affectedEntityIDs.contains($0.entityID) }) {
            semanticStates[accessory.id] = HomeAssistantAccessoryStateResolver.resolve(
                accessory,
                translations: translationCatalog
            )
        }
        semanticStatesByAccessoryID = semanticStates
        self.snapshot = updatedSnapshot
        allAccessories = updatedAccessories
        if snapshotPhase.allowsControl { scheduleSnapshotCacheSave() }
    }

    private func rebuildAccessoryProjection(from sourceSnapshot: HomeAssistantSnapshot? = nil) {
        guard let sourceSnapshot = sourceSnapshot ?? snapshot else {
            semanticStatesByAccessoryID = [:]
            allAccessories = []
            return
        }
        let accessories = HomeAssistantAccessoryReconciler.accessories(
            from: sourceSnapshot.cards,
            entities: sourceSnapshot.entities,
            presentations: accessoryPresentations,
            legacyPresentations: devicePresentations,
            grouping: accessoryGrouping
        )
        semanticStatesByAccessoryID = Dictionary(
            uniqueKeysWithValues: accessories.map { accessory in
                (
                    accessory.id,
                    HomeAssistantAccessoryStateResolver.resolve(
                        accessory,
                        translations: translationCatalog
                    )
                )
            }
        )
        allAccessories = accessories
    }

    private func rebuildSemanticStateProjection() {
        semanticStatesByAccessoryID = Dictionary(
            uniqueKeysWithValues: allAccessories.map { accessory in
                (
                    accessory.id,
                    HomeAssistantAccessoryStateResolver.resolve(
                        accessory,
                        translations: translationCatalog
                    )
                )
            }
        )
    }

    private func loadLayoutSuggestion(for snapshot: HomeAssistantSnapshot) {
        let hash = HomeAssistantLayoutAnalyzer.topologyHash(for: snapshot)
        if let cached = settingsStore.loadLayoutSuggestion(topologyHash: hash) {
            layoutSuggestion = cached
        } else if layoutSuggestion.roomOrder.isEmpty && layoutSuggestion.featuredEntityIDs.isEmpty {
            layoutSuggestion = HomeAssistantLayoutAnalyzer.deterministicSuggestion(
                for: HomeAssistantSnapshotProjection.visibleSnapshot(
                    from: snapshot,
                    hiddenCardIDs: hiddenCardIDs
                )
            )
        }
    }

    private func refreshTranslationCatalog() {
        translationTask?.cancel()
        let language = Self.preferredTranslationLanguage
        let fingerprint = instanceFingerprint
        translationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let catalog = await socket.fetchTranslationCatalog(language: language)
            guard !Task.isCancelled, !catalog.isEmpty, fingerprint == instanceFingerprint else { return }
            translationCatalog = catalog
            rebuildSemanticStateProjection()
            if let fingerprint {
                settingsStore.saveTranslationCatalog(catalog, instanceFingerprint: fingerprint)
            }
        }
    }

    private func saveDeviceVisibility() {
        guard let instanceFingerprint else { return }
        settingsStore.saveDeviceVisibility(
            HomeAssistantDeviceVisibilitySettings(hiddenCardIDs: hiddenCardIDs),
            instanceFingerprint: instanceFingerprint
        )
    }

    private func saveDashboardLayout() {
        guard let instanceFingerprint else { return }
        settingsStore.saveDashboardLayout(dashboardLayout, instanceFingerprint: instanceFingerprint)
    }

    private func saveDevicePresentations() {
        guard let instanceFingerprint else { return }
        settingsStore.saveDevicePresentations(
            HomeAssistantDevicePresentationSettings(devices: devicePresentations),
            instanceFingerprint: instanceFingerprint
        )
    }

    private func saveAccessoryPresentations() {
        guard let instanceFingerprint else { return }
        settingsStore.saveAccessoryPresentations(
            HomeAssistantAccessoryPresentationSettings(accessories: accessoryPresentations),
            instanceFingerprint: instanceFingerprint
        )
    }

    private func saveAccessoryGrouping() {
        guard let instanceFingerprint else { return }
        settingsStore.saveAccessoryGrouping(
            accessoryGrouping,
            instanceFingerprint: instanceFingerprint
        )
    }

    private func defaultDisplayName(for card: HomeAssistantDeviceCard) -> String {
        guard card.isVirtual, let entity = card.primaryEntity else { return card.name }
        return displayName(for: entity)
    }

    private func inferredDisplayType(for card: HomeAssistantDeviceCard) -> HomeAssistantDeviceDisplayType {
        inferredDisplayTypeIfSupported(for: card) ?? .switchDevice
    }

    private func defaultCardSize(for accessory: HomeAssistantAccessory) -> HomeAssistantCardSize {
        HomeAssistantDashboardPresentationPolicy.defaultCardSize(for: accessory.kind)
    }

    private func defaultAccessoryOrder(
        _ lhs: HomeAssistantAccessory,
        _ rhs: HomeAssistantAccessory,
        featuredOrder: [String: Int]
    ) -> Bool {
        let lhsAvailable = isAccessoryAvailable(lhs)
        let rhsAvailable = isAccessoryAvailable(rhs)
        if lhsAvailable != rhsAvailable { return lhsAvailable }
        let left = lhs.primaryControlEntity.map { featuredOrder[$0.entityID] ?? Int.max } ?? Int.max
        let right = rhs.primaryControlEntity.map { featuredOrder[$0.entityID] ?? Int.max } ?? Int.max
        if left != right { return left < right }
        return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
    }

    private func isAccessoryAvailable(_ accessory: HomeAssistantAccessory) -> Bool {
        let state = semanticState(for: accessory)
        return state.availability == .available || state.availability == .partiallyAvailable
    }

    private func needsAccessoryOrganization(_ accessory: HomeAssistantAccessory) -> Bool {
        accessory.needsReview && splitCandidates(for: accessory).count <= 1
    }

    private func inferredDisplayTypeIfSupported(
        for card: HomeAssistantDeviceCard
    ) -> HomeAssistantDeviceDisplayType? {
        let entity = card.primaryEntity
        let nameHint = "\(card.name) \(entity?.name ?? "") \(entity?.deviceClass ?? "")".lowercased()
        if nameHint.contains("空气净化") || nameHint.contains("purifier") {
            return .airPurifier
        }
        return switch entity?.domain {
        case "light": .light
        case "fan": .fan
        case "climate": .airConditioner
        case "switch", "input_boolean": .switchDevice
        default: nil
        }
    }

    private func normalizeSelectedRoom() {
        guard let selectedRoomID else { return }
        if !rooms.contains(where: { $0.id == selectedRoomID }) {
            self.selectedRoomID = nil
        }
    }

    private func resetSnapshotState() {
        stateProjectionTask?.cancel()
        stateProjectionTask = nil
        pendingStateUpdates.removeAll()
        snapshot = nil
        semanticStatesByAccessoryID = [:]
        allAccessories = []
        snapshotPhase = .empty
        cacheSavedAt = nil
        cacheWritesSuspended = false
        layoutSuggestion = HomeAssistantLayoutSuggestion()
        pendingLayoutSuggestion = nil
        dashboardLayout = HomeAssistantDashboardLayoutSettings()
        devicePresentations = [:]
        accessoryPresentations = [:]
        translationCatalog = HomeAssistantTranslationCatalog(language: Self.preferredTranslationLanguage)
        rawStatesByID = [:]
        registryEntries = []
        areas = []
        devices = []
        services = []
        config = nil
        selectedRoomID = nil
    }

    private static func indexedStates(_ states: [HomeAssistantState]) -> [String: HomeAssistantState] {
        states.reduce(into: [:]) { result, state in
            result[state.entityID] = state
        }
    }

    private static var preferredTranslationLanguage: String {
        let language = Locale.preferredLanguages.first ?? "zh-Hans"
        if language.hasPrefix("zh-Hant") || language.hasPrefix("zh-TW") || language.hasPrefix("zh-HK") {
            return "zh-Hant"
        }
        if language.hasPrefix("zh") { return "zh-Hans" }
        return language.split(separator: "-").first.map(String.init) ?? "en"
    }

    private func scheduleSnapshotCacheSave(delay: Duration = .seconds(2)) {
        guard snapshotPhase.allowsControl,
              !cacheWritesSuspended,
              let snapshot,
              let instanceFingerprint else { return }
        cacheSaveTask?.cancel()
        let store = snapshotCacheStore
        cacheSaveTask = Task { @MainActor [weak self] in
            do {
                if delay > .zero { try await Task.sleep(for: delay) }
                try Task.checkCancellation()
                try await Task.detached(priority: .utility) {
                    try store.save(snapshot: snapshot, instanceFingerprint: instanceFingerprint)
                }.value
                guard !Task.isCancelled else { return }
                self?.cacheSavedAt = .now
            } catch {
                // A failed cache write must not affect the live Home Assistant session.
            }
        }
    }

    private func handle(_ error: Error) {
        guard !Task.isCancelled, !HomeAssistantErrorClassifier.isCancellation(error) else { return }
        if error as? HomeAssistantError == .unauthorized {
            connectionState = .authenticationFailed
        } else {
            connectionState = .failed(error.localizedDescription)
        }
        errorMessage = error.localizedDescription
        connectedCandidate = nil
    }
}
