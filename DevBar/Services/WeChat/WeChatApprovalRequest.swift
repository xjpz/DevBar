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
    let allowsWechatApproval: Bool
    let source: String?
    let toolName: String?
    let operationSummary: String?
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
        let instruction = allowsWechatApproval
            ? "回复 Y \(id) 可允许，回复 N \(id) 可取消。"
            : "请在 Mac 端 DevBar 确认。\n回复 N \(id) 可取消。"
        var lines = [
            "需要授权 \(id)：",
            "agent=\(agentName)",
        ]
        if let source { lines.append("来源=\(source)") }
        lines.append("风险=\(risk.displayName)")
        lines.append("目录=\(cwd ?? "未设置")")
        if let toolName { lines.append("工具=\(toolName)") }
        if let operationSummary { lines.append("操作=\(operationSummary)") }
        lines.append("")
        lines.append(instruction)
        return lines.joined(separator: "\n")
    }
}
