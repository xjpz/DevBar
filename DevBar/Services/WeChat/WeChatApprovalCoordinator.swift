// WeChatApprovalCoordinator.swift
// DevBar

import Foundation
import Combine
import UserNotifications

@MainActor
final class WeChatApprovalCoordinator: ObservableObject {
    @Published private(set) var pendingRequests: [WeChatApprovalRequest] = []

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
        timeoutSeconds: Int
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
        if source == .wechat, approved, request.risk == .high {
            return "授权 \(id) 风险较高，请在 Mac 端 DevBar 确认。"
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

    private func expire(id: String) {
        complete(id: id, approved: false, status: .expired)
    }

    private func complete(id: String, approved: Bool, status: WeChatApprovalRequest.Status) {
        timeoutTasks[id]?.cancel()
        timeoutTasks[id] = nil

        if let index = pendingRequests.firstIndex(where: { $0.id == id }) {
            pendingRequests[index].status = status
            pendingRequests.remove(at: index)
        }

        let continuation = continuations.removeValue(forKey: id)
        continuation?.resume(returning: approved)
    }

    private func sendNotification(for request: WeChatApprovalRequest) {
        let content = UNMutableNotificationContent()
        content.title = "DevBar 请求授权"
        content.body = "\(request.agentName) 想执行 \(request.risk.displayName) 风险 CLI 操作"
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
