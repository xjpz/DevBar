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

    public enum AppGroup {
        public static let groupID = "group.cc.xjpz.DevBar"
        public static let sharedDataKey = "widget_shared_data"
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
        public static let liveActivitySettingsKey = "live_activity_settings"
    }
}
