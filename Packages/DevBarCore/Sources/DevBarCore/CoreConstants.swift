import Foundation

public enum DevBarCoreConstants {
    public enum API {
        public static let baseURL = "https://bigmodel.cn"
        public static let loginURL = "\(baseURL)/login"
        public static let subscriptionListURL = "\(baseURL)/api/biz/subscription/list"
        public static let quotaLimitURL = "\(baseURL)/api/monitor/usage/quota/limit"
    }

    public enum Keychain {
        public static let service = "cc.xjpz.DevBar"
        public static let tokenKey = "authorization_token"
        public static let cookieKey = "cookie_string"
        public static let openAIAccessTokenKey = "openai_access_token"
        public static let mimoServiceTokenKey = "mimo_service_token"
        public static let macRelayDeviceSecretKey = "relay_device_secret_mac"
        public static let iPhoneRelayDeviceSecretKey = "relay_device_secret_iphone"
        public static let relayDeviceTokenKey = "relay_device_token"
        public static let relayLocalPairSecretPrefix = "relay_local_pair_secret_"
        public static let relayPendingLocalPairSecretPrefix = "relay_pending_local_pair_secret_"
    }

    public enum OpenAI {
        public static let usageURL = "https://chatgpt.com/backend-api/wham/usage"
        public static let accountIdKey = "openai_account_id"
    }

    public enum MiMO {
        public static let dashboardURL = "https://platform.xiaomimimo.com"
        public static let platformUsageURL = "\(dashboardURL)/api/v1/tokenPlan/usage"
        public static let platformPlanDetailURL = "\(dashboardURL)/api/v1/tokenPlan/detail"
    }

    public enum TransferRelay {
        public static let baseURL = "https://dev.xjpz.cc"
        public static let transfersPath = "/api/devbar/transfers"
        public static let directQRCodeLengthThreshold = 1_800
    }

    public enum DeviceRelay {
        public static let baseURL = "https://dev.xjpz.cc"
        public static let registerPath = "/api/devbar/devices/register"
        public static let peersPath = "/api/devbar/devices/peers"
        public static let createPairPath = "/api/devbar/pair/create"
        public static let confirmPairPath = "/api/devbar/pair/confirm"
        public static let revokePairPath = "/api/devbar/pair/revoke"
        public static let socketPath = "/ws/devbar-relay"
        public static let heartbeatInterval: TimeInterval = 25
        public static let localServiceType = "_devbar-relay._tcp"
        public static let localHeartbeatInterval: TimeInterval = 10
        public static let localConnectTimeout: TimeInterval = 1.5

        public static func commandPath(targetDeviceId: String) -> String {
            "/api/devbar/devices/\(targetDeviceId)/commands"
        }
    }

    public enum AppGroup {
        public static let groupID = "group.cc.xjpz.DevBar"
        public static let sharedDataKey = "widget_shared_data"
        public static let macThemeWidgetSnapshotKey = "mac_theme_widget_snapshot"
        public static let macThemeWidgetSelectedPageKey = "mac_theme_widget_selected_page"
        public static let liveActivitySelectedProviderKey = "live_activity_selected_provider"

        public static func sharedDataKey(for provider: String) -> String {
            "widget_shared_data_\(provider)"
        }
    }

    public enum Defaults {
        public static let refreshIntervalKey = "refresh_interval"
        public static let defaultRefreshInterval: TimeInterval = 300
        public static let accountConfigsKey = "account_configs"
        public static let glmQuotaCacheKey = "glm_quota_cache"
        public static let openAIQuotaCacheKey = "openai_quota_cache"
        public static let mimoQuotaCacheKey = "mimo_quota_cache"
        public static let mimoCookieLastRenewedAtKey = "mimo_cookie_last_renewed_at"
        public static let mimoCookieLastRenewFailedAtKey = "mimo_cookie_last_renew_failed_at"
        public static let mimoCookieAutoRenewEnabledKey = "mimo_cookie_auto_renew_enabled"
        public static let liveActivitySettingsKey = "live_activity_settings"
        public static let relayMacDeviceIDKey = "relay_mac_device_id"
        public static let relayIPhoneDeviceIDKey = "relay_iphone_device_id"
        public static let relayDeviceTokenKey = "relay_device_token"
        public static let relayIPhoneDeviceNameKey = "relay_iphone_device_name"
        public static let relayMacEnabledKey = "relay_mac_enabled"
    }
}
