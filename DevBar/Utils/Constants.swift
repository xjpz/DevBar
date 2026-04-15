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
    }

    enum Defaults {
        static let refreshIntervalKey = "refresh_interval"
        static let defaultRefreshInterval: TimeInterval = 300 // 5 minutes
        static let menuBarIconKey = "menu_bar_icon"
        static let defaultMenuBarIcon = "AppIcon"
        static let hideFromDockKey = "hide_from_dock"
    }

    enum Icons {
        static let availableIcons: [(String, String)] = [
            ("chart.bar.xaxis", "横轴"),
            ("fish.fill", "鱼"),
            ("sparkles", "星星"),
            ("align.vertical.bottom.fill", "竖线"),
            ("chart.bar.fill", "柱状图"),
            ("dog.fill", "狗"),
            ("tortoise.fill", "乌龟"),
            ("hare.fill", "兔子"),
            ("cat.fill", "猫"),
            ("bird.fill", "鸟"),
        ]

        /// Returns true if the icon name refers to a custom asset image (not a system SF Symbol)
        static func isCustomIcon(_ name: String) -> Bool {
            !availableIcons.contains { $0.0 == name }
        }
    }

    enum UI {
        static let popoverWidth: CGFloat = 320
        static let popoverHeight: CGFloat = 420
    }
}
