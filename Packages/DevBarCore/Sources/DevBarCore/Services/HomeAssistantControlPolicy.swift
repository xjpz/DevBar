import Foundation

public enum HomeAssistantControlAction: Equatable, Sendable {
    case turnOn
    case turnOff
    case toggle
    case setBrightness(Double)
    case setPercentage(Double)
    case open
    case close
    case stop
    case setCoverPosition(Double)
    case setTemperature(Double)
    case setHVACMode(String)
    case lock
    case unlock
    case activate
}

public enum HomeAssistantControlPolicy {
    public static func serviceCall(
        entity: HomeAssistantEntity,
        action: HomeAssistantControlAction
    ) throws -> HomeAssistantServiceCall {
        guard entity.isAvailable else { throw HomeAssistantError.unsupportedControl }
        let service: String
        var data: [String: HomeAssistantJSONValue] = [:]
        var confirmation = false

        switch (entity.domain, action) {
        case ("light", .turnOn), ("switch", .turnOn), ("input_boolean", .turnOn), ("fan", .turnOn): service = "turn_on"
        case ("light", .turnOff), ("switch", .turnOff), ("input_boolean", .turnOff), ("fan", .turnOff): service = "turn_off"
        case ("light", .toggle), ("switch", .toggle), ("input_boolean", .toggle), ("fan", .toggle): service = "toggle"
        case ("light", .setBrightness(let value)):
            service = "turn_on"
            data["brightness_pct"] = .number(clamp(value))
        case ("fan", .setPercentage(let value)):
            service = "set_percentage"
            data["percentage"] = .number(clamp(value))
        case ("cover", .open): service = "open_cover"
        case ("cover", .close): service = "close_cover"
        case ("cover", .stop): service = "stop_cover"
        case ("cover", .setCoverPosition(let value)):
            service = "set_cover_position"
            data["position"] = .number(clamp(value))
        case ("climate", .setTemperature(let value)):
            service = "set_temperature"
            data["temperature"] = .number(value)
        case ("climate", .setHVACMode(let mode)):
            service = "set_hvac_mode"
            data["hvac_mode"] = .string(mode)
        case ("lock", .lock): service = "lock"
        case ("lock", .unlock):
            service = "unlock"
            confirmation = true
        case ("scene", .activate):
            service = "turn_on"
            confirmation = true
        case ("script", .activate):
            service = "turn_on"
            confirmation = true
        case ("automation", .activate):
            service = "trigger"
            confirmation = true
        case ("button", .activate):
            service = "press"
            confirmation = true
        default:
            throw HomeAssistantError.unsupportedControl
        }

        guard entity.availableServices.contains(service) else {
            throw HomeAssistantError.serviceUnavailable
        }
        return HomeAssistantServiceCall(
            domain: entity.domain,
            service: service,
            targetEntityID: entity.entityID,
            data: data,
            requiresConfirmation: confirmation
        )
    }

    public static func quickAction(for entity: HomeAssistantEntity) -> HomeAssistantControlAction? {
        switch entity.domain {
        case "light", "switch", "input_boolean", "fan": entity.isOn ? .turnOff : .turnOn
        case "lock": entity.state.state == "locked" ? .unlock : .lock
        case "cover": entity.state.state == "open" ? .close : .open
        case "scene", "script", "automation", "button": .activate
        default: nil
        }
    }

    private static func clamp(_ value: Double) -> Double {
        min(100, max(0, value))
    }
}
