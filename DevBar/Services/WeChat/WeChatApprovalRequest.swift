// WeChatApprovalRequest.swift
// DevBar

import Foundation

struct WeChatApprovalRequest: Identifiable, Codable, Sendable {
    enum Status: String, Codable, Sendable {
        case pending
        case approved
        case denied
        case expired
    }

    enum Risk: String, Codable, Sendable {
        case low
        case medium
        case high

        var displayName: String {
            switch self {
            case .low: return "low"
            case .medium: return "medium"
            case .high: return "high"
            }
        }
    }

    let id: String
    let agentName: String
    let userID: String
    let message: String
    let command: String
    let arguments: [String]
    let cwd: String?
    let risk: Risk
    let createdAt: Date
    let expiresAt: Date
    var status: Status

    var isExpired: Bool {
        Date() >= expiresAt
    }

    var commandSummary: String {
        ([command] + arguments).joined(separator: " ")
    }

    var wechatPrompt: String {
        """
        需要授权 \(id)：
        agent=\(agentName)
        风险=\(risk.displayName)
        目录=\(cwd ?? "未设置")

        请在 Mac 端 DevBar 确认。
        回复 N \(id) 可取消。
        """
    }
}
