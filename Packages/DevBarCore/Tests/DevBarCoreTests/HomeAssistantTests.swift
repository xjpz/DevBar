import Foundation
import Testing
@testable import DevBarCore

@Suite("Home Assistant")
struct HomeAssistantTests {
    @Test("WebSocket ping completion ignores duplicate success")
    func webSocketPingCompletionIgnoresDuplicateSuccess() {
        let recorder = OneShotCompletionRecorder()
        let completion = HomeAssistantOneShotCompletion { error in
            recorder.record(error)
        }

        completion.complete(error: nil)
        completion.complete(error: HomeAssistantTestError.duplicate)

        #expect(recorder.errors.count == 1)
        #expect((recorder.errors.first ?? nil) == nil)
    }

    @Test("WebSocket ping completion keeps the first failure")
    func webSocketPingCompletionKeepsFirstFailure() {
        let recorder = OneShotCompletionRecorder()
        let completion = HomeAssistantOneShotCompletion { error in
            recorder.record(error)
        }

        completion.complete(error: HomeAssistantTestError.first)
        completion.complete(error: HomeAssistantTestError.duplicate)

        #expect(recorder.errors.count == 1)
        #expect((recorder.errors.first as? HomeAssistantTestError) == .first)
    }

    @Test("WebSocket ping completion is safe under concurrent callbacks")
    func webSocketPingCompletionIsSafeUnderConcurrentCallbacks() {
        let recorder = OneShotCompletionRecorder()
        let completion = HomeAssistantOneShotCompletion { error in
            recorder.record(error)
        }

        DispatchQueue.concurrentPerform(iterations: 32) { index in
            completion.complete(error: index == 0 ? nil : HomeAssistantTestError.duplicate)
        }

        #expect(recorder.errors.count == 1)
    }

    @Test("Dashboard hides sensor cards by default but keeps controllable devices")
    func dashboardDefaultPresentationHidesSensors() {
        #expect(!HomeAssistantDashboardPresentationPolicy.isShownByDefault(.sensorGroup))
        #expect(HomeAssistantDashboardPresentationPolicy.isShownByDefault(.switchDevice))
        #expect(HomeAssistantDashboardPresentationPolicy.isShownByDefault(.light))
        #expect(HomeAssistantDashboardPresentationPolicy.isShownByDefault(.airConditioner))
        #expect(HomeAssistantDashboardPresentationPolicy.defaultCardSize(for: .light) == .standard)
        #expect(HomeAssistantDashboardPresentationPolicy.defaultCardSize(for: .switchDevice) == .compact)
    }

    @Test("Dashboard visibility lets users explicitly show sensors")
    func dashboardVisibilitySupportsSensorOverride() throws {
        let sensorID = "device:sensor-room"
        let defaults = HomeAssistantDeviceVisibilitySettings()
        #expect(!HomeAssistantDashboardPresentationPolicy.isShown(.sensorGroup, cardID: sensorID, visibility: defaults))

        let explicitlyShown = HomeAssistantDeviceVisibilitySettings(shownCardIDs: [sensorID])
        #expect(HomeAssistantDashboardPresentationPolicy.isShown(
            .sensorGroup,
            cardID: sensorID,
            visibility: explicitlyShown
        ))

        let explicitlyHidden = HomeAssistantDeviceVisibilitySettings(
            hiddenCardIDs: [sensorID],
            shownCardIDs: [sensorID]
        )
        #expect(!HomeAssistantDashboardPresentationPolicy.isShown(
            .sensorGroup,
            cardID: sensorID,
            visibility: explicitlyHidden
        ))
        #expect(explicitlyHidden.shownCardIDs.isEmpty)

        let legacyData = try #require(#"{"hiddenCardIDs":["device:hidden"]}"#.data(using: .utf8))
        let legacy = try JSONDecoder().decode(HomeAssistantDeviceVisibilitySettings.self, from: legacyData)
        #expect(legacy.hiddenCardIDs == ["device:hidden"])
        #expect(legacy.shownCardIDs.isEmpty)
    }

    @Test("Cellular never returns an internal endpoint")
    func cellularSkipsInternalEndpoint() throws {
        let settings = try HomeAssistantEndpointSelector.normalizedSettings(.init(
            externalURL: "https://ha.example.com/path?secret=1",
            internalURL: "http://192.168.1.10:8123/api"
        ))

        let candidates = HomeAssistantEndpointSelector.candidates(settings: settings, interface: .cellular)

        #expect(candidates.map(\.kind) == [.externalNetwork])
        #expect(candidates.first?.url.absoluteString == "https://ha.example.com")
    }

    @Test("Wi-Fi tries internal then external")
    func wifiPrefersInternalEndpoint() throws {
        let settings = try HomeAssistantEndpointSelector.normalizedSettings(.init(
            externalURL: "https://ha.example.com",
            internalURL: "http://homeassistant.local:8123",
            internalSSIDs: ["My Home"]
        ))

        let candidates = HomeAssistantEndpointSelector.candidates(
            settings: settings,
            interface: .wifi,
            currentSSID: "My Home"
        )

        #expect(candidates.map(\.kind) == [.internalNetwork, .externalNetwork])
    }

    @Test("Wi-Fi skips internal endpoint when SSID differs or is unavailable")
    func wifiRequiresMatchingSSID() throws {
        let settings = try HomeAssistantEndpointSelector.normalizedSettings(.init(
            externalURL: "https://ha.example.com",
            internalURL: "http://homeassistant.local:8123",
            internalSSIDs: ["My Home", "My Home 5G", "Guest Home"]
        ))

        let mismatched = HomeAssistantEndpointSelector.candidates(
            settings: settings,
            interface: .wifi,
            currentSSID: "Coffee Shop"
        )
        let unavailable = HomeAssistantEndpointSelector.candidates(
            settings: settings,
            interface: .wifi,
            currentSSID: nil
        )

        #expect(mismatched.map(\.kind) == [.externalNetwork])
        #expect(unavailable.map(\.kind) == [.externalNetwork])
    }

    @Test("Legacy connection settings decode without an SSID")
    func legacySettingsDecodeWithoutSSID() throws {
        let settings = try decode(HomeAssistantConnectionSettings.self, """
        {"externalURL":"https://ha.example.com","internalURL":"http://ha.local:8123","aiAnalysisEnabled":false,"showsDiagnosticEntities":false}
        """)

        #expect(settings.internalSSIDs.isEmpty)
        #expect(settings.lastKnownLocationName.isEmpty)
    }

    @Test("Endpoint normalization preserves the last known location name")
    func normalizationPreservesLastKnownLocationName() throws {
        let settings = try HomeAssistantEndpointSelector.normalizedSettings(.init(
            externalURL: "https://ha.example.com",
            lastKnownLocationName: "  海边小屋  "
        ))

        #expect(settings.lastKnownLocationName == "海边小屋")
    }

    @Test("Legacy single SSID migrates into the SSID list")
    func legacySingleSSIDMigrates() throws {
        let settings = try decode(HomeAssistantConnectionSettings.self, """
        {"externalURL":"https://ha.example.com","internalURL":"http://ha.local:8123","internalSSID":"My Home","aiAnalysisEnabled":false,"showsDiagnosticEntities":false}
        """)

        #expect(settings.internalSSIDs == ["My Home"])
    }

    @Test("SSID list is trimmed deduplicated and limited to three")
    func normalizesSSIDList() throws {
        let settings = try HomeAssistantEndpointSelector.normalizedSettings(.init(
            externalURL: "https://ha.example.com",
            internalURL: "http://ha.local:8123",
            internalSSIDs: [" Home ", "Home", "Home 5G", "", "Home IoT", "Extra"]
        ))

        #expect(settings.internalSSIDs == ["Home", "Home 5G", "Home IoT"])
        let candidates = HomeAssistantEndpointSelector.candidates(
            settings: settings,
            interface: .wifi,
            currentSSID: "Home IoT"
        )
        #expect(candidates.map(\.kind) == [.internalNetwork, .externalNetwork])
    }

    @Test("Public endpoint requires HTTPS")
    func publicEndpointRequiresHTTPS() {
        #expect(throws: HomeAssistantError.externalURLRequiresHTTPS) {
            try HomeAssistantEndpointSelector.normalizedSettings(.init(externalURL: "http://ha.example.com"))
        }
    }

    @Test("URL session cancellation is a normal lifecycle event")
    func recognizesURLSessionCancellation() {
        #expect(HomeAssistantErrorClassifier.isCancellation(CancellationError()))
        #expect(HomeAssistantErrorClassifier.isCancellation(URLError(.cancelled)))
        #expect(!HomeAssistantErrorClassifier.isCancellation(URLError(.timedOut)))
    }

    @Test("A stale WebSocket connection cannot mutate the current connection")
    func staleWebSocketEpochIsRejected() {
        var epoch = HomeAssistantConnectionEpoch()
        let firstConnection = epoch.current
        let secondConnection = epoch.advance()

        #expect(!epoch.isCurrent(firstConnection))
        #expect(epoch.isCurrent(secondConnection))
    }

    @Test("Device snapshot cache round-trips only presentation attributes")
    func snapshotCacheRoundTripsMinimalProjection() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("HomeAssistantCacheTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = HomeAssistantSnapshotCacheStore(directoryURL: directory)
        let fingerprint = try #require(HomeAssistantSnapshotCacheStore.instanceFingerprint(externalURL: "https://HA.example.com/path"))
        let snapshot = try cacheFixtureSnapshot()

        try store.save(snapshot: snapshot, instanceFingerprint: fingerprint)
        let cached = try #require(store.load(instanceFingerprint: fingerprint))

        #expect(cached.snapshot.cards.map(\.id) == snapshot.cards.map(\.id))
        #expect(cached.snapshot.entities.first?.state.attributes["brightness"] == .number(128))
        #expect(cached.snapshot.entities.first?.state.attributes["latitude"] == nil)
        #expect(store.load(instanceFingerprint: "another-instance") == nil)
    }

    @Test("Fast state synchronization preserves topology and marks missing entities unavailable")
    func cachedStateMergePreservesTopology() throws {
        let snapshot = try cacheFixtureSnapshot()
        let updated = try decode(HomeAssistantState.self, """
        {"entity_id":"light.living","state":"off","attributes":{"brightness":0}}
        """)

        let merged = HomeAssistantSnapshotProjection.merging(states: [updated], into: snapshot)

        let livingCard = merged.cards.first { $0.id == "device-living" }
        let bedroomCard = merged.cards.first { $0.id == "device-bedroom" }
        #expect(livingCard?.name == "客厅灯")
        #expect(livingCard?.areaID == "living")
        #expect(livingCard?.primaryEntity?.state.state == "off")
        #expect(bedroomCard?.primaryEntity?.state.state == "unavailable")
    }

    @Test("Incremental state events preserve unrelated entity states and topology")
    func incrementalStateProjectionPreservesUnrelatedEntities() throws {
        let snapshot = try cacheFixtureSnapshot()
        let updated = try decode(HomeAssistantState.self, """
        {"entity_id":"light.living","state":"off","attributes":{"brightness":0}}
        """)

        let projected = HomeAssistantSnapshotProjection.applying(states: [updated], to: snapshot)

        #expect(projected.rooms == snapshot.rooms)
        #expect(projected.services == snapshot.services)
        #expect(projected.cards.map(\.id) == snapshot.cards.map(\.id))
        #expect(projected.cards.first { $0.id == "device-living" }?.primaryEntity?.state.state == "off")
        #expect(projected.cards.first { $0.id == "device-bedroom" }?.primaryEntity?.state.state == "on")
        #expect(projected.entities.first { $0.entityID == "switch.bedroom" }?.state.state == "on")
    }

    @Test("Incremental accessory refresh preserves classification and updates semantic state")
    func incrementalAccessoryRefreshPreservesSchema() throws {
        let snapshot = try cacheFixtureSnapshot()
        let original = try #require(
            HomeAssistantAccessoryReconciler.accessories(
                from: snapshot.cards,
                entities: snapshot.entities
            ).first { $0.id == "device-living" }
        )
        let updated = try decode(HomeAssistantState.self, """
        {"entity_id":"light.living","state":"off","attributes":{"brightness":0}}
        """)

        let refreshed = try #require(
            HomeAssistantAccessoryReconciler.applying(states: [updated], to: [original]).first
        )

        #expect(refreshed.id == original.id)
        #expect(refreshed.kind == original.kind)
        #expect(refreshed.name == original.name)
        #expect(refreshed.bindings == original.bindings)
        #expect(refreshed.classification == original.classification)
        #expect(refreshed.primaryControlEntity?.state.state == "off")
        #expect(HomeAssistantAccessoryStateResolver.resolve(refreshed).power == .off)
    }

    @Test("Hidden device projection filters cards rooms and summary entities together")
    func hiddenDeviceProjectionIsConsistent() throws {
        let snapshot = try cacheFixtureSnapshot()
        let hiddenID = "device-living"

        let visible = HomeAssistantSnapshotProjection.visibleSnapshot(
            from: snapshot,
            hiddenCardIDs: [hiddenID]
        )

        #expect(!visible.cards.contains(where: { $0.id == hiddenID }))
        #expect(!visible.rooms.contains(where: { $0.id == "living" }))
        #expect(!visible.entities.contains(where: { $0.entityID == "light.living" }))
    }

    @Test("Hidden device settings are isolated by Home Assistant instance")
    func hiddenDeviceSettingsAreInstanceScoped() throws {
        let suite = "HomeAssistantVisibilityTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = HomeAssistantSettingsStore(defaults: defaults)

        store.saveDeviceVisibility(
            .init(hiddenCardIDs: ["device-a"], shownCardIDs: ["sensor-a"]),
            instanceFingerprint: "instance-a"
        )

        #expect(store.loadDeviceVisibility(instanceFingerprint: "instance-a").hiddenCardIDs == ["device-a"])
        #expect(store.loadDeviceVisibility(instanceFingerprint: "instance-a").shownCardIDs == ["sensor-a"])
        #expect(store.loadDeviceVisibility(instanceFingerprint: "instance-b").hiddenCardIDs.isEmpty)
        #expect(store.loadDeviceVisibility(instanceFingerprint: "instance-b").shownCardIDs.isEmpty)
    }

    @Test("Dashboard card size and room order persist per Home Assistant instance")
    func dashboardLayoutIsNormalizedAndInstanceScoped() throws {
        let suite = "HomeAssistantDashboardLayoutTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = HomeAssistantSettingsStore(defaults: defaults)
        var layout = HomeAssistantDashboardLayoutSettings(
            cardOrderByRoom: ["living": ["device-b", "device-a", "device-b", ""]],
            cardSizes: ["device-a": .standard]
        )
        layout.setSize(.compact, forCard: "device-b")

        store.saveDashboardLayout(layout, instanceFingerprint: "instance-a")

        let restored = store.loadDashboardLayout(instanceFingerprint: "instance-a")
        #expect(restored.cardOrderByRoom["living"] == ["device-b", "device-a"])
        #expect(restored.cardSizes == ["device-a": .standard, "device-b": .compact])
        #expect(store.loadDashboardLayout(instanceFingerprint: "instance-b").cardOrderByRoom.isEmpty)
    }

    @Test("Changing an accessory type preserves its resolved dashboard card size")
    func accessoryTypeChangePreservesResolvedCardSize() {
        var layout = HomeAssistantDashboardLayoutSettings()
        let cardID = "switch-device"
        let currentSize = layout.cardSizes[cardID]
            ?? HomeAssistantDashboardPresentationPolicy.defaultCardSize(for: .switchDevice)

        layout.preserveResolvedSize(currentSize, forCard: cardID)

        let sizeAfterChangingToLight = layout.cardSizes[cardID]
            ?? HomeAssistantDashboardPresentationPolicy.defaultCardSize(for: .light)
        #expect(currentSize == .compact)
        #expect(sizeAfterChangingToLight == .compact)

        layout.setSize(.standard, forCard: cardID)
        layout.preserveResolvedSize(.compact, forCard: cardID)
        #expect(layout.cardSizes[cardID] == .standard)
    }

    @Test("Device display types use the approved SF Symbols")
    func deviceDisplayTypesUseSFSymbols() {
        #expect(HomeAssistantDeviceDisplayType.allCases.map(\.rawValue) == [
            "switch", "light", "fan", "air.purifier", "air.conditioner",
        ])
        #expect(HomeAssistantDeviceDisplayType.airPurifier.systemImage == "air.purifier.fill")
        #expect(HomeAssistantDeviceDisplayType.airConditioner.systemImage == "air.conditioner.horizontal.fill")
        #expect(HomeAssistantDeviceDisplayType.switchDevice.systemImages.contains("desktopcomputer"))
        for type in HomeAssistantDeviceDisplayType.allCases {
            #expect(type.systemImages.count > 1)
            #expect(type.systemImages.first == type.systemImage)
            #expect(Set(type.systemImages).count == type.systemImages.count)
        }
    }

    @Test("Device name and type customizations are normalized and instance scoped")
    func devicePresentationsAreInstanceScoped() throws {
        let suite = "HomeAssistantPresentationTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = HomeAssistantSettingsStore(defaults: defaults)
        let presentation = HomeAssistantDevicePresentation(
            customName: "  客厅空气净化器  ",
            displayType: .airPurifier,
            systemImage: "leaf.fill",
            areaID: " dining-room "
        )

        store.saveDevicePresentations(
            .init(devices: ["device-a": presentation]),
            instanceFingerprint: "instance-a"
        )

        #expect(store.loadDevicePresentations(instanceFingerprint: "instance-a").devices["device-a"]?.customName == "客厅空气净化器")
        #expect(store.loadDevicePresentations(instanceFingerprint: "instance-a").devices["device-a"]?.displayType == .airPurifier)
        #expect(store.loadDevicePresentations(instanceFingerprint: "instance-a").devices["device-a"]?.systemImage == "leaf.fill")
        #expect(store.loadDevicePresentations(instanceFingerprint: "instance-a").devices["device-a"]?.customAreaID == "dining-room")
        #expect(store.loadDevicePresentations(instanceFingerprint: "instance-b").devices.isEmpty)

        let invalidIcon = HomeAssistantDevicePresentation(
            customName: nil,
            displayType: .fan,
            systemImage: "externaldrive.fill"
        )
        #expect(invalidIcon.systemImage == HomeAssistantDeviceDisplayType.fan.systemImage)

        let legacyPresentation = try decode(
            HomeAssistantDevicePresentation.self,
            #"{"customName":"旧灯具","displayType":"light"}"#
        )
        #expect(legacyPresentation.systemImage == HomeAssistantDeviceDisplayType.light.systemImage)
    }

    @Test("REST service lists accept array representation")
    func restServiceArrayCompatibility() throws {
        let service = try decode(HomeAssistantService.self, #"{"domain":"light","services":["turn_on","turn_off"]}"#)
        #expect(Set(service.services.keys) == ["turn_on", "turn_off"])
    }

    @Test("Entity area overrides device area")
    func entityAreaOverridesDeviceArea() throws {
        let config = try decode(HomeAssistantConfig.self, #"{"location_name":"Home"}"#)
        let state = try decode(HomeAssistantState.self, """
        {"entity_id":"light.ceiling","state":"on","attributes":{"friendly_name":"Ceiling"}}
        """)
        let areaKitchen = try decode(HomeAssistantArea.self, #"{"area_id":"kitchen","name":"Kitchen"}"#)
        let areaBedroom = try decode(HomeAssistantArea.self, #"{"area_id":"bedroom","name":"Bedroom"}"#)
        let device = try decode(HomeAssistantDevice.self, #"{"id":"device-1","name":"Lamp","area_id":"bedroom"}"#)
        let services = [HomeAssistantService(domain: "light", services: ["turn_on": .object([:]), "turn_off": .object([:])])]

        let snapshot = HomeAssistantTopologyBuilder.build(
            config: config,
            states: [state],
            registryEntries: [.init(entityID: state.entityID, areaID: "kitchen", deviceID: device.id)],
            areas: [areaKitchen, areaBedroom],
            devices: [device],
            services: services
        )

        #expect(snapshot.entities.first?.areaID == "kitchen")
        #expect(snapshot.cards.first?.name == "Lamp")
        #expect(snapshot.rooms.map(\.id) == ["kitchen"])
    }

    @Test("Hidden and diagnostic entities are filtered")
    func filtersHiddenAndDiagnostic() throws {
        let config = try decode(HomeAssistantConfig.self, #"{"location_name":"Home"}"#)
        let states = try decode([HomeAssistantState].self, """
        [
          {"entity_id":"sensor.visible","state":"20","attributes":{}},
          {"entity_id":"sensor.hidden","state":"1","attributes":{}},
          {"entity_id":"sensor.diagnostic","state":"2","attributes":{}}
        ]
        """)
        let registry: [HomeAssistantEntityRegistryEntry] = [
            .init(entityID: "sensor.visible"),
            .init(entityID: "sensor.hidden", isHidden: true),
            .init(entityID: "sensor.diagnostic", entityCategory: "diagnostic"),
        ]

        let snapshot = HomeAssistantTopologyBuilder.build(
            config: config,
            states: states,
            registryEntries: registry,
            areas: [],
            devices: [],
            services: []
        )

        #expect(snapshot.entities.map(\.entityID) == ["sensor.visible"])
    }

    @Test("One physical device produces one card with controls and sensors")
    func groupsEntitiesByPhysicalDevice() throws {
        let config = try decode(HomeAssistantConfig.self, #"{"location_name":"Home"}"#)
        let states = try decode([HomeAssistantState].self, """
        [
          {"entity_id":"switch.desk_socket","state":"on","attributes":{"friendly_name":"Desk Socket"}},
          {"entity_id":"sensor.desk_power","state":"42","attributes":{"device_class":"power","unit_of_measurement":"W"}},
          {"entity_id":"sensor.desk_energy","state":"3.5","attributes":{"device_class":"energy","unit_of_measurement":"kWh"}}
        ]
        """)
        let device = try decode(HomeAssistantDevice.self, #"{"id":"desk-device","name_by_user":"Desk Plug","area_id":"office"}"#)
        let registry = states.map {
            HomeAssistantEntityRegistryEntry(entityID: $0.entityID, deviceID: device.id)
        }

        let snapshot = HomeAssistantTopologyBuilder.build(
            config: config,
            states: states,
            registryEntries: registry,
            areas: [],
            devices: [device],
            services: []
        )

        let card = try #require(snapshot.cards.first)
        #expect(snapshot.cards.count == 1)
        #expect(card.name == "Desk Plug")
        #expect(card.entities.count == 3)
        #expect(card.controllableEntities.map(\.entityID) == ["switch.desk_socket"])
        #expect(card.sensorCount == 2)
        #expect(card.isActive)
        #expect(card.primaryEntityID == "switch.desk_socket")
    }

    @Test("Device power remains off when fan and indicator child entities are on")
    func semanticStateUsesExplicitPowerOwner() throws {
        let config = try decode(HomeAssistantConfig.self, #"{"location_name":"Home"}"#)
        let states = try decode([HomeAssistantState].self, """
        [
          {"entity_id":"switch.purifier_device_power","state":"off","attributes":{"friendly_name":"净化器 总开关"}},
          {"entity_id":"fan.purifier_fan","state":"on","attributes":{"friendly_name":"净化器 风扇"}},
          {"entity_id":"switch.purifier_indicator","state":"on","attributes":{"friendly_name":"净化器 指示灯"}}
        ]
        """)
        let device = try decode(HomeAssistantDevice.self, #"{"id":"purifier-device","name":"客厅空气净化器"}"#)
        let snapshot = HomeAssistantTopologyBuilder.build(
            config: config,
            states: states,
            registryEntries: states.map { .init(entityID: $0.entityID, deviceID: device.id) },
            areas: [],
            devices: [device],
            services: []
        )

        let accessory = try #require(
            HomeAssistantAccessoryReconciler.accessories(
                from: snapshot.cards,
                entities: snapshot.entities
            ).first
        )
        let semanticState = HomeAssistantAccessoryStateResolver.resolve(accessory)

        #expect(accessory.kind == .airPurifier)
        #expect(accessory.powerEntity?.entityID == "switch.purifier_device_power")
        #expect(accessory.primaryControlEntity?.entityID == "fan.purifier_fan")
        #expect(semanticState.power == .off)
        #expect(semanticState.primaryText == "已关闭")
        #expect(semanticState.secondaryText?.contains("运行中") == true)
        #expect(!semanticState.isCountedAsOn)
    }

    @Test("Air conditioner semantic state exposes the current indoor temperature")
    func airConditionerSemanticStateExposesCurrentTemperature() throws {
        let climate = try entity(
            #"{"entity_id":"climate.bedroom","state":"cool","attributes":{"friendly_name":"主卧空调","current_temperature":26.5,"temperature":23}}"#,
            deviceID: "bedroom-ac"
        )
        let card = HomeAssistantDeviceCard(
            id: "bedroom-ac",
            name: "主卧空调",
            areaID: "bedroom",
            primaryEntityID: climate.entityID,
            entities: [climate],
            hasMultiplePrimaryControls: false
        )
        let presentation = HomeAssistantAccessoryPresentation(
            id: card.id,
            sourceDeviceIDs: ["bedroom-ac"],
            kind: .airConditioner,
            bindings: [.init(role: .primaryControl, entityIDs: [climate.entityID])]
        )
        let accessory = try #require(HomeAssistantAccessoryReconciler.accessories(
            from: [card],
            entities: [climate],
            presentations: [card.id: presentation]
        ).first)

        let semanticState = HomeAssistantAccessoryStateResolver.resolve(accessory)

        #expect(semanticState.currentTemperature == 26.5)
        #expect(HomeAssistantDashboardPresentationPolicy.defaultCardSize(for: .airConditioner) == .standard)
    }

    @Test("Multiple controls remain one physical accessory by default")
    func multiplePrimaryControlsStayMergedByDefault() throws {
        let snapshot = try multipleSwitchSnapshot()
        let accessories = HomeAssistantAccessoryReconciler.accessories(from: snapshot.cards)

        let accessory = try #require(accessories.first)
        let semanticState = HomeAssistantAccessoryStateResolver.resolve(accessory)
        #expect(accessories.count == 1)
        #expect(accessory.id == "wall-device")
        #expect(accessory.sourceCardID == "wall-device")
        #expect(accessory.splitEntityID == nil)
        #expect(accessory.name == "双路开关")
        #expect(accessory.needsReview)
        #expect(accessory.quickControlEntity == nil)
        #expect(semanticState.primaryText == "1 个开启")
        #expect(semanticState.isCountedAsOn)
    }

    @Test("Only explicitly selected controls become separate accessories")
    func explicitGroupingSplitsAndMergesControls() throws {
        let snapshot = try multipleSwitchSnapshot()
        var grouping = HomeAssistantAccessoryGroupingSettings()
        grouping.setSplitEntityIDs(["switch.wall_right"], for: "wall-device")
        let mergedPresentation = HomeAssistantAccessoryPresentation(
            id: "wall-device",
            sourceDeviceIDs: ["wall-device"],
            kind: .switchDevice,
            bindings: [
                .init(role: .primaryControl, entityIDs: ["switch.wall_left"]),
                .init(role: .childControl, entityIDs: ["switch.wall_right"]),
            ]
        )

        let partiallySplit = HomeAssistantAccessoryReconciler.accessories(
            from: snapshot.cards,
            entities: snapshot.entities,
            presentations: ["wall-device": mergedPresentation],
            grouping: grouping
        )
        let mergedBase = try #require(partiallySplit.first { !$0.isSplitAccessory })
        let splitRight = try #require(partiallySplit.first { $0.splitEntityID == "switch.wall_right" })
        #expect(partiallySplit.count == 2)
        #expect(mergedBase.id == "wall-device")
        #expect(mergedBase.entities.map(\.entityID) == ["switch.wall_left"])
        #expect(!mergedBase.boundEntityIDs.contains("switch.wall_right"))
        #expect(splitRight.id == "wall-device::switch.wall_right")
        #expect(splitRight.sourceCardID == "wall-device")
        #expect(splitRight.quickControlEntity?.entityID == "switch.wall_right")

        grouping.setSplitEntityIDs(
            ["switch.wall_left", "switch.wall_right"],
            for: "wall-device"
        )
        let fullySplit = HomeAssistantAccessoryReconciler.accessories(
            from: snapshot.cards,
            grouping: grouping
        )
        #expect(fullySplit.count == 2)
        #expect(fullySplit.allSatisfy { $0.isSplitAccessory })
        #expect(Set(fullySplit.compactMap(\.splitEntityID)) == [
            "switch.wall_left", "switch.wall_right",
        ])
        #expect(fullySplit.allSatisfy { !$0.needsReview && $0.quickControlEntity != nil })
    }

    @Test("Configuration switches are not offered as split accessories")
    func groupingFiltersConfigurationHelpers() throws {
        let channel = try entity(
            #"{"entity_id":"switch.wall_channel_1","state":"on","attributes":{"friendly_name":"开关 1"}}"#,
            deviceID: "wall-device"
        )
        let memory = try entity(
            #"{"entity_id":"switch.wall_power_on_behavior","state":"on","attributes":{"friendly_name":"断电记忆"}}"#,
            deviceID: "wall-device"
        )
        let parameter = try entity(
            #"{"entity_id":"switch.wall_custom_parameter","state":"off","attributes":{"friendly_name":"自定义参数"}}"#,
            deviceID: "wall-device"
        )
        let card = HomeAssistantDeviceCard(
            id: "wall-device",
            name: "墙壁开关",
            areaID: "living",
            primaryEntityID: channel.entityID,
            entities: [channel, memory, parameter],
            hasMultiplePrimaryControls: true
        )

        #expect(HomeAssistantAccessoryReconciler.splitCandidates(in: card).map(\.entityID) == [
            "switch.wall_channel_1",
        ])

        let grouping = HomeAssistantAccessoryGroupingSettings(
            splitEntityIDsBySourceCardID: [
                "wall-device": [memory.entityID, parameter.entityID],
            ]
        )
        let accessories = HomeAssistantAccessoryReconciler.accessories(
            from: [card],
            grouping: grouping
        )
        #expect(accessories.count == 1)
        #expect(accessories.first?.id == "wall-device")
    }

    @Test("Multi-outlet control projection keeps the master and exposes every child control")
    func multiOutletControlProjection() throws {
        let master = try entity(
            #"{"entity_id":"switch.strip_master","state":"on","attributes":{"friendly_name":"总控"}}"#,
            deviceID: "smart-strip"
        )
        let s1 = try entity(
            #"{"entity_id":"switch.strip_s1","state":"on","attributes":{"friendly_name":"排插 S1"}}"#,
            deviceID: "smart-strip"
        )
        let s2 = try entity(
            #"{"entity_id":"switch.strip_s2","state":"on","attributes":{"friendly_name":"排插 S2"}}"#,
            deviceID: "smart-strip"
        )
        let s3 = try entity(
            #"{"entity_id":"switch.strip_s3","state":"off","attributes":{"friendly_name":"排插 S3"}}"#,
            deviceID: "smart-strip"
        )
        let indicator = try entity(
            #"{"entity_id":"switch.strip_indicator","state":"off","attributes":{"friendly_name":"指示灯"}}"#,
            deviceID: "smart-strip"
        )
        let sourceCard = HomeAssistantDeviceCard(
            id: "smart-strip",
            name: "智能排插",
            areaID: "living",
            primaryEntityID: s1.entityID,
            entities: [master, s1, s2, s3, indicator],
            hasMultiplePrimaryControls: true
        )
        let accessory = HomeAssistantAccessory(
            id: sourceCard.id,
            sourceCard: sourceCard,
            kind: .switchDevice,
            name: sourceCard.name,
            areaID: sourceCard.areaID,
            systemImage: "powerplug.fill",
            bindings: [
                .init(role: .power, entityIDs: [master.entityID]),
                .init(role: .primaryControl, entityIDs: [s1.entityID]),
                .init(role: .childControl, entityIDs: [s2.entityID, s3.entityID, s2.entityID]),
                .init(role: .indicator, entityIDs: [indicator.entityID]),
            ],
            classification: .init(
                confidence: 1,
                source: .user,
                reasons: ["用户确认多路插座"],
                needsReview: false
            ),
            isUserConfigured: true
        )

        let projection = HomeAssistantAccessoryControlProjection(accessory: accessory)

        #expect(projection.masterEntity?.entityID == master.entityID)
        #expect(projection.childEntities.map(\.entityID) == [
            s1.entityID, s2.entityID, s3.entityID, indicator.entityID,
        ])
        #expect(projection.usesChildControlGrid)
    }

    @Test("Air conditioner control projection prefers climate over a bound power switch")
    func airConditionerControlProjectionUsesClimate() throws {
        let climate = try entity(
            #"{"entity_id":"climate.bedroom","state":"cool","attributes":{"friendly_name":"主卧空调","temperature":24}}"#,
            deviceID: "bedroom-ac"
        )
        let power = try entity(
            #"{"entity_id":"switch.bedroom_ac_power","state":"on","attributes":{"friendly_name":"空调电源"}}"#,
            deviceID: "bedroom-ac"
        )
        let sourceCard = HomeAssistantDeviceCard(
            id: "bedroom-ac",
            name: "主卧空调",
            areaID: "bedroom",
            primaryEntityID: climate.entityID,
            entities: [climate, power],
            hasMultiplePrimaryControls: false
        )
        let accessory = HomeAssistantAccessory(
            id: sourceCard.id,
            sourceCard: sourceCard,
            kind: .airConditioner,
            name: sourceCard.name,
            areaID: sourceCard.areaID,
            systemImage: "air.conditioner.horizontal.fill",
            bindings: [
                .init(role: .primaryControl, entityIDs: [climate.entityID]),
                .init(role: .power, entityIDs: [power.entityID]),
            ],
            classification: .init(
                confidence: 1,
                source: .user,
                reasons: ["用户确认空调实体"],
                needsReview: false
            ),
            isUserConfigured: true
        )

        let projection = HomeAssistantAccessoryControlProjection(accessory: accessory)

        #expect(projection.masterEntity?.entityID == climate.entityID)
        #expect(accessory.quickControlEntity?.entityID == power.entityID)
    }

    @Test("State formatter translates domain and binary sensor semantics")
    func stateFormatterUsesDomainAndDeviceClass() throws {
        let switchEntity = try entity(#"{"entity_id":"switch.socket","state":"on","attributes":{"friendly_name":"插座"}}"#)
        let lightEntity = try entity(#"{"entity_id":"light.ceiling","state":"off","attributes":{"friendly_name":"顶灯"}}"#)
        let doorEntity = try entity(#"{"entity_id":"binary_sensor.door","state":"on","attributes":{"device_class":"door"}}"#)
        let motionEntity = try entity(#"{"entity_id":"binary_sensor.motion","state":"off","attributes":{"device_class":"motion"}}"#)
        let problemEntity = try entity(#"{"entity_id":"binary_sensor.problem","state":"on","attributes":{"device_class":"problem"}}"#)

        #expect(HomeAssistantStateFormatter.stateText(for: switchEntity) == "已开启")
        #expect(HomeAssistantStateFormatter.stateText(for: lightEntity) == "已关闭")
        #expect(HomeAssistantStateFormatter.stateText(for: doorEntity) == "已打开")
        #expect(HomeAssistantStateFormatter.stateText(for: motionEntity) == "未检测到活动")
        #expect(HomeAssistantStateFormatter.stateText(for: problemEntity) == "存在异常")
        #expect(HomeAssistantStateFormatter.translatedAttributeState("fan_only", key: "hvac_modes") == "送风")
        #expect(HomeAssistantStateFormatter.readableFallback("custom_quiet_mode") == "custom quiet mode")
    }

    @Test("Home Assistant translation resources enhance custom states and remain instance scoped")
    func customTranslationCatalogEnhancesFormatter() throws {
        let moon = try entity(
            #"{"entity_id":"sensor.moon_phase","state":"full_moon","attributes":{"friendly_name":"月相"}}"#,
            platform: "moon",
            translationKey: "phase"
        )
        let catalog = HomeAssistantTranslationCatalog(
            language: "zh-Hans",
            resources: [
                "component.moon.entity.sensor.phase.state.full_moon": "满月",
            ]
        )
        #expect(HomeAssistantStateFormatter.stateText(for: moon, translations: catalog) == "满月")

        let suite = "HomeAssistantTranslationTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = HomeAssistantSettingsStore(defaults: defaults)
        store.saveTranslationCatalog(catalog, instanceFingerprint: "instance-a")

        #expect(store.loadTranslationCatalog(instanceFingerprint: "instance-a", language: "zh-Hans") == catalog)
        #expect(store.loadTranslationCatalog(instanceFingerprint: "instance-a", language: "en").isEmpty)
        #expect(store.loadTranslationCatalog(instanceFingerprint: "instance-b", language: "zh-Hans").isEmpty)
    }

    @Test("V1 presentation migrates into instance-scoped V2 accessory settings")
    func accessoryPresentationMigrationAndPersistence() throws {
        let suite = "HomeAssistantAccessoryPresentationTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = HomeAssistantSettingsStore(defaults: defaults)
        let legacy = HomeAssistantDevicePresentation(
            customName: "  主灯  ",
            displayType: .light,
            systemImage: "light.recessed",
            areaID: " dining "
        )
        let presentation = HomeAssistantAccessoryPresentation(
            id: "device-light",
            sourceDeviceIDs: ["device-light"],
            legacy: legacy,
            bindings: [.init(role: .primaryControl, entityIDs: ["light.main"])]
        )

        store.saveAccessoryPresentations(
            .init(accessories: [presentation.id: presentation]),
            instanceFingerprint: "instance-a"
        )

        let restored = store.loadAccessoryPresentations(instanceFingerprint: "instance-a")
        #expect(restored.schemaVersion == 2)
        #expect(restored.accessories[presentation.id]?.customName == "主灯")
        #expect(restored.accessories[presentation.id]?.kind == .light)
        #expect(restored.accessories[presentation.id]?.customAreaID == "dining")
        #expect(restored.accessories[presentation.id]?.entityIDs(for: .primaryControl) == ["light.main"])
        #expect(store.loadAccessoryPresentations(instanceFingerprint: "instance-b").accessories.isEmpty)
    }

    @Test("Manual accessory grouping is normalized and instance scoped")
    func accessoryGroupingPersistence() throws {
        let suite = "HomeAssistantAccessoryGroupingTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = HomeAssistantSettingsStore(defaults: defaults)
        let grouping = HomeAssistantAccessoryGroupingSettings(
            splitEntityIDsBySourceCardID: [
                " wall-device ": [
                    " switch.wall_right ", "switch.wall_right", "", "switch.wall_left",
                ],
            ]
        )

        store.saveAccessoryGrouping(grouping, instanceFingerprint: "instance-a")

        let restored = store.loadAccessoryGrouping(instanceFingerprint: "instance-a")
        #expect(restored.splitEntityIDs(for: "wall-device") == [
            "switch.wall_left", "switch.wall_right",
        ])
        #expect(store.loadAccessoryGrouping(
            instanceFingerprint: "instance-b"
        ).splitEntityIDsBySourceCardID.isEmpty)
    }

    @Test("Cross-device auxiliary bindings survive reconciliation and missing bindings require review")
    func reconcilesCrossDeviceAuxiliaryBindings() throws {
        let control = try entity(#"{"entity_id":"climate.living","state":"off","attributes":{"friendly_name":"客厅空调"}}"#, deviceID: "ac-device")
        let temperature = try entity(#"{"entity_id":"sensor.living_temperature","state":"25.5","attributes":{"device_class":"temperature","unit_of_measurement":"°C"}}"#, deviceID: "sensor-device")
        let card = HomeAssistantDeviceCard(
            id: "ac-device",
            name: "客厅空调",
            areaID: "living",
            primaryEntityID: control.entityID,
            entities: [control],
            hasMultiplePrimaryControls: false
        )
        let presentation = HomeAssistantAccessoryPresentation(
            id: card.id,
            sourceDeviceIDs: ["ac-device", "sensor-device"],
            kind: .airConditioner,
            bindings: [
                .init(role: .primaryControl, entityIDs: [control.entityID]),
                .init(role: .temperature, entityIDs: [temperature.entityID]),
            ]
        )

        let reconciled = try #require(HomeAssistantAccessoryReconciler.accessories(
            from: [card],
            entities: [control, temperature],
            presentations: [card.id: presentation]
        ).first)
        #expect(reconciled.entities(for: .temperature).first?.entityID == temperature.entityID)
        #expect(!reconciled.needsReview)

        let missing = try #require(HomeAssistantAccessoryReconciler.accessories(
            from: [card],
            entities: [control],
            presentations: [card.id: presentation]
        ).first)
        #expect(missing.needsReview)
        #expect(missing.classification.reasons.contains { $0.contains(temperature.entityID) })
    }

    @Test("Explicitly unbound auxiliary roles remain unbound after reconciliation and persistence")
    func explicitlyUnboundAuxiliaryRolesRemainUnbound() throws {
        let power = try entity(
            #"{"entity_id":"switch.purifier","state":"on","attributes":{"friendly_name":"净化器"}}"#,
            deviceID: "purifier-device"
        )
        let temperature = try entity(
            #"{"entity_id":"sensor.purifier_temperature","state":"25.5","attributes":{"friendly_name":"温度","device_class":"temperature","unit_of_measurement":"°C"}}"#,
            deviceID: "purifier-device"
        )
        let card = HomeAssistantDeviceCard(
            id: "purifier-device",
            name: "净化器",
            areaID: "living",
            primaryEntityID: power.entityID,
            entities: [power, temperature],
            hasMultiplePrimaryControls: false
        )
        let presentation = HomeAssistantAccessoryPresentation(
            id: card.id,
            sourceDeviceIDs: ["purifier-device"],
            kind: .airPurifier,
            bindings: [.init(role: .primaryControl, entityIDs: [power.entityID])],
            explicitlyUnboundRoles: [.temperature]
        )

        let suite = "HomeAssistantExplicitlyUnboundTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = HomeAssistantSettingsStore(defaults: defaults)
        store.saveAccessoryPresentations(
            .init(accessories: [presentation.id: presentation]),
            instanceFingerprint: "instance-a"
        )
        let restored = try #require(
            store.loadAccessoryPresentations(instanceFingerprint: "instance-a")
                .accessories[presentation.id]
        )
        let accessory = try #require(HomeAssistantAccessoryReconciler.accessories(
            from: [card],
            entities: [power, temperature],
            presentations: [card.id: restored]
        ).first)

        #expect(restored.explicitlyUnboundRoles == [.temperature])
        #expect(accessory.entityIDs(for: .temperature).isEmpty)
        #expect(accessory.entityIDs(for: .primaryControl) == [power.entityID])
    }

    @Test("Sensor accessory preserves a manually selected contact entity as primary")
    func sensorAccessoryPreservesSelectedContactPrimary() throws {
        let battery = try entity(
            #"{"entity_id":"sensor.door_battery","state":"100","attributes":{"friendly_name":"电量","device_class":"battery","unit_of_measurement":"%"}}"#,
            deviceID: "door-device"
        )
        let contact = try entity(
            #"{"entity_id":"binary_sensor.door_contact","state":"off","attributes":{"friendly_name":"门窗传感器 接触状态","device_class":"door"}}"#,
            deviceID: "door-device"
        )
        let card = HomeAssistantDeviceCard(
            id: "door-device",
            name: "门窗传感器",
            areaID: "living",
            primaryEntityID: battery.entityID,
            entities: [battery, contact],
            hasMultiplePrimaryControls: false
        )
        let presentation = HomeAssistantAccessoryPresentation(
            id: card.id,
            sourceDeviceIDs: ["door-device"],
            kind: .sensorGroup,
            bindings: [
                .init(role: .primaryControl, entityIDs: [contact.entityID]),
            ]
        )

        let reconciled = try #require(HomeAssistantAccessoryReconciler.accessories(
            from: [card],
            presentations: [card.id: presentation]
        ).first)

        #expect(reconciled.primaryControlEntity?.entityID == contact.entityID)
        #expect(!reconciled.needsReview)
    }

    @Test("Standalone read-only entities stay out of device cards")
    func suppressesStandaloneReadOnlyCards() throws {
        let config = try decode(HomeAssistantConfig.self, #"{"location_name":"Home"}"#)
        let states = try decode([HomeAssistantState].self, """
        [
          {"entity_id":"sensor.outdoor_temperature","state":"26","attributes":{}},
          {"entity_id":"light.virtual_lamp","state":"off","attributes":{}}
        ]
        """)

        let snapshot = HomeAssistantTopologyBuilder.build(
            config: config,
            states: states,
            registryEntries: [],
            areas: [],
            devices: [],
            services: []
        )

        #expect(snapshot.entities.count == 2)
        #expect(snapshot.cards.map(\.primaryEntityID) == ["light.virtual_lamp"])
        #expect(snapshot.cards.first?.primaryEntity?.availableServices.contains("turn_on") == true)
    }

    @Test("Primary device controls suppress unclassified configuration helpers")
    func filtersUnclassifiedDeviceHelpers() throws {
        let config = try decode(HomeAssistantConfig.self, #"{"location_name":"Home"}"#)
        let states = try decode([HomeAssistantState].self, """
        [
          {"entity_id":"light.yeelight_strip","state":"off","attributes":{"friendly_name":"灯光"}},
          {"entity_id":"button.yeelight_toggle","state":"unknown","attributes":{"friendly_name":"灯光 开关状态切换"}},
          {"entity_id":"switch.yeelight_flex_switch","state":"off","attributes":{"friendly_name":"灯光 滚动开关"}},
          {"entity_id":"select.yeelight_factory_reset","state":"unknown","attributes":{"friendly_name":"默认状态 参数重置"}},
          {"entity_id":"select.yeelight_dimming","state":"Gradient","attributes":{"friendly_name":"默认状态 灯光变化"}}
        ]
        """)
        let device = try decode(HomeAssistantDevice.self, #"{"id":"strip-device","name":"客厅灯带"}"#)
        let registry = states.map {
            HomeAssistantEntityRegistryEntry(entityID: $0.entityID, deviceID: device.id)
        }

        let snapshot = HomeAssistantTopologyBuilder.build(
            config: config,
            states: states,
            registryEntries: registry,
            areas: [],
            devices: [device],
            services: []
        )

        let card = try #require(snapshot.cards.first)
        #expect(card.entities.map(\.entityID) == ["light.yeelight_strip"])
        #expect(card.controllableEntities.count == 1)
        #expect(card.isAvailable)

        let suggestion = try HomeAssistantLayoutAnalyzer.validatedSuggestion(
            from: #"{"roomOrder":[],"featuredEntityIDs":["button.yeelight_toggle","light.yeelight_strip"],"aliases":{"button.yeelight_toggle":"切换","light.yeelight_strip":"灯带"},"suggestions":[]}"#,
            snapshot: snapshot
        )
        #expect(suggestion.featuredEntityIDs == ["light.yeelight_strip"])
        #expect(suggestion.aliases == ["light.yeelight_strip": "灯带"])
    }

    @Test("Available equivalent light becomes the primary device control")
    func availableEquivalentLightBecomesPrimary() throws {
        let unavailableID = "light.lemesh_cn_1099659273_wy0c14_s_2"
        let availableID = "light.lemesh_cn_1099659273_wy0c14_s_2_light"
        let config = try decode(HomeAssistantConfig.self, #"{"location_name":"Home"}"#)
        let states = try decode([HomeAssistantState].self, """
        [
          {"entity_id":"\(unavailableID)","state":"unavailable","attributes":{"friendly_name":"灯光"}},
          {"entity_id":"\(availableID)","state":"off","attributes":{"friendly_name":"灯光"}}
        ]
        """)
        let device = try decode(
            HomeAssistantDevice.self,
            #"{"id":"ed9c5d00b022144776abbb6a44754001","name":"主灯","area_id":"zhu_wo"}"#
        )
        let registry = states.map {
            HomeAssistantEntityRegistryEntry(entityID: $0.entityID, deviceID: device.id)
        }
        let snapshot = HomeAssistantTopologyBuilder.build(
            config: config,
            states: states,
            registryEntries: registry,
            areas: [try decode(HomeAssistantArea.self, #"{"area_id":"zhu_wo","name":"主卧"}"#)],
            devices: [device],
            services: []
        )

        let card = try #require(snapshot.cards.first)
        #expect(card.primaryEntityID == availableID)
        #expect(card.hasMultiplePrimaryControls == false)

        let accessory = try #require(
            HomeAssistantAccessoryReconciler.accessories(
                from: snapshot.cards,
                entities: snapshot.entities
            ).first
        )
        #expect(accessory.primaryControlEntity?.entityID == availableID)
        #expect(accessory.needsReview == false)
        #expect(HomeAssistantAccessoryStateResolver.resolve(accessory).availability == .partiallyAvailable)
    }

    @Test("Automatic primary control follows equivalent light availability changes")
    func automaticPrimaryControlFollowsAvailability() throws {
        let firstID = "light.bedroom_main"
        let secondID = "light.bedroom_main_light"
        let config = try decode(HomeAssistantConfig.self, #"{"location_name":"Home"}"#)
        let initialStates = try decode([HomeAssistantState].self, """
        [
          {"entity_id":"\(firstID)","state":"on","attributes":{"friendly_name":"主灯"}},
          {"entity_id":"\(secondID)","state":"unavailable","attributes":{"friendly_name":"主灯"}}
        ]
        """)
        let device = try decode(HomeAssistantDevice.self, #"{"id":"bedroom-main","name":"主灯"}"#)
        let registry = initialStates.map {
            HomeAssistantEntityRegistryEntry(entityID: $0.entityID, deviceID: device.id)
        }
        let snapshot = HomeAssistantTopologyBuilder.build(
            config: config,
            states: initialStates,
            registryEntries: registry,
            areas: [],
            devices: [device],
            services: []
        )
        let accessory = try #require(
            HomeAssistantAccessoryReconciler.accessories(
                from: snapshot.cards,
                entities: snapshot.entities
            ).first
        )
        let changedStates = try decode([HomeAssistantState].self, """
        [
          {"entity_id":"\(firstID)","state":"unavailable","attributes":{"friendly_name":"主灯"}},
          {"entity_id":"\(secondID)","state":"off","attributes":{"friendly_name":"主灯"}}
        ]
        """)

        let projected = HomeAssistantSnapshotProjection.applying(states: changedStates, to: snapshot)
        let refreshed = try #require(
            HomeAssistantAccessoryReconciler.applying(states: changedStates, to: [accessory]).first
        )

        #expect(projected.cards.first?.primaryEntityID == secondID)
        #expect(refreshed.primaryControlEntity?.entityID == secondID)
        #expect(refreshed.needsReview == false)
        #expect(HomeAssistantAccessoryStateResolver.resolve(refreshed).power == .off)
    }

    @Test("Control policy rejects missing services and confirms unlock")
    func controlPolicy() throws {
        let state = try decode(HomeAssistantState.self, """
        {"entity_id":"lock.front_door","state":"locked","attributes":{}}
        """)
        let entity = HomeAssistantEntity(
            entityID: state.entityID,
            deviceID: nil,
            areaID: nil,
            name: "Front Door",
            domain: "lock",
            deviceClass: nil,
            icon: nil,
            state: state,
            availableServices: ["lock", "unlock"]
        )

        let call = try HomeAssistantControlPolicy.serviceCall(entity: entity, action: .unlock)

        #expect(call.service == "unlock")
        #expect(call.requiresConfirmation)
    }

    @Test("Fan capabilities and actions follow the entity feature attributes")
    func fanCapabilitiesAndActions() throws {
        let state = try decode(HomeAssistantState.self, """
        {
          "entity_id":"fan.living_room",
          "state":"on",
          "attributes":{
            "percentage":75,
            "percentage_step":25,
            "preset_mode":"自然风",
            "preset_modes":["直吹风","自然风"],
            "oscillating":true,
            "current_direction":"forward",
            "supported_features":63
          }
        }
        """)
        let entity = HomeAssistantEntity(
            entityID: state.entityID,
            deviceID: "fan-device",
            areaID: "living",
            name: "客厅落地扇",
            domain: "fan",
            deviceClass: nil,
            icon: nil,
            state: state,
            availableServices: [
                "turn_on", "turn_off", "set_percentage", "set_preset_mode",
                "oscillate", "set_direction",
            ]
        )

        let capabilities = HomeAssistantFanCapabilities(entity: entity)
        #expect(capabilities.percentage == 75)
        #expect(capabilities.percentageStep == 25)
        #expect(capabilities.presetModes == ["直吹风", "自然风"])
        #expect(capabilities.presetMode == "自然风")
        #expect(capabilities.oscillating == true)
        #expect(capabilities.currentDirection == "forward")
        #expect(capabilities.supportsPercentage)
        #expect(capabilities.supportsPresetMode)
        #expect(capabilities.supportsOscillation)
        #expect(capabilities.supportsDirection)

        let speedCall = try HomeAssistantControlPolicy.serviceCall(entity: entity, action: .setPercentage(75))
        let modeCall = try HomeAssistantControlPolicy.serviceCall(entity: entity, action: .setPresetMode("自然风"))
        let oscillationCall = try HomeAssistantControlPolicy.serviceCall(entity: entity, action: .setOscillating(false))
        let directionCall = try HomeAssistantControlPolicy.serviceCall(entity: entity, action: .setDirection("reverse"))

        #expect(speedCall.service == "set_percentage")
        #expect(speedCall.data == ["percentage": .number(75)])
        #expect(modeCall.service == "set_preset_mode")
        #expect(modeCall.data == ["preset_mode": .string("自然风")])
        #expect(oscillationCall.service == "oscillate")
        #expect(oscillationCall.data == ["oscillating": .bool(false)])
        #expect(directionCall.service == "set_direction")
        #expect(directionCall.data == ["direction": .string("reverse")])
    }

    @Test("Fan presentation attributes survive snapshot caching")
    func fanAttributesSurviveSnapshotCaching() throws {
        let config = try decode(HomeAssistantConfig.self, #"{"location_name":"Home"}"#)
        let state = try decode(HomeAssistantState.self, """
        {
          "entity_id":"fan.living_room",
          "state":"on",
          "attributes":{
            "percentage":50,
            "oscillating":true,
            "current_direction":"reverse",
            "latitude":36.0
          }
        }
        """)
        let snapshot = HomeAssistantTopologyBuilder.build(
            config: config,
            states: [state],
            registryEntries: [],
            areas: [],
            devices: [],
            services: [
                HomeAssistantService(
                    domain: "fan",
                    services: ["turn_on": .null, "oscillate": .null, "set_direction": .null]
                ),
            ]
        )

        let cached = HomeAssistantSnapshotProjection.cacheSnapshot(from: snapshot)
        let attributes = try #require(cached.entities.first?.state.attributes)
        #expect(attributes["oscillating"] == .bool(true))
        #expect(attributes["current_direction"] == .string("reverse"))
        #expect(attributes["latitude"] == nil)
    }

    @Test("Climate capabilities map every standard air conditioner control")
    func climateCapabilitiesAndActions() throws {
        let state = try decode(HomeAssistantState.self, """
        {
          "entity_id":"climate.bedroom",
          "state":"cool",
          "attributes":{
            "current_temperature":27.5,
            "temperature":24,
            "min_temp":16,
            "max_temp":30,
            "target_temp_step":1,
            "hvac_modes":["off","cool","dry","fan_only"],
            "fan_mode":"medium",
            "fan_modes":["auto","low","medium","high"],
            "preset_mode":"eco",
            "preset_modes":["none","eco","sleep"],
            "swing_mode":"vertical",
            "swing_modes":["off","vertical"],
            "swing_horizontal_mode":"off",
            "swing_horizontal_modes":["off","on"],
            "supported_features":953
          }
        }
        """)
        let services: Set<String> = [
            "turn_on", "turn_off", "set_temperature", "set_hvac_mode",
            "set_fan_mode", "set_preset_mode", "set_swing_mode", "set_swing_horizontal_mode",
        ]
        let entity = HomeAssistantEntity(
            entityID: state.entityID,
            deviceID: "bedroom-ac",
            areaID: "bedroom",
            name: "主卧空调",
            domain: "climate",
            deviceClass: nil,
            icon: nil,
            state: state,
            availableServices: services
        )

        let capabilities = HomeAssistantClimateCapabilities(entity: entity)

        #expect(capabilities.currentTemperature == 27.5)
        #expect(capabilities.targetTemperature == 24)
        #expect(capabilities.temperatureRange == 16...30)
        #expect(capabilities.temperatureStep == 1)
        #expect(capabilities.hvacModes == ["off", "cool", "dry", "fan_only"])
        #expect(capabilities.fanModes == ["auto", "low", "medium", "high"])
        #expect(capabilities.presetModes == ["none", "eco", "sleep"])
        #expect(capabilities.swingModes == ["off", "vertical"])
        #expect(capabilities.horizontalSwingModes == ["off", "on"])
        #expect(capabilities.supportsTargetTemperature)
        #expect(capabilities.supportsFanMode)
        #expect(capabilities.supportsPresetMode)
        #expect(capabilities.supportsSwingMode)
        #expect(capabilities.supportsHorizontalSwingMode)
        #expect(capabilities.supportsTurnOn)
        #expect(capabilities.supportsTurnOff)

        let temperatureCall = try HomeAssistantControlPolicy.serviceCall(entity: entity, action: .setTemperature(25))
        let fanCall = try HomeAssistantControlPolicy.serviceCall(entity: entity, action: .setClimateFanMode("high"))
        let presetCall = try HomeAssistantControlPolicy.serviceCall(entity: entity, action: .setClimatePresetMode("sleep"))
        let swingCall = try HomeAssistantControlPolicy.serviceCall(entity: entity, action: .setClimateSwingMode("off"))
        let horizontalCall = try HomeAssistantControlPolicy.serviceCall(
            entity: entity,
            action: .setClimateHorizontalSwingMode("on")
        )

        #expect(temperatureCall.service == "set_temperature")
        #expect(temperatureCall.data == ["temperature": .number(25)])
        #expect(fanCall.data == ["fan_mode": .string("high")])
        #expect(presetCall.data == ["preset_mode": .string("sleep")])
        #expect(swingCall.data == ["swing_mode": .string("off")])
        #expect(horizontalCall.data == ["swing_horizontal_mode": .string("on")])
    }

    @Test("Physical air conditioners retain safe configuration controls and cache their options")
    func airConditionerRetainsConfigurationControls() throws {
        let config = try decode(HomeAssistantConfig.self, #"{"location_name":"Home"}"#)
        let states = try decode([HomeAssistantState].self, """
        [
          {"entity_id":"climate.bedroom","state":"cool","attributes":{"friendly_name":"主卧空调","temperature":24,"swing_mode":"off","swing_modes":["off","vertical"],"supported_features":33}},
          {"entity_id":"switch.bedroom_anti_direct_blow","state":"on","attributes":{"friendly_name":"防直吹"}},
          {"entity_id":"select.bedroom_airflow","state":"上摆","attributes":{"friendly_name":"送风角度","options":["上摆","中间","下摆"]}},
          {"entity_id":"button.bedroom_self_clean","state":"2026-08-17T00:00:00+00:00","attributes":{"friendly_name":"自清洁"}},
          {"entity_id":"sensor.bedroom_signal","state":"80","attributes":{"device_class":"signal_strength"}},
          {"entity_id":"select.config_only_mode","state":"auto","attributes":{"friendly_name":"配置模式","options":["auto","manual"]}}
        ]
        """)
        let device = try decode(HomeAssistantDevice.self, #"{"id":"bedroom-ac","name":"主卧空调","area_id":"bedroom"}"#)
        let configOnlyDevice = try decode(HomeAssistantDevice.self, #"{"id":"config-only","name":"配置实体"}"#)
        let registry = [
            HomeAssistantEntityRegistryEntry(entityID: "climate.bedroom", deviceID: device.id),
            HomeAssistantEntityRegistryEntry(entityID: "switch.bedroom_anti_direct_blow", deviceID: device.id, entityCategory: "config"),
            HomeAssistantEntityRegistryEntry(entityID: "select.bedroom_airflow", deviceID: device.id, entityCategory: "config"),
            HomeAssistantEntityRegistryEntry(entityID: "button.bedroom_self_clean", deviceID: device.id, entityCategory: "config"),
            HomeAssistantEntityRegistryEntry(entityID: "sensor.bedroom_signal", deviceID: device.id, entityCategory: "diagnostic"),
            HomeAssistantEntityRegistryEntry(entityID: "select.config_only_mode", deviceID: configOnlyDevice.id, entityCategory: "config"),
        ]

        let snapshot = HomeAssistantTopologyBuilder.build(
            config: config,
            states: states,
            registryEntries: registry,
            areas: [try decode(HomeAssistantArea.self, #"{"area_id":"bedroom","name":"主卧"}"#)],
            devices: [device, configOnlyDevice],
            services: []
        )
        let card = try #require(snapshot.cards.first)
        let accessory = try #require(HomeAssistantAccessoryReconciler.accessories(
            from: snapshot.cards,
            entities: snapshot.entities
        ).first)

        #expect(Set(card.entities.map(\.entityID)) == [
            "climate.bedroom", "switch.bedroom_anti_direct_blow",
            "select.bedroom_airflow", "button.bedroom_self_clean",
        ])
        #expect(!snapshot.entities.contains { $0.entityID == "sensor.bedroom_signal" })
        #expect(snapshot.entities.contains { $0.entityID == "select.config_only_mode" })
        #expect(snapshot.cards.count == 1)
        #expect(accessory.entities(for: .childControl).map(\.entityID) == ["switch.bedroom_anti_direct_blow"])
        #expect(accessory.entities(for: .mode).map(\.entityID) == ["select.bedroom_airflow"])
        #expect(accessory.entities(for: .action).map(\.entityID) == ["button.bedroom_self_clean"])

        let selectEntity = try #require(card.entities.first { $0.domain == "select" })
        let selectCall = try HomeAssistantControlPolicy.serviceCall(
            entity: selectEntity,
            action: .selectOption("下摆")
        )
        #expect(selectCall.service == "select_option")
        #expect(selectCall.data == ["option": .string("下摆")])

        let cached = HomeAssistantSnapshotProjection.cacheSnapshot(from: snapshot)
        let cachedClimate = try #require(cached.entities.first { $0.domain == "climate" })
        let cachedSelect = try #require(cached.entities.first { $0.domain == "select" })
        #expect(cachedClimate.state.attributes["swing_modes"]?.arrayValue?.compactMap(\.stringValue) == ["off", "vertical"])
        #expect(cachedSelect.state.attributes["options"]?.arrayValue?.compactMap(\.stringValue) == ["上摆", "中间", "下摆"])
    }

    @Test("AI result cannot introduce unknown identifiers")
    func validatesAIResult() throws {
        let config = try decode(HomeAssistantConfig.self, #"{"location_name":"Home"}"#)
        let state = try decode(HomeAssistantState.self, """
        {"entity_id":"light.living_room","state":"on","attributes":{}}
        """)
        let snapshot = HomeAssistantTopologyBuilder.build(
            config: config,
            states: [state],
            registryEntries: [.init(entityID: state.entityID, areaID: "living")],
            areas: [try decode(HomeAssistantArea.self, #"{"area_id":"living","name":"Living"}"#)],
            devices: [],
            services: []
        )
        let response = """
        {"roomOrder":["unknown","living"],"featuredEntityIDs":["evil.entity","light.living_room"],"aliases":{"evil.entity":"x","light.living_room":"主灯"},"suggestions":["建议"]}
        """

        let result = try HomeAssistantLayoutAnalyzer.validatedSuggestion(from: response, snapshot: snapshot)

        #expect(result.roomOrder == ["living"])
        #expect(result.featuredEntityIDs == ["light.living_room"])
        #expect(result.aliases == ["light.living_room": "主灯"])
    }

    @Test("AI layout cache is bound to topology hash")
    func layoutCacheUsesTopologyHash() throws {
        let suite = "HomeAssistantTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = HomeAssistantSettingsStore(defaults: defaults)
        let suggestion = HomeAssistantLayoutSuggestion(featuredEntityIDs: ["light.room"])

        store.saveLayoutSuggestion(suggestion, topologyHash: "hash-a")

        #expect(store.loadLayoutSuggestion(topologyHash: "hash-a") == suggestion)
        #expect(store.loadLayoutSuggestion(topologyHash: "hash-b") == nil)
    }

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(type, from: Data(json.utf8))
    }

    private func entity(
        _ json: String,
        deviceID: String? = nil,
        platform: String? = nil,
        translationKey: String? = nil
    ) throws -> HomeAssistantEntity {
        let state = try decode(HomeAssistantState.self, json)
        return HomeAssistantEntity(
            entityID: state.entityID,
            deviceID: deviceID,
            areaID: nil,
            name: state.friendlyName ?? state.entityID,
            domain: state.domain,
            deviceClass: state.deviceClass,
            icon: nil,
            platform: platform,
            translationKey: translationKey,
            state: state,
            availableServices: []
        )
    }

    private func cacheFixtureSnapshot() throws -> HomeAssistantSnapshot {
        let config = try decode(HomeAssistantConfig.self, #"{"location_name":"Home"}"#)
        let states = try decode([HomeAssistantState].self, """
        [
          {"entity_id":"light.living","state":"on","attributes":{"friendly_name":"客厅灯","brightness":128,"latitude":31.2}},
          {"entity_id":"switch.bedroom","state":"on","attributes":{"friendly_name":"卧室插座"}}
        ]
        """)
        let areas = try decode([HomeAssistantArea].self, """
        [{"area_id":"living","name":"客厅"},{"area_id":"bedroom","name":"卧室"}]
        """)
        let devices = try decode([HomeAssistantDevice].self, """
        [
          {"id":"device-living","name":"客厅灯","area_id":"living"},
          {"id":"device-bedroom","name":"卧室插座","area_id":"bedroom"}
        ]
        """)
        let registry = [
            HomeAssistantEntityRegistryEntry(entityID: "light.living", deviceID: "device-living"),
            HomeAssistantEntityRegistryEntry(entityID: "switch.bedroom", deviceID: "device-bedroom"),
        ]
        let services = [
            HomeAssistantService(domain: "light", services: ["turn_on": .null, "turn_off": .null]),
            HomeAssistantService(domain: "switch", services: ["turn_on": .null, "turn_off": .null]),
        ]
        return HomeAssistantTopologyBuilder.build(
            config: config,
            states: states,
            registryEntries: registry,
            areas: areas,
            devices: devices,
            services: services
        )
    }

    private func multipleSwitchSnapshot() throws -> HomeAssistantSnapshot {
        let config = try decode(HomeAssistantConfig.self, #"{"location_name":"Home"}"#)
        let states = try decode([HomeAssistantState].self, """
        [
          {"entity_id":"switch.wall_left","state":"off","attributes":{"friendly_name":"左路"}},
          {"entity_id":"switch.wall_right","state":"on","attributes":{"friendly_name":"右路"}}
        ]
        """)
        let device = try decode(HomeAssistantDevice.self, #"{"id":"wall-device","name":"双路开关"}"#)
        return HomeAssistantTopologyBuilder.build(
            config: config,
            states: states,
            registryEntries: states.map { .init(entityID: $0.entityID, deviceID: device.id) },
            areas: [],
            devices: [device],
            services: []
        )
    }
}

private enum HomeAssistantTestError: Error, Equatable {
    case first
    case duplicate
}

private final class OneShotCompletionRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recordedErrors: [Error?] = []

    var errors: [Error?] {
        lock.lock()
        defer { lock.unlock() }
        return recordedErrors
    }

    func record(_ error: Error?) {
        lock.lock()
        recordedErrors.append(error)
        lock.unlock()
    }
}
