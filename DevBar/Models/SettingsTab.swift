// SettingsTab.swift
// DevBar

import Foundation

enum SettingsTab: String, CaseIterable {
    case general = "通用"
    case notifications = "通知"
    case about = "关于"

    var icon: String {
        switch self {
        case .general: return "gear"
        case .notifications: return "bell"
        case .about: return "info.circle"
        }
    }
}
