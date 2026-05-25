import AppIntents
import DevBarCore
import Foundation

struct MacDeviceEntityQuery: EntityQuery {
    func entities(for identifiers: [MacDeviceEntity.ID]) async throws -> [MacDeviceEntity] {
        let devices = try await Self.fetchMacDevices()
        return devices.filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [MacDeviceEntity] {
        try await Self.fetchMacDevices()
    }

    static func defaultResult() async -> MacDeviceEntity? {
        try? await fetchMacDevices().first
    }

    static func fetchMacDevices() async throws -> [MacDeviceEntity] {
        let store = DeviceRelayStore()
        guard let token = store.loadDeviceToken(), !token.isEmpty else {
            return []
        }
        let peers = try await DeviceRelayService.shared.fetchPeers(deviceToken: token)
        return peers
            .filter { $0.deviceType == .mac }
            .map(MacDeviceEntity.init(device:))
    }
}
