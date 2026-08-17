import Foundation

public enum HomeAssistantStateFormatter {
    public static func presentation(
        for entity: HomeAssistantEntity,
        role: HomeAssistantAccessoryRole? = nil,
        translations: HomeAssistantTranslationCatalog? = nil,
        locale: Locale = .current
    ) -> HomeAssistantStatePresentation {
        let rawState = entity.state.state
        if rawState == "unavailable" {
            return .init(title: "不可用", tone: .unavailable)
        }
        if rawState == "unknown" {
            return .init(title: "状态未知", tone: .unavailable)
        }

        if entity.domain == "sensor" || entity.domain == "number" {
            if Double(rawState) == nil, let translated = translations?.stateText(for: entity) {
                return .init(title: translated, tone: .neutral)
            }
            let value = formattedMeasurement(entity, locale: locale)
            return .init(title: value, tone: .neutral)
        }

        let title = translations?.stateText(for: entity) ?? translatedState(
                rawState,
                domain: entity.domain,
                deviceClass: entity.deviceClass,
                role: role
            )
        return .init(
            title: title,
            tone: tone(for: rawState, domain: entity.domain, deviceClass: entity.deviceClass)
        )
    }

    public static func stateText(
        for entity: HomeAssistantEntity,
        role: HomeAssistantAccessoryRole? = nil,
        translations: HomeAssistantTranslationCatalog? = nil,
        locale: Locale = .current
    ) -> String {
        presentation(for: entity, role: role, translations: translations, locale: locale).title
    }

    public static func attributeName(_ key: String) -> String {
        switch key {
        case "brightness": "亮度"
        case "color_temp", "color_temp_kelvin": "色温"
        case "current_position": "当前位置"
        case "current_temperature": "当前温度"
        case "temperature": "目标温度"
        case "humidity", "current_humidity": "湿度"
        case "fan_mode": "风速模式"
        case "swing_mode": "摆风"
        case "swing_horizontal_mode": "左右摆风"
        case "oscillating": "摆风"
        case "current_direction": "风向"
        case "preset_mode": "预设模式"
        case "percentage": "风速"
        case "hvac_action": "运行状态"
        case "hvac_modes": "支持模式"
        case "fan_modes": "支持风速"
        case "preset_modes": "支持预设"
        case "unit_of_measurement": "单位"
        default: readableFallback(key)
        }
    }

    public static func attributeName(
        _ key: String,
        entity: HomeAssistantEntity,
        translations: HomeAssistantTranslationCatalog?
    ) -> String {
        translations?.attributeName(key, for: entity) ?? attributeName(key)
    }

    public static func attributeValue(
        key: String,
        value: HomeAssistantJSONValue,
        entity: HomeAssistantEntity? = nil,
        translations: HomeAssistantTranslationCatalog? = nil,
        locale: Locale = .current
    ) -> String? {
        if let values = value.arrayValue?.compactMap(\.stringValue) {
            return values.map { rawValue in
                if let entity, let translated = translations?.attributeValue(rawValue, attribute: key, for: entity) {
                    return translated
                }
                return translatedAttributeState(rawValue, key: key)
            }.joined(separator: "、")
        }
        if let raw = value.stringValue {
            if key == "temperature" || key == "current_temperature" {
                let unit = entity?.state.attributes["unit_of_measurement"]?.stringValue ?? "°C"
                return "\(raw)\(unit)"
            }
            if key == "percentage" || key == "current_position" || key == "humidity" || key == "current_humidity" {
                return raw.hasSuffix("%") ? raw : "\(raw)%"
            }
            if let entity, let translated = translations?.attributeValue(raw, attribute: key, for: entity) {
                return translated
            }
            return translatedAttributeState(raw, key: key)
        }
        if let number = value.doubleValue {
            return number.formatted(.number.locale(locale).precision(.fractionLength(0...2)))
        }
        if let boolean = value.boolValue {
            return boolean ? "是" : "否"
        }
        return nil
    }

    public static func translatedAttributeState(_ rawValue: String, key: String) -> String {
        switch key {
        case "hvac_action":
            return translatedState(rawValue, domain: "climate", deviceClass: nil, role: .activity)
        case "fan_mode", "fan_modes":
            return switch rawValue {
            case "auto": "自动"
            case "low": "低速"
            case "medium", "mid": "中速"
            case "high": "高速"
            case "quiet", "silent": "静音"
            case "turbo": "强劲"
            case "off": "关闭"
            default: readableFallback(rawValue)
            }
        case "swing_mode", "swing_horizontal_mode":
            return switch rawValue {
            case "on": "开启"
            case "off": "关闭"
            case "vertical": "上下摆风"
            case "horizontal": "左右摆风"
            case "both": "全向摆风"
            default: readableFallback(rawValue)
            }
        case "oscillating":
            return ["true", "on"].contains(rawValue.lowercased()) ? "开启" : "关闭"
        case "current_direction":
            return switch rawValue {
            case "forward": "正向"
            case "reverse", "backward": "反向"
            default: readableFallback(rawValue)
            }
        case "preset_mode", "preset_modes":
            return switch rawValue {
            case "auto": "自动"
            case "sleep": "睡眠"
            case "eco": "节能"
            case "away": "离家"
            case "comfort": "舒适"
            case "boost": "强劲"
            default: readableFallback(rawValue)
            }
        case "hvac_modes":
            return translatedState(rawValue, domain: "climate", deviceClass: nil, role: nil)
        default:
            return readableFallback(rawValue)
        }
    }

    public static func translatedState(
        _ rawState: String,
        domain: String,
        deviceClass: String?,
        role: HomeAssistantAccessoryRole?
    ) -> String {
        if rawState == "unavailable" { return "不可用" }
        if rawState == "unknown" { return "状态未知" }

        switch domain {
        case "switch", "input_boolean":
            return binaryState(rawState, on: "已开启", off: "已关闭")
        case "light":
            return binaryState(rawState, on: "已打开", off: "已关闭")
        case "fan":
            return binaryState(rawState, on: "运行中", off: "已停止")
        case "climate":
            return switch rawState {
            case "off": "已关闭"
            case "auto": "自动"
            case "heat", "heating": "制热"
            case "cool", "cooling": "制冷"
            case "dry", "drying": "除湿"
            case "fan_only": "送风"
            case "idle": "空闲"
            default: readableFallback(rawState)
            }
        case "cover":
            return switch rawState {
            case "open": "已打开"
            case "opening": "正在打开"
            case "closed": "已关闭"
            case "closing": "正在关闭"
            default: readableFallback(rawState)
            }
        case "lock":
            return switch rawState {
            case "locked": "已上锁"
            case "unlocked": "已解锁"
            case "locking": "正在上锁"
            case "unlocking": "正在解锁"
            case "jammed": "锁具卡住"
            default: readableFallback(rawState)
            }
        case "binary_sensor":
            return translatedBinarySensor(rawState, deviceClass: deviceClass)
        case "automation":
            return binaryState(rawState, on: "已启用", off: "已停用")
        case "media_player":
            return switch rawState {
            case "playing": "正在播放"
            case "paused": "已暂停"
            case "idle": "空闲"
            case "off": "已关闭"
            default: readableFallback(rawState)
            }
        default:
            if role == .indicator || role == .childControl {
                return binaryState(rawState, on: "已开启", off: "已关闭")
            }
            return readableFallback(rawState)
        }
    }

    public static func readableFallback(_ value: String) -> String {
        value.replacingOccurrences(of: "_", with: " ")
    }

    private static func formattedMeasurement(_ entity: HomeAssistantEntity, locale: Locale) -> String {
        let unit = entity.state.attributes["unit_of_measurement"]?.stringValue ?? ""
        if let number = Double(entity.state.state) {
            let formatted = number.formatted(.number.locale(locale).precision(.fractionLength(0...2)))
            return unit.isEmpty ? formatted : "\(formatted) \(unit)"
        }
        return unit.isEmpty ? readableFallback(entity.state.state) : "\(readableFallback(entity.state.state)) \(unit)"
    }

    private static func translatedBinarySensor(_ rawState: String, deviceClass: String?) -> String {
        let isOn = rawState == "on"
        switch deviceClass {
        case "door", "garage_door", "opening", "window": return isOn ? "已打开" : "已关闭"
        case "lock": return isOn ? "已解锁" : "已上锁"
        case "motion", "occupancy", "presence": return isOn ? "检测到活动" : "未检测到活动"
        case "problem": return isOn ? "存在异常" : "正常"
        case "safety": return isOn ? "存在风险" : "安全"
        case "smoke": return isOn ? "检测到烟雾" : "未检测到烟雾"
        case "gas": return isOn ? "检测到燃气" : "未检测到燃气"
        case "moisture": return isOn ? "检测到水" : "干燥"
        case "connectivity": return isOn ? "已连接" : "已断开"
        case "running": return isOn ? "运行中" : "已停止"
        case "battery": return isOn ? "电量低" : "正常"
        case "battery_charging": return isOn ? "正在充电" : "未充电"
        default: return isOn ? "已触发" : "未触发"
        }
    }

    private static func binaryState(_ rawState: String, on: String, off: String) -> String {
        switch rawState {
        case "on": on
        case "off": off
        default: readableFallback(rawState)
        }
    }

    private static func tone(for rawState: String, domain: String, deviceClass: String?) -> HomeAssistantAccessoryTone {
        if ["unavailable", "unknown"].contains(rawState) { return .unavailable }
        if domain == "binary_sensor", ["problem", "safety", "smoke", "gas", "moisture"].contains(deviceClass ?? ""), rawState == "on" {
            return .warning
        }
        if ["on", "open", "opening", "unlocked", "playing", "heat", "cool", "heating", "cooling", "running"].contains(rawState) {
            return .active
        }
        return .neutral
    }
}
