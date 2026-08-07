import Foundation

public enum DevBarCoreConstants {
    public enum Server {
        public static let baseURL = "https://xjpz.cc"
    }

    public enum Features {
        public static let agentWatcherEnabled = true
        public static let flipClockWidgetEnabled = true
        public static let iPhoneWidgetsEnabled = false
        public static let notificationRemindersEnabled = true
    }

    public enum API {
        public static let baseURL = "https://bigmodel.cn"
        public static let loginURL = "\(baseURL)/login"
        public static let subscriptionListURL = "\(baseURL)/api/biz/subscription/list"
        public static let quotaLimitURL = "\(baseURL)/api/monitor/usage/quota/limit"
        public static let glmChatCompletionsURL = "https://open.bigmodel.cn/api/coding/paas/v4/chat/completions"
    }

    public enum Keychain {
        public static let service = "cc.xjpz.DevBar"
        public static let tokenKey = "authorization_token"
        public static let cookieKey = "cookie_string"
        public static let glmAPIKeyKey = "glm_api_key"
        public static let hermesAPIKeyKey = "hermes_api_key"
        public static let homeAssistantTokenKey = "home_assistant_token"
        public static let openAIAccessTokenKey = "openai_access_token"
        public static let mimoServiceTokenKey = "mimo_service_token"
        public static let macRelayDeviceIDKey = "relay_device_id_mac"
        public static let iPhoneRelayDeviceIDKey = "relay_device_id_iphone"
        public static let macRelayDeviceSecretKey = "relay_device_secret_mac"
        public static let iPhoneRelayDeviceSecretKey = "relay_device_secret_iphone"
        public static let relayDeviceTokenKey = "relay_device_token"
        public static let relayLocalPairSecretPrefix = "relay_local_pair_secret_"
        public static let relayPendingLocalPairSecretPrefix = "relay_pending_local_pair_secret_"
        public static let devBarAppSessionTokenKey = "devbar_app_session_token_v1"

        public static func providerAccountCredentialKey(for accountID: String) -> String {
            "provider_account_\(accountID)_credential"
        }
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

    public enum DeepSeek {
        public static let dashboardURL = "https://platform.deepseek.com"
        public static let platformAPIBase = "\(dashboardURL)/api/v0"
        public static let userSummaryURL = "\(platformAPIBase)/users/get_user_summary"
    }

    public enum TransferRelay {
        public static let baseURL = Server.baseURL
        public static let transfersPath = "/api/devbar/transfers"
        public static let directQRCodeLengthThreshold = 1_800
    }

    public enum DeviceRelay {
        public static let baseURL = Server.baseURL
        public static let registerPath = "/api/devbar/devices/register"
        public static let peersPath = "/api/devbar/devices/peers"
        public static let createPairPath = "/api/devbar/pair/create"
        public static let confirmPairPath = "/api/devbar/pair/confirm"
        public static let revokePairPath = "/api/devbar/pair/revoke"
        public static let accountBindPreviewPath = "/api/devbar/devices/account-bind/preview"
        public static let accountBindConfirmPath = "/api/devbar/devices/account-bind/confirm"
        public static let socketPath = "/ws/devbar-relay"
        public static let heartbeatInterval: TimeInterval = 25
        public static let localServiceType = "_devbar-relay._tcp"
        public static let localHeartbeatInterval: TimeInterval = 10
        public static let localConnectTimeout: TimeInterval = 1.5

        public static func commandPath(targetDeviceId: String) -> String {
            "/api/devbar/devices/\(targetDeviceId)/commands"
        }
    }

    public enum PushNotifications {
        public static let registerPath = "/api/devbar/push/register"
        public static let preferencesPath = "/api/devbar/push/preferences"
        public static let liveActivityPushToStartPath = "/api/devbar/push/live-activities/push-to-start"
        public static let liveActivitiesPath = "/api/devbar/push/live-activities"
        public static let liveMessagePath = "/api/devbar/push/live-message"
        public static let smsAlertPath = "/api/devbar/push/sms-alert"
        public static let openKeysPath = "/api/devbar/push/open-keys"

        public static func openKeyPath(id: Int64) -> String {
            "\(openKeysPath)/\(id)"
        }

        public static func liveActivityPath(activityId: String) -> String {
            "\(liveActivitiesPath)/\(activityId)"
        }
    }

    public enum Diagnostics {
        public static let logsPath = "/api/devbar/diagnostics/logs"
    }

    public enum AppGroup {
        public static let groupID = "group.cc.xjpz.DevBar"
        public static let sharedDataKey = "widget_shared_data"
        public static let macThemeWidgetSnapshotKey = "mac_theme_widget_snapshot"
        public static let macThemeWidgetSelectedPageKey = "mac_theme_widget_selected_page"
        public static let macThemeWidgetQuotaProviderPageKey = "mac_theme_widget_quota_provider_page"
        public static let desktopQuotaWidgetProviderPageKey = "desktop_quota_widget_provider_page"
        public static let macThemeWidgetAvatarFileName = "mac-theme-widget-avatar.jpg"
        public static let liveActivitySelectedProviderKey = "live_activity_selected_provider"
        public static let agentWatcherWidgetKey = "agent_watcher_widget_data"
        public static let enabledWidgetProvidersKey = "enabled_widget_providers"

        public static func sharedDataKey(for provider: String) -> String {
            "widget_shared_data_\(provider)"
        }

        public static func quotaSnapshotKey(for accountID: String) -> String {
            "quota_snapshot_\(accountID)"
        }
    }

    public enum ICloud {
        public static let containerIdentifier = "iCloud.cc.xjpz.DevBar"
    }

    public enum Defaults {
        public static let refreshIntervalKey = "refresh_interval"
        public static let defaultRefreshInterval: TimeInterval = 300
        public static let accountConfigsKey = "account_configs"
        public static let providerAccountsKey = "provider_accounts_v2"
        public static let providerPingConfigsKey = "provider_ping_configs"
        public static let hermesAPIBaseURLKey = "hermes_api_base_url"
        public static let hermesModelKey = "hermes_model"
        public static let hermesProviderKey = "hermes_provider"
        public static let hermesStreamingEnabledKey = "hermes_streaming_enabled"
        public static let hermesChatTabProviderKey = "hermes_chat_tab_provider"
        public static let hermesChatHermesRemarkKey = "hermes_chat_hermes_remark"
        public static let hermesChatHermesTagKey = "hermes_chat_hermes_tag"
        public static let hermesQuickStartItemsKey = "hermes_quick_start_items_v1"
        public static let iosWebKitTabEnabledKey = "ios_webkit_tab_enabled"
        public static let glmQuotaCacheKey = "glm_quota_cache"
        public static let openAIQuotaCacheKey = "openai_quota_cache"
        public static let mimoQuotaCacheKey = "mimo_quota_cache"
        public static let deepseekQuotaCacheKey = "deepseek_quota_cache"
        public static let mimoCookieLastRenewedAtKey = "mimo_cookie_last_renewed_at"
        public static let mimoCookieLastRenewFailedAtKey = "mimo_cookie_last_renew_failed_at"
        public static let mimoCookieAutoRenewEnabledKey = "mimo_cookie_auto_renew_enabled"
        public static let liveActivitySettingsKey = "live_activity_settings"
        public static let relayMacDeviceIDKey = "relay_mac_device_id"
        public static let relayIPhoneDeviceIDKey = "relay_iphone_device_id"
        public static let relayDeviceTokenKey = "relay_device_token"
        public static let relayIPhoneDeviceNameKey = "relay_iphone_device_name"
        public static let macThemeWidgetUserNameKey = "mac_theme_widget_user_name"
        public static let relayMacEnabledKey = "relay_mac_enabled"
        public static let iCloudSyncSettingsKey = "icloud_sync_settings_v1"
        public static let iCloudSyncSettingsEnvelopeKey = "icloud_sync_settings_envelope_v1"
        public static let homeAssistantSettingsKey = "home_assistant_settings_v1"
        public static let homeAssistantSettingsCloudUpdatedAtKey = "home_assistant_settings_cloud_updated_at_v1"
        public static let homeAssistantLayoutSuggestionKey = "home_assistant_layout_suggestion_v1"
        public static let homeAssistantTopologyHashKey = "home_assistant_topology_hash_v1"
        public static let homeAssistantDeviceVisibilityKey = "home_assistant_device_visibility_v1"
        public static let homeAssistantDevicePresentationKey = "home_assistant_device_presentation_v1"
        public static let homeAssistantAccessoryPresentationKey = "home_assistant_accessory_presentation_v2"
        public static let homeAssistantAccessoryGroupingKey = "home_assistant_accessory_grouping_v1"
        public static let homeAssistantTranslationCatalogKey = "home_assistant_translation_catalog_v1"
        public static let homeAssistantDashboardLayoutKey = "home_assistant_dashboard_layout_v1"
        public static let devBarActiveUserIDKey = "devbar_active_user_id_v1"
        public static let devBarProfileCachePrefix = "devbar_profile_cache_v1_"
    }

    public enum Account {
        public static let appleLoginPath = "/api/devbar/auth/apple"
        public static let logoutPath = "/api/devbar/auth/logout"
        public static let mePath = "/api/devbar/me"
        public static let profilePath = "/api/devbar/me/profile"
        public static let deviceBindingPath = "/api/devbar/me/device-binding"
        public static let messagesPath = "/api/devbar/messages"
        public static let unreadCountPath = "/api/devbar/messages/unread-count"
        public static let markAllReadPath = "/api/devbar/messages/read-all"

        public static func messageReadPath(messageId: String) -> String {
            "\(messagesPath)/by-id/\(messageId)/read"
        }
    }

    public enum HomeAssistant {
        public static let snapshotCacheSchemaVersion = 1
        public static let snapshotCacheDirectoryName = "HomeAssistant"
        public static let snapshotCacheMaximumBytes = 10 * 1_024 * 1_024
    }
}
