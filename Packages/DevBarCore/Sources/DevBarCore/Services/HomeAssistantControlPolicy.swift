import Foundation

public enum HomeAssistantControlAction: Equatable, Sendable {
    case turnOn
    case turnOff
    case toggle
    case setBrightness(Double)
    case setPercentage(Double)
    case setPresetMode(String)
    case setOscillating(Bool)
    case setDirection(String)
    case setClimateFanMode(String)
    case setClimatePresetMode(String)
    case setClimateSwingMode(String)
    case setClimateHorizontalSwingMode(String)
    case selectOption(String)
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
        case ("fan", .setPresetMode(let mode)):
            service = "set_preset_mode"
            data["preset_mode"] = .string(mode)
        case ("fan", .setOscillating(let oscillating)):
            service = "oscillate"
            data["oscillating"] = .bool(oscillating)
        case ("fan", .setDirection(let direction)):
            service = "set_direction"
            data["direction"] = .string(direction)
        case ("climate", .turnOn):
            guard HomeAssistantClimateCapabilities(entity: entity).supportsTurnOn else {
                throw HomeAssistantError.unsupportedControl
            }
            service = "turn_on"
        case ("climate", .turnOff):
            guard HomeAssistantClimateCapabilities(entity: entity).supportsTurnOff else {
                throw HomeAssistantError.unsupportedControl
            }
            service = "turn_off"
        case ("cover", .open): service = "open_cover"
        case ("cover", .close): service = "close_cover"
        case ("cover", .stop): service = "stop_cover"
        case ("cover", .setCoverPosition(let value)):
            service = "set_cover_position"
            data["position"] = .number(clamp(value))
        case ("climate", .setTemperature(let value)):
            let capabilities = HomeAssistantClimateCapabilities(entity: entity)
            guard capabilities.supportsTargetTemperature,
                  capabilities.temperatureRange.contains(value) else {
                throw HomeAssistantError.unsupportedControl
            }
            service = "set_temperature"
            data["temperature"] = .number(value)
        case ("climate", .setHVACMode(let mode)):
            let capabilities = HomeAssistantClimateCapabilities(entity: entity)
            guard capabilities.supportsHVACMode, capabilities.hvacModes.contains(mode) else {
                throw HomeAssistantError.unsupportedControl
            }
            service = "set_hvac_mode"
            data["hvac_mode"] = .string(mode)
        case ("climate", .setClimateFanMode(let mode)):
            let capabilities = HomeAssistantClimateCapabilities(entity: entity)
            guard capabilities.supportsFanMode, capabilities.fanModes.contains(mode) else {
                throw HomeAssistantError.unsupportedControl
            }
            service = "set_fan_mode"
            data["fan_mode"] = .string(mode)
        case ("climate", .setClimatePresetMode(let mode)):
            let capabilities = HomeAssistantClimateCapabilities(entity: entity)
            guard capabilities.supportsPresetMode, capabilities.presetModes.contains(mode) else {
                throw HomeAssistantError.unsupportedControl
            }
            service = "set_preset_mode"
            data["preset_mode"] = .string(mode)
        case ("climate", .setClimateSwingMode(let mode)):
            let capabilities = HomeAssistantClimateCapabilities(entity: entity)
            guard capabilities.supportsSwingMode, capabilities.swingModes.contains(mode) else {
                throw HomeAssistantError.unsupportedControl
            }
            service = "set_swing_mode"
            data["swing_mode"] = .string(mode)
        case ("climate", .setClimateHorizontalSwingMode(let mode)):
            let capabilities = HomeAssistantClimateCapabilities(entity: entity)
            guard capabilities.supportsHorizontalSwingMode,
                  capabilities.horizontalSwingModes.contains(mode) else {
                throw HomeAssistantError.unsupportedControl
            }
            service = "set_swing_horizontal_mode"
            data["swing_horizontal_mode"] = .string(mode)
        case ("select", .selectOption(let option)), ("input_select", .selectOption(let option)):
            let options = entity.state.attributes["options"]?.arrayValue?.compactMap(\.stringValue) ?? []
            guard options.contains(option) else { throw HomeAssistantError.unsupportedControl }
            service = "select_option"
            data["option"] = .string(option)
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

public struct HomeAssistantFanCapabilities: Equatable, Sendable {
    private static let setSpeedFeature = 1
    private static let oscillateFeature = 2
    private static let directionFeature = 4
    private static let presetModeFeature = 8

    public let percentage: Double?
    public let percentageStep: Double
    public let presetModes: [String]
    public let presetMode: String?
    public let oscillating: Bool?
    public let currentDirection: String?
    public let supportsPercentage: Bool
    public let supportsPresetMode: Bool
    public let supportsOscillation: Bool
    public let supportsDirection: Bool

    public init(entity: HomeAssistantEntity) {
        let attributes = entity.state.attributes
        let supportedFeatures = Int(attributes["supported_features"]?.doubleValue ?? 0)
        let rawStep = attributes["percentage_step"]?.doubleValue ?? 1
        let modes = attributes["preset_modes"]?.arrayValue?.compactMap(\.stringValue) ?? []

        percentage = attributes["percentage"]?.doubleValue
        percentageStep = min(100, max(1, rawStep))
        presetModes = modes.reduce(into: []) { result, mode in
            if !mode.isEmpty, !result.contains(mode) { result.append(mode) }
        }
        presetMode = attributes["preset_mode"]?.stringValue
        oscillating = attributes["oscillating"]?.boolValue
        currentDirection = attributes["current_direction"]?.stringValue
        supportsPercentage = supportedFeatures & Self.setSpeedFeature != 0 || percentage != nil
        supportsPresetMode = supportedFeatures & Self.presetModeFeature != 0 || !presetModes.isEmpty
        supportsOscillation = supportedFeatures & Self.oscillateFeature != 0
        supportsDirection = supportedFeatures & Self.directionFeature != 0
    }
}

public struct HomeAssistantClimateCapabilities: Equatable, Sendable {
    private static let targetTemperatureFeature = 1
    private static let fanModeFeature = 8
    private static let presetModeFeature = 16
    private static let swingModeFeature = 32
    private static let turnOffFeature = 128
    private static let turnOnFeature = 256
    private static let horizontalSwingModeFeature = 512

    public let isOn: Bool
    public let currentTemperature: Double?
    public let targetTemperature: Double?
    public let minimumTemperature: Double
    public let maximumTemperature: Double
    public let temperatureStep: Double
    public let temperatureUnit: String
    public let hvacModes: [String]
    public let hvacMode: String
    public let fanModes: [String]
    public let fanMode: String?
    public let presetModes: [String]
    public let presetMode: String?
    public let swingModes: [String]
    public let swingMode: String?
    public let horizontalSwingModes: [String]
    public let horizontalSwingMode: String?
    public let supportsTargetTemperature: Bool
    public let supportsHVACMode: Bool
    public let supportsFanMode: Bool
    public let supportsPresetMode: Bool
    public let supportsSwingMode: Bool
    public let supportsHorizontalSwingMode: Bool
    public let supportsTurnOn: Bool
    public let supportsTurnOff: Bool

    public var temperatureRange: ClosedRange<Double> {
        minimumTemperature...maximumTemperature
    }

    public init(entity: HomeAssistantEntity) {
        let attributes = entity.state.attributes
        let supportedFeatures = Int(attributes["supported_features"]?.doubleValue ?? 0)
        let minimum = attributes["min_temp"]?.doubleValue ?? 7
        let maximum = attributes["max_temp"]?.doubleValue ?? 35
        let resolvedTargetTemperature = attributes["temperature"]?.doubleValue
        let resolvedHVACModes = Self.uniqueStrings(attributes["hvac_modes"])
        let resolvedFanModes = Self.uniqueStrings(attributes["fan_modes"])
        let resolvedPresetModes = Self.uniqueStrings(attributes["preset_modes"])
        let resolvedSwingModes = Self.uniqueStrings(attributes["swing_modes"])
        let resolvedHorizontalSwingModes = Self.uniqueStrings(attributes["swing_horizontal_modes"])

        isOn = entity.isAvailable && entity.state.state != "off"
        currentTemperature = attributes["current_temperature"]?.doubleValue
        targetTemperature = resolvedTargetTemperature
        minimumTemperature = min(minimum, maximum)
        maximumTemperature = max(minimum, maximum)
        temperatureStep = max(0.1, attributes["target_temp_step"]?.doubleValue ?? 0.5)
        temperatureUnit = attributes["temperature_unit"]?.stringValue
            ?? attributes["unit_of_measurement"]?.stringValue
            ?? "°C"
        hvacModes = resolvedHVACModes
        hvacMode = entity.state.state
        fanModes = resolvedFanModes
        fanMode = attributes["fan_mode"]?.stringValue
        presetModes = resolvedPresetModes
        presetMode = attributes["preset_mode"]?.stringValue
        swingModes = resolvedSwingModes
        swingMode = attributes["swing_mode"]?.stringValue
        horizontalSwingModes = resolvedHorizontalSwingModes
        horizontalSwingMode = attributes["swing_horizontal_mode"]?.stringValue

        supportsTargetTemperature = supportedFeatures & Self.targetTemperatureFeature != 0
            || resolvedTargetTemperature != nil
        supportsHVACMode = !resolvedHVACModes.isEmpty && entity.availableServices.contains("set_hvac_mode")
        supportsFanMode = supportedFeatures & Self.fanModeFeature != 0
            && !resolvedFanModes.isEmpty
            && entity.availableServices.contains("set_fan_mode")
        supportsPresetMode = supportedFeatures & Self.presetModeFeature != 0
            && !resolvedPresetModes.isEmpty
            && entity.availableServices.contains("set_preset_mode")
        supportsSwingMode = supportedFeatures & Self.swingModeFeature != 0
            && !resolvedSwingModes.isEmpty
            && entity.availableServices.contains("set_swing_mode")
        supportsHorizontalSwingMode = supportedFeatures & Self.horizontalSwingModeFeature != 0
            && !resolvedHorizontalSwingModes.isEmpty
            && entity.availableServices.contains("set_swing_horizontal_mode")
        supportsTurnOn = supportedFeatures & Self.turnOnFeature != 0
            && entity.availableServices.contains("turn_on")
        supportsTurnOff = supportedFeatures & Self.turnOffFeature != 0
            && entity.availableServices.contains("turn_off")
    }

    private static func uniqueStrings(_ value: HomeAssistantJSONValue?) -> [String] {
        (value?.arrayValue?.compactMap(\.stringValue) ?? []).reduce(into: []) { result, item in
            guard !item.isEmpty, !result.contains(item) else { return }
            result.append(item)
        }
    }
}
