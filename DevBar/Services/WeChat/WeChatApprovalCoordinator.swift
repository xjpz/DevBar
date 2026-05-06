// WeChatApprovalCoordinator.swift
// DevBar

import Foundation
import Combine
import UserNotifications

@MainActor
final class WeChatApprovalCoordinator: ObservableObject {
    @Published private(set) var pendingRequests: [WeChatApprovalRequest] = []
    @Published private(set) var recentRequests: [WeChatApprovalRequest] = []

    private var continuations: [String: CheckedContinuation<Bool, Never>] = [:]
    private var timeoutTasks: [String: Task<Void, Never>] = [:]
    private let notificationCenter = UNUserNotificationCenter.current()

    func makeRequest(
        agentName: String,
        userID: String,
        message: String,
        command: String,
        arguments: [String],
        cwd: String?,
        risk: WeChatApprovalRequest.Risk,
        allowsWechatApproval: Bool,
        timeoutSeconds: Int,
        source: String? = nil,
        toolName: String? = nil,
        operationSummary: String? = nil
    ) -> WeChatApprovalRequest {
        let id = Self.makeID()
        let now = Date()
        return WeChatApprovalRequest(
            id: id,
            agentName: agentName,
            userID: userID,
            message: message,
            command: command,
            arguments: arguments,
            cwd: cwd,
            risk: risk,
            allowsWechatApproval: allowsWechatApproval,
            source: source,
            toolName: toolName,
            operationSummary: operationSummary,
            createdAt: now,
            expiresAt: now.addingTimeInterval(TimeInterval(timeoutSeconds)),
            status: .pending
        )
    }

    func requestApproval(_ request: WeChatApprovalRequest) async -> Bool {
        pendingRequests.append(request)
        if !request.allowsWechatApproval {
            sendNotification(for: request)
        }

        let timeoutSeconds = max(1, Int(request.expiresAt.timeIntervalSince(request.createdAt)))
        timeoutTasks[request.id]?.cancel()
        timeoutTasks[request.id] = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(timeoutSeconds) * 1_000_000_000)
            self?.expire(id: request.id)
        }

        return await withCheckedContinuation { continuation in
            continuations[request.id] = continuation
        }
    }

    @discardableResult
    func resolve(id: String, userID: String, approved: Bool, source: ApprovalSource) -> String? {
        guard let request = pendingRequests.first(where: { $0.id.caseInsensitiveCompare(id) == .orderedSame }) else {
            return nil
        }
        guard request.userID == userID else {
            return "授权 \(id) 不属于当前微信用户。"
        }
        guard request.status == .pending else {
            return "授权 \(id) 已处理。"
        }
        if source == .wechat, approved, !request.allowsWechatApproval {
            return "授权 \(id) 需要在 Mac 端 DevBar 确认。"
        }

        complete(id: request.id, approved: approved, status: approved ? .approved : .denied)
        return approved ? "已允许授权 \(request.id)，继续执行。" : "已拒绝授权 \(request.id)，任务未执行。"
    }

    func expirePendingRequests() {
        for request in pendingRequests where request.status == .pending && request.isExpired {
            expire(id: request.id)
        }
    }

    func pendingRequest(id: String, userID: String) -> WeChatApprovalRequest? {
        pendingRequests.first {
            $0.id.caseInsensitiveCompare(id) == .orderedSame && $0.userID == userID && $0.status == .pending
        }
    }

    func pendingSummary(userID: String) -> String {
        let requests = pendingRequests.filter { $0.userID == userID && $0.status == .pending }
        guard !requests.isEmpty else {
            return "[DevBar] 当前没有待授权请求。"
        }

        var lines = ["[DevBar] 待授权请求:"]
        for request in requests {
            lines.append("- \(request.id) \(request.agentName) \(request.risk.displayName)")
            if let source = request.source { lines.append("  来源: \(source)") }
            if let toolName = request.toolName { lines.append("  工具: \(toolName)") }
            if let operationSummary = request.operationSummary { lines.append("  操作: \(operationSummary)") }
            lines.append("  回复 N \(request.id) 可取消\(request.allowsWechatApproval ? "，回复 Y \(request.id) 可允许" : "")")
        }
        return lines.joined(separator: "\n")
    }

    func cancelPending(id: String, userID: String) -> String {
        guard let request = pendingRequest(id: id, userID: userID) else {
            return "未找到待处理授权 \(id)。"
        }
        complete(id: request.id, approved: false, status: .denied)
        return "已取消授权 \(request.id)，任务未执行。"
    }

    func cancelPending(agentName: String) {
        let ids = pendingRequests
            .filter { $0.agentName == agentName && $0.status == .pending }
            .map(\.id)
        for id in ids {
            complete(id: id, approved: false, status: .denied)
        }
    }

    private func expire(id: String) {
        complete(id: id, approved: false, status: .expired)
    }

    private func complete(id: String, approved: Bool, status: WeChatApprovalRequest.Status) {
        timeoutTasks[id]?.cancel()
        timeoutTasks[id] = nil

        if let index = pendingRequests.firstIndex(where: { $0.id == id }) {
            var request = pendingRequests[index]
            request.status = status
            pendingRequests.remove(at: index)
            recentRequests.insert(request, at: 0)
            if recentRequests.count > 20 {
                recentRequests.removeLast(recentRequests.count - 20)
            }
        }

        let continuation = continuations.removeValue(forKey: id)
        continuation?.resume(returning: approved)
    }

    private func sendNotification(for request: WeChatApprovalRequest) {
        let content = UNMutableNotificationContent()
        content.title = "DevBar 请求授权"
        let source = request.source ?? "远程 Agent"
        content.body = "\(request.agentName) 通过 \(source) 请求 \(request.risk.displayName) 风险授权"
        content.sound = .default

        let notification = UNNotificationRequest(
            identifier: "wechat-approval-\(request.id)",
            content: content,
            trigger: nil
        )
        notificationCenter.add(notification) { error in
            if let error {
                print("[WeChat:Approval] notification error: \(error)")
            }
        }
    }

    private static func makeID() -> String {
        let alphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        return String((0..<4).compactMap { _ in alphabet.randomElement() })
    }
}

extension WeChatApprovalCoordinator {
    enum ApprovalSource: Sendable {
        case mac
        case wechat
    }
}
