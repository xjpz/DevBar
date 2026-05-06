// ACPPermissionRequest.swift
// DevBar

import Foundation

struct ACPPermissionRequest: Identifiable, Sendable {
    struct Option: Sendable {
        enum Kind: Sendable {
            case allow
            case deny
            case unknown
        }

        let id: String
        let kind: Kind
        let label: String
    }

    let id: String
    let agentName: String
    let userID: String
    let message: String
    let cwd: String?
    let toolName: String?
    let command: String?
    let summary: String
    let rawParams: AnyJSON
    let options: [Option]

    nonisolated var denyOptionID: String? {
        options.first {
            if case .deny = $0.kind { return true }
            return false
        }?.id
            ?? options.first { $0.id.localizedCaseInsensitiveContains("deny") }?.id
    }

    nonisolated var allowOptionID: String? {
        options.first {
            if case .allow = $0.kind { return true }
            return false
        }?.id
            ?? options.first { $0.id.localizedCaseInsensitiveContains("allow") }?.id
            ?? options.first {
                if case .deny = $0.kind { return false }
                return true
            }?.id
    }

    nonisolated static func parse(
        rawObject: [String: Any],
        agentName: String,
        userID: String,
        message: String,
        cwd: String?
    ) -> ACPPermissionRequest? {
        guard let params = rawObject["params"] as? [String: Any] else { return nil }
        let requestID = stringValue(rawObject["id"]) ?? UUID().uuidString
        let options = parseOptions(from: params)
        let method = stringValue(rawObject["method"])
        let toolName = firstString(in: params, keys: ["toolName", "tool_name", "tool", "kind", "type"])
            ?? toolName(from: method)
        let command = extractCommand(from: params)
        let requestCwd = firstString(in: params, keys: ["cwd", "grantRoot"]) ?? cwd
        let summary = extractSummary(from: params, toolName: toolName, command: command)

        return ACPPermissionRequest(
            id: requestID,
            agentName: agentName,
            userID: userID,
            message: message,
            cwd: requestCwd,
            toolName: toolName,
            command: command,
            summary: summary,
            rawParams: AnyJSON.dictionary(params),
            options: options
        )
    }

    nonisolated private static func parseOptions(from params: [String: Any]) -> [Option] {
        guard let rawOptions = params["options"] as? [[String: Any]] else { return [] }
        return rawOptions.compactMap { raw in
            let id = firstString(in: raw, keys: ["optionId", "id", "value"])
            guard let id, !id.isEmpty else { return nil }
            let label = firstString(in: raw, keys: ["label", "title", "name", "kind"]) ?? id
            let discriminator = [
                firstString(in: raw, keys: ["kind"]),
                firstString(in: raw, keys: ["optionId", "id", "value"]),
                label,
            ]
                .compactMap { $0 }
                .joined(separator: " ")
                .lowercased()
            let kind: Option.Kind
            if discriminator.contains("deny") || discriminator.contains("reject") || discriminator.contains("disallow") {
                kind = .deny
            } else if discriminator.contains("allow") || discriminator.contains("approve") || discriminator.contains("accept") {
                kind = .allow
            } else {
                kind = .unknown
            }
            return Option(id: id, kind: kind, label: label)
        }
    }

    nonisolated private static func extractSummary(
        from params: [String: Any],
        toolName: String?,
        command: String?
    ) -> String {
        if let explicit = firstString(in: params, keys: ["summary", "description", "message", "reason"]) {
            return explicit
        }
        if let command, !command.isEmpty {
            return command
        }
        if let toolName, !toolName.isEmpty {
            return toolName
        }
        return "Codex 请求执行需要授权的操作"
    }

    nonisolated private static func extractCommand(from value: Any) -> String? {
        if let dict = value as? [String: Any] {
            if let command = firstString(in: dict, keys: ["command", "cmd", "shellCommand"]) {
                return command
            }
            if let command = dict["command"] as? [String], !command.isEmpty {
                return command.joined(separator: " ")
            }
            if let arguments = dict["arguments"] as? [String], !arguments.isEmpty {
                return arguments.joined(separator: " ")
            }
            for key in ["toolCall", "tool_call", "invocation", "request", "input"] {
                if let nested = dict[key], let command = extractCommand(from: nested) {
                    return command
                }
            }
            for nested in dict.values {
                if let command = extractCommand(from: nested) {
                    return command
                }
            }
        }
        if let array = value as? [Any] {
            for nested in array {
                if let command = extractCommand(from: nested) {
                    return command
                }
            }
        }
        return nil
    }

    nonisolated private static func toolName(from method: String?) -> String? {
        switch method {
        case "item/commandExecution/requestApproval", "execCommandApproval":
            return "shell"
        case "item/fileChange/requestApproval", "applyPatchApproval":
            return "file change"
        case "item/permissions/requestApproval":
            return "permissions"
        default:
            return method
        }
    }

    nonisolated private static func firstString(in dict: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = stringValue(dict[key]), !value.isEmpty {
                return value
            }
        }
        return nil
    }

    nonisolated private static func stringValue(_ value: Any?) -> String? {
        switch value {
        case let value as String:
            return value
        case let value as Int:
            return String(value)
        case let value as Int64:
            return String(value)
        case let value as Double:
            return String(value)
        default:
            return nil
        }
    }
}

enum ACPPermissionDecision: Sendable {
    case selected(optionId: String)
    case deny
}

@MainActor
protocol ACPPermissionHandling: AnyObject, Sendable {
    func handlePermissionRequest(_ request: ACPPermissionRequest) async -> ACPPermissionDecision
}
