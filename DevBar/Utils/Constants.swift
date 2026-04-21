// Constants.swift
// DevBar

import Foundation

enum Constants {
    enum API {
        static let baseURL = "https://bigmodel.cn"
        static let loginURL = "\(baseURL)/login"
        static let subscriptionListURL = "\(baseURL)/api/biz/subscription/list"
        static let quotaLimitURL = "\(baseURL)/api/monitor/usage/quota/limit"
    }

    enum Keychain {
        static let service = "cc.xjpz.DevBar"
        static let tokenKey = "authorization_token"
        static let cookieKey = "cookie_string"
        static let openAIAccessTokenKey = "openai_access_token"
    }

    enum OpenAI {
        static let usageURL = "https://chatgpt.com/backend-api/wham/usage"
        static let accountIdKey = "openai_account_id"
    }

    enum Defaults {
        static let refreshIntervalKey = "refresh_interval"
        static let defaultRefreshInterval: TimeInterval = 300 // 5 minutes
        static let menuBarIconKey = "menu_bar_icon"
        static let defaultMenuBarIcon = "sparkles"
        static let hideFromDockKey = "hide_from_dock"
        static let launchAtLoginKey = "launch_at_login"
        static let lastUpdateCheckKey = "last_update_check"
        static let skippedVersionKey = "skipped_version"

        // Notification settings
        static let notificationLowQuotaEnabledKey = "notification_low_quota_enabled"
        static let notificationLowQuotaThresholdKey = "notification_low_quota_threshold"
        static let defaultLowQuotaThreshold: Double = 20 // 20%
        static let notificationExhaustedEnabledKey = "notification_exhausted_enabled"
        static let notificationResetEnabledKey = "notification_reset_enabled"

        // Notification throttling
        static let lastLowQuotaNotificationTimeKey = "last_low_quota_notification_time"
        static let lastExhaustedNotificationTimeKey = "last_exhausted_notification_time"
        static let lastResetNotificationTimeKey = "last_reset_notification_time"
        static let lowQuotaNotificationInterval: TimeInterval = 1800 // 30 minutes

        // Account configs
        static let accountConfigsKey = "account_configs"
    }

    enum Update {
        static let owner = "xjpz"
        static let repo = "DevBar"
        static let releasesURL = "https://api.github.com/repos/\(owner)/\(repo)/releases/latest"
        static let releasesPageURL = "https://github.com/\(owner)/\(repo)/releases"
        static let checkInterval: TimeInterval = 86400 // 24 hours
        static let launchCheckDelay: TimeInterval = 5
    }

    enum Icons {
        static let availableIcons: [(String, String)] = [
            ("sparkles", String(localized: "icon_sparkles")),
            ("chart.bar.xaxis", String(localized: "icon_chart")),
            ("align.vertical.bottom.fill", String(localized: "icon_bars")),
            ("chart.bar.fill", String(localized: "icon_bar_fill")),
            ("fish.fill", String(localized: "icon_fish")),
            ("dog.fill", String(localized: "icon_dog")),
            ("tortoise.fill", String(localized: "icon_tortoise")),
            ("hare.fill", String(localized: "icon_hare")),
            ("cat.fill", String(localized: "icon_cat")),
            ("bird.fill", String(localized: "icon_bird")),
        ]

        /// Returns true if the icon name refers to a custom asset image (not a system SF Symbol)
        static func isCustomIcon(_ name: String) -> Bool {
            !availableIcons.contains { $0.0 == name }
        }
    }

    enum AppGroup {
        static let groupID = "group.cc.xjpz.DevBar"
        static let sharedDataKey = "widget_shared_data"
        static func sharedDataKey(for provider: String) -> String {
            "widget_shared_data_\(provider)"
        }
    }

    enum UI {
        static let popoverWidth: CGFloat = 320
        static let popoverHeight: CGFloat = 420
    }
}
