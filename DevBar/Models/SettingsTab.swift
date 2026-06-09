// SettingsTab.swift
// DevBar

import Foundation
import DevBarCore

enum SettingsTab: String, CaseIterable {
    case general
    case notifications
    case finder
    case accounts
    case weChat

    static var visibleCases: [SettingsTab] {
        allCases.filter { tab in
            switch tab {
            case .notifications:
                return DevBarCoreConstants.Features.notificationRemindersEnabled
            default:
                return true
            }
        }
    }

    var localizedName: String {
        switch self {
        case .general: return String(localized: "tab_general")
        case .notifications: return String(localized: "tab_notifications")
        case .finder: return String(localized: "tab_finder")
        case .accounts: return String(localized: "tab_accounts")
        case .weChat: return String(localized: "tab_wechat")
        }
    }

    var icon: String {
        switch self {
        case .general: return "gear"
        case .notifications: return "bell"
        case .finder: return "folder"
        case .accounts: return "person.badge.key"
        case .weChat: return "rectangle.connected.to.line.below"
        }
    }
}
