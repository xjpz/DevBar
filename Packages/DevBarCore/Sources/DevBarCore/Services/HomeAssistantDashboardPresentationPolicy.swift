public enum HomeAssistantDashboardPresentationPolicy {
    public static func isShownByDefault(_ kind: HomeAssistantAccessoryKind) -> Bool {
        kind != .sensorGroup
    }

    public static func defaultCardSize(for kind: HomeAssistantAccessoryKind) -> HomeAssistantCardSize {
        switch kind {
        case .light, .airConditioner, .sensorGroup: .standard
        default: .compact
        }
    }
}
