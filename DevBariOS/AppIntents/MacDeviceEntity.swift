import AppIntents
import DevBarCore
import Foundation

struct MacDeviceEntity: AppEntity, Identifiable {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Mac")
    static var defaultQuery = MacDeviceEntityQuery()

    let id: String
    let name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }

    init(id: String, name: String) {
        self.id = id
        self.name = name
    }

    init(device: DeviceRelayDevice) {
        self.id = device.deviceId
        self.name = device.deviceName?.isEmpty == false ? device.deviceName! : "Mac \(device.deviceId.suffix(6))"
    }
}
