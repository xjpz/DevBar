public enum HomeAssistantDashboardPresentationPolicy {
    public static func isShownByDefault(_ kind: HomeAssistantAccessoryKind) -> Bool {
        kind != .sensorGroup
    }

    public static func isShown(
        _ kind: HomeAssistantAccessoryKind,
        cardID: String,
        visibility: HomeAssistantDeviceVisibilitySettings
    ) -> Bool {
        if visibility.hiddenCardIDs.contains(cardID) { return false }
        if visibility.shownCardIDs.contains(cardID) { return true }
        return isShownByDefault(kind)
    }

    public static func defaultCardSize(for kind: HomeAssistantAccessoryKind) -> HomeAssistantCardSize {
        switch kind {
        case .light, .airConditioner, .sensorGroup: .standard
        default: .compact
        }
    }
}
