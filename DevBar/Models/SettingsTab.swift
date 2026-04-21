// SettingsTab.swift
// DevBar

import Foundation

enum SettingsTab: String, CaseIterable {
    case general
    case notifications
    case accounts
    case about

    var localizedName: String {
        switch self {
        case .general: return String(localized: "tab_general")
        case .notifications: return String(localized: "tab_notifications")
        case .accounts: return String(localized: "tab_accounts")
        case .about: return String(localized: "tab_about")
        }
    }

    var icon: String {
        switch self {
        case .general: return "gear"
        case .notifications: return "bell"
        case .accounts: return "person.2"
        case .about: return "info.circle"
        }
    }
}
