import Foundation
import Security

public struct HomeAssistantSettingsStore {
    private let defaults: UserDefaults
    private let keychain: KeychainService

    public init(defaults: UserDefaults = .standard, keychain: KeychainService = .shared) {
        self.defaults = defaults
        self.keychain = keychain
    }

    public func load() -> HomeAssistantConnectionSettings {
        guard let data = defaults.data(forKey: DevBarCoreConstants.Defaults.homeAssistantSettingsKey),
              let settings = try? JSONDecoder().decode(HomeAssistantConnectionSettings.self, from: data) else {
            return HomeAssistantConnectionSettings()
        }
        return settings
    }

    public func save(_ settings: HomeAssistantConnectionSettings, token: String?) throws {
        let normalized = try HomeAssistantEndpointSelector.normalizedSettings(settings)
        let data = try JSONEncoder().encode(normalized)
        defaults.set(data, forKey: DevBarCoreConstants.Defaults.homeAssistantSettingsKey)
        if let token {
            let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                keychain.delete(key: DevBarCoreConstants.Keychain.homeAssistantTokenKey)
            } else if keychain.save(key: DevBarCoreConstants.Keychain.homeAssistantTokenKey, value: trimmed) != errSecSuccess {
                throw HomeAssistantError.credentialSaveFailed
            }
        }
        markCloudSettingsModified()
    }

    public func loadToken() -> String {
        keychain.load(key: DevBarCoreConstants.Keychain.homeAssistantTokenKey) ?? ""
    }

    public func loadCloudSyncState() -> ICloudPreferenceState<HomeAssistantCloudSyncSnapshot>? {
        let connectionSettings = load()
        let updatedAt: Date
        if let storedUpdatedAt = cloudSettingsUpdatedAt {
            updatedAt = storedUpdatedAt
        } else {
            guard connectionSettings != HomeAssistantConnectionSettings() else { return nil }
            updatedAt = Date(timeIntervalSince1970: 0)
            setCloudSettingsUpdatedAt(updatedAt)
        }

        let fingerprint = HomeAssistantSnapshotCacheStore.instanceFingerprint(
            externalURL: connectionSettings.externalURL
        )
        let snapshot: HomeAssistantCloudSyncSnapshot
        if let fingerprint {
            snapshot = HomeAssistantCloudSyncSnapshot(
                connectionSettings: connectionSettings,
                instanceFingerprint: fingerprint,
                deviceVisibility: loadDeviceVisibility(instanceFingerprint: fingerprint),
                dashboardLayout: loadDashboardLayout(instanceFingerprint: fingerprint),
                devicePresentations: loadDevicePresentations(instanceFingerprint: fingerprint),
                accessoryPresentations: loadAccessoryPresentations(instanceFingerprint: fingerprint),
                accessoryGrouping: loadAccessoryGrouping(instanceFingerprint: fingerprint)
            )
        } else {
            snapshot = HomeAssistantCloudSyncSnapshot(connectionSettings: connectionSettings)
        }
        return ICloudPreferenceState(value: snapshot, updatedAt: updatedAt)
    }

    @discardableResult
    public func applyCloudSyncState(
        _ state: ICloudPreferenceState<HomeAssistantCloudSyncSnapshot>
    ) -> Bool {
        guard state.value.schemaVersion == HomeAssistantCloudSyncSnapshot.schemaVersion else { return false }
        if let localUpdatedAt = cloudSettingsUpdatedAt, localUpdatedAt > state.updatedAt {
            return false
        }

        let importedSettings: HomeAssistantConnectionSettings
        if state.value.connectionSettings.isConfigured {
            guard let normalized = try? HomeAssistantEndpointSelector.normalizedSettings(
                state.value.connectionSettings
            ) else { return false }
            importedSettings = normalized
        } else {
            importedSettings = HomeAssistantConnectionSettings()
        }

        let oldFingerprint = HomeAssistantSnapshotCacheStore.instanceFingerprint(externalURL: load().externalURL)
        persistConnectionSettings(importedSettings)
        let newFingerprint = HomeAssistantSnapshotCacheStore.instanceFingerprint(externalURL: importedSettings.externalURL)
        if oldFingerprint != newFingerprint, let oldFingerprint {
            removeInstanceSettings(instanceFingerprint: oldFingerprint)
        }
        if let newFingerprint {
            persistCodable(state.value.deviceVisibility, key: visibilityKey(instanceFingerprint: newFingerprint))
            persistCodable(state.value.dashboardLayout, key: dashboardLayoutKey(instanceFingerprint: newFingerprint))
            persistCodable(state.value.devicePresentations, key: presentationKey(instanceFingerprint: newFingerprint))
            persistCodable(
                state.value.accessoryPresentations,
                key: accessoryPresentationKey(instanceFingerprint: newFingerprint)
            )
            persistCodable(state.value.accessoryGrouping, key: accessoryGroupingKey(instanceFingerprint: newFingerprint))
        }
        setCloudSettingsUpdatedAt(state.updatedAt)
        return true
    }

    public func clear() {
        if let fingerprint = HomeAssistantSnapshotCacheStore.instanceFingerprint(externalURL: load().externalURL) {
            defaults.removeObject(forKey: visibilityKey(instanceFingerprint: fingerprint))
            defaults.removeObject(forKey: presentationKey(instanceFingerprint: fingerprint))
            defaults.removeObject(forKey: accessoryPresentationKey(instanceFingerprint: fingerprint))
            defaults.removeObject(forKey: accessoryGroupingKey(instanceFingerprint: fingerprint))
            defaults.removeObject(forKey: translationCatalogKey(instanceFingerprint: fingerprint))
            defaults.removeObject(forKey: dashboardLayoutKey(instanceFingerprint: fingerprint))
        }
        defaults.removeObject(forKey: DevBarCoreConstants.Defaults.homeAssistantSettingsKey)
        defaults.removeObject(forKey: DevBarCoreConstants.Defaults.homeAssistantLayoutSuggestionKey)
        defaults.removeObject(forKey: DevBarCoreConstants.Defaults.homeAssistantTopologyHashKey)
        keychain.delete(key: DevBarCoreConstants.Keychain.homeAssistantTokenKey)
        markCloudSettingsModified()
    }

    public func loadLayoutSuggestion(topologyHash: String) -> HomeAssistantLayoutSuggestion? {
        guard defaults.string(forKey: DevBarCoreConstants.Defaults.homeAssistantTopologyHashKey) == topologyHash,
              let data = defaults.data(forKey: DevBarCoreConstants.Defaults.homeAssistantLayoutSuggestionKey) else {
            return nil
        }
        return try? JSONDecoder().decode(HomeAssistantLayoutSuggestion.self, from: data)
    }

    public func saveLayoutSuggestion(_ suggestion: HomeAssistantLayoutSuggestion, topologyHash: String) {
        guard let data = try? JSONEncoder().encode(suggestion) else { return }
        defaults.set(data, forKey: DevBarCoreConstants.Defaults.homeAssistantLayoutSuggestionKey)
        defaults.set(topologyHash, forKey: DevBarCoreConstants.Defaults.homeAssistantTopologyHashKey)
    }

    public func clearLayoutSuggestion() {
        defaults.removeObject(forKey: DevBarCoreConstants.Defaults.homeAssistantLayoutSuggestionKey)
        defaults.removeObject(forKey: DevBarCoreConstants.Defaults.homeAssistantTopologyHashKey)
    }

    public func loadDeviceVisibility(instanceFingerprint: String) -> HomeAssistantDeviceVisibilitySettings {
        guard let data = defaults.data(forKey: visibilityKey(instanceFingerprint: instanceFingerprint)),
              let settings = try? JSONDecoder().decode(HomeAssistantDeviceVisibilitySettings.self, from: data) else {
            return HomeAssistantDeviceVisibilitySettings()
        }
        return settings
    }

    public func saveDeviceVisibility(
        _ settings: HomeAssistantDeviceVisibilitySettings,
        instanceFingerprint: String
    ) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: visibilityKey(instanceFingerprint: instanceFingerprint))
        markCloudSettingsModified()
    }

    public func loadDashboardLayout(instanceFingerprint: String) -> HomeAssistantDashboardLayoutSettings {
        guard let data = defaults.data(forKey: dashboardLayoutKey(instanceFingerprint: instanceFingerprint)),
              let settings = try? JSONDecoder().decode(HomeAssistantDashboardLayoutSettings.self, from: data),
              settings.schemaVersion == HomeAssistantDashboardLayoutSettings.schemaVersion else {
            return HomeAssistantDashboardLayoutSettings()
        }
        return settings
    }

    public func saveDashboardLayout(
        _ settings: HomeAssistantDashboardLayoutSettings,
        instanceFingerprint: String
    ) {
        guard settings.schemaVersion == HomeAssistantDashboardLayoutSettings.schemaVersion,
              let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: dashboardLayoutKey(instanceFingerprint: instanceFingerprint))
        markCloudSettingsModified()
    }

    public func loadDevicePresentations(
        instanceFingerprint: String
    ) -> HomeAssistantDevicePresentationSettings {
        guard let data = defaults.data(forKey: presentationKey(instanceFingerprint: instanceFingerprint)),
              let settings = try? JSONDecoder().decode(HomeAssistantDevicePresentationSettings.self, from: data) else {
            return HomeAssistantDevicePresentationSettings()
        }
        return settings
    }

    public func saveDevicePresentations(
        _ settings: HomeAssistantDevicePresentationSettings,
        instanceFingerprint: String
    ) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: presentationKey(instanceFingerprint: instanceFingerprint))
        markCloudSettingsModified()
    }

    public func loadAccessoryPresentations(
        instanceFingerprint: String
    ) -> HomeAssistantAccessoryPresentationSettings {
        guard let data = defaults.data(forKey: accessoryPresentationKey(instanceFingerprint: instanceFingerprint)),
              let settings = try? JSONDecoder().decode(HomeAssistantAccessoryPresentationSettings.self, from: data),
              settings.schemaVersion == HomeAssistantAccessoryPresentation.schemaVersion else {
            return HomeAssistantAccessoryPresentationSettings()
        }
        return settings
    }

    public func saveAccessoryPresentations(
        _ settings: HomeAssistantAccessoryPresentationSettings,
        instanceFingerprint: String
    ) {
        guard settings.schemaVersion == HomeAssistantAccessoryPresentation.schemaVersion,
              let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: accessoryPresentationKey(instanceFingerprint: instanceFingerprint))
        markCloudSettingsModified()
    }

    public func loadAccessoryGrouping(
        instanceFingerprint: String
    ) -> HomeAssistantAccessoryGroupingSettings {
        guard let data = defaults.data(forKey: accessoryGroupingKey(instanceFingerprint: instanceFingerprint)),
              let settings = try? JSONDecoder().decode(HomeAssistantAccessoryGroupingSettings.self, from: data),
              settings.schemaVersion == HomeAssistantAccessoryGroupingSettings.schemaVersion else {
            return HomeAssistantAccessoryGroupingSettings()
        }
        return settings
    }

    public func saveAccessoryGrouping(
        _ settings: HomeAssistantAccessoryGroupingSettings,
        instanceFingerprint: String
    ) {
        guard settings.schemaVersion == HomeAssistantAccessoryGroupingSettings.schemaVersion,
              let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: accessoryGroupingKey(instanceFingerprint: instanceFingerprint))
        markCloudSettingsModified()
    }

    public func loadTranslationCatalog(
        instanceFingerprint: String,
        language: String
    ) -> HomeAssistantTranslationCatalog {
        guard let data = defaults.data(forKey: translationCatalogKey(instanceFingerprint: instanceFingerprint)),
              let catalog = try? JSONDecoder().decode(HomeAssistantTranslationCatalog.self, from: data),
              catalog.language == language else {
            return HomeAssistantTranslationCatalog(language: language)
        }
        return catalog
    }

    public func saveTranslationCatalog(
        _ catalog: HomeAssistantTranslationCatalog,
        instanceFingerprint: String
    ) {
        guard let data = try? JSONEncoder().encode(catalog) else { return }
        defaults.set(data, forKey: translationCatalogKey(instanceFingerprint: instanceFingerprint))
    }

    private func visibilityKey(instanceFingerprint: String) -> String {
        "\(DevBarCoreConstants.Defaults.homeAssistantDeviceVisibilityKey).\(instanceFingerprint)"
    }

    private func presentationKey(instanceFingerprint: String) -> String {
        "\(DevBarCoreConstants.Defaults.homeAssistantDevicePresentationKey).\(instanceFingerprint)"
    }

    private func accessoryPresentationKey(instanceFingerprint: String) -> String {
        "\(DevBarCoreConstants.Defaults.homeAssistantAccessoryPresentationKey).\(instanceFingerprint)"
    }

    private func accessoryGroupingKey(instanceFingerprint: String) -> String {
        "\(DevBarCoreConstants.Defaults.homeAssistantAccessoryGroupingKey).\(instanceFingerprint)"
    }

    private func translationCatalogKey(instanceFingerprint: String) -> String {
        "\(DevBarCoreConstants.Defaults.homeAssistantTranslationCatalogKey).\(instanceFingerprint)"
    }

    private func dashboardLayoutKey(instanceFingerprint: String) -> String {
        "\(DevBarCoreConstants.Defaults.homeAssistantDashboardLayoutKey).\(instanceFingerprint)"
    }

    private var cloudSettingsUpdatedAt: Date? {
        guard defaults.object(forKey: DevBarCoreConstants.Defaults.homeAssistantSettingsCloudUpdatedAtKey) != nil else {
            return nil
        }
        return Date(
            timeIntervalSince1970: defaults.double(
                forKey: DevBarCoreConstants.Defaults.homeAssistantSettingsCloudUpdatedAtKey
            )
        )
    }

    private func markCloudSettingsModified() {
        setCloudSettingsUpdatedAt(Date())
    }

    private func setCloudSettingsUpdatedAt(_ date: Date) {
        defaults.set(
            date.timeIntervalSince1970,
            forKey: DevBarCoreConstants.Defaults.homeAssistantSettingsCloudUpdatedAtKey
        )
    }

    private func persistConnectionSettings(_ settings: HomeAssistantConnectionSettings) {
        if settings == HomeAssistantConnectionSettings() {
            defaults.removeObject(forKey: DevBarCoreConstants.Defaults.homeAssistantSettingsKey)
            return
        }
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: DevBarCoreConstants.Defaults.homeAssistantSettingsKey)
    }

    private func persistCodable<Value: Encodable>(_ value: Value?, key: String) {
        guard let value, let data = try? JSONEncoder().encode(value) else {
            defaults.removeObject(forKey: key)
            return
        }
        defaults.set(data, forKey: key)
    }

    private func removeInstanceSettings(instanceFingerprint: String) {
        defaults.removeObject(forKey: visibilityKey(instanceFingerprint: instanceFingerprint))
        defaults.removeObject(forKey: presentationKey(instanceFingerprint: instanceFingerprint))
        defaults.removeObject(forKey: accessoryPresentationKey(instanceFingerprint: instanceFingerprint))
        defaults.removeObject(forKey: accessoryGroupingKey(instanceFingerprint: instanceFingerprint))
        defaults.removeObject(forKey: dashboardLayoutKey(instanceFingerprint: instanceFingerprint))
    }
}

public enum HomeAssistantError: LocalizedError, Equatable, Sendable {
    case invalidExternalURL
    case externalURLRequiresHTTPS
    case invalidInternalURL
    case emptyToken
    case credentialSaveFailed
    case unauthorized
    case invalidResponse
    case disconnected
    case serviceUnavailable
    case unsupportedControl

    public var errorDescription: String? {
        switch self {
        case .invalidExternalURL: "公网地址无效"
        case .externalURLRequiresHTTPS: "公网地址必须使用 HTTPS"
        case .invalidInternalURL: "内网地址无效"
        case .emptyToken: "请输入 Home Assistant Long-Lived Access Token"
        case .credentialSaveFailed: "Token 无法保存到 Keychain"
        case .unauthorized: "Home Assistant Token 无效或已失效"
        case .invalidResponse: "Home Assistant 返回了无法识别的数据"
        case .disconnected: "Home Assistant 连接已断开"
        case .serviceUnavailable: "当前实例不支持此操作"
        case .unsupportedControl: "该实体暂不支持控制"
        }
    }
}

public enum HomeAssistantErrorClassifier {
    public static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if let urlError = error as? URLError, urlError.code == .cancelled { return true }
        let error = error as NSError
        return error.domain == NSURLErrorDomain && error.code == NSURLErrorCancelled
    }
}

public enum HomeAssistantEndpointSelector {
    public static func normalizedSettings(
        _ settings: HomeAssistantConnectionSettings
    ) throws -> HomeAssistantConnectionSettings {
        guard let external = normalizedURL(settings.externalURL), external.scheme == "https" else {
            if normalizedURL(settings.externalURL) != nil { throw HomeAssistantError.externalURLRequiresHTTPS }
            throw HomeAssistantError.invalidExternalURL
        }

        let internalText = settings.internalURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let internalURL: URL?
        if internalText.isEmpty {
            internalURL = nil
        } else {
            guard let resolved = normalizedURL(internalText), ["http", "https"].contains(resolved.scheme ?? "") else {
                throw HomeAssistantError.invalidInternalURL
            }
            internalURL = resolved
        }

        return HomeAssistantConnectionSettings(
            externalURL: external.absoluteString,
            internalURL: internalURL?.absoluteString ?? "",
            internalSSIDs: normalizedSSIDs(settings.internalSSIDs),
            aiAnalysisEnabled: settings.aiAnalysisEnabled,
            showsDiagnosticEntities: settings.showsDiagnosticEntities
        )
    }

    public static func candidates(
        settings: HomeAssistantConnectionSettings,
        interface: HomeAssistantNetworkInterface,
        currentSSID: String? = nil
    ) -> [HomeAssistantEndpointCandidate] {
        guard let externalURL = normalizedURL(settings.externalURL), externalURL.scheme == "https" else { return [] }
        let external = HomeAssistantEndpointCandidate(kind: .externalNetwork, url: externalURL)

        switch interface {
        case .wifi:
            let configuredSSIDs = normalizedSSIDs(settings.internalSSIDs)
            let connectedSSID = currentSSID?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let connectedSSID,
               configuredSSIDs.contains(connectedSSID),
               let internalURL = normalizedURL(settings.internalURL),
               ["http", "https"].contains(internalURL.scheme ?? "") {
                return [HomeAssistantEndpointCandidate(kind: .internalNetwork, url: internalURL), external]
            }
            return [external]
        case .cellular, .other:
            return [external]
        case .unavailable:
            return []
        }
    }

    public static func webSocketURL(from baseURL: URL) -> URL? {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else { return nil }
        components.scheme = baseURL.scheme == "https" ? "wss" : "ws"
        components.path = "/api/websocket"
        components.query = nil
        components.fragment = nil
        return components.url
    }

    private static func normalizedURL(_ rawValue: String) -> URL? {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty,
              var components = URLComponents(string: value),
              let scheme = components.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              components.host?.isEmpty == false,
              components.user == nil,
              components.password == nil else { return nil }
        components.scheme = scheme
        components.path = ""
        components.query = nil
        components.fragment = nil
        return components.url
    }

    private static func normalizedSSIDs(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
            .prefix(3)
            .map { $0 }
    }
}
