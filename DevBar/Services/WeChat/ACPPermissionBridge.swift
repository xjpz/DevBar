// ACPPermissionBridge.swift
// DevBar

import Foundation

@MainActor
final class ACPPermissionBridge: ACPPermissionHandling, @unchecked Sendable {
    private let agent: WeChatAgentRouter.AgentConfig
    private let approvalCoordinator: WeChatApprovalCoordinator
    private let approvalNotifier: ((String) async -> Void)?

    init(
        agent: WeChatAgentRouter.AgentConfig,
        approvalCoordinator: WeChatApprovalCoordinator,
        approvalNotifier: ((String) async -> Void)?
    ) {
        self.agent = agent
        self.approvalCoordinator = approvalCoordinator
        self.approvalNotifier = approvalNotifier
    }

    func handlePermissionRequest(_ request: ACPPermissionRequest) async -> ACPPermissionDecision {
        let risk = assessRisk(for: request)

        switch agent.effectiveApprovalPolicy {
        case .trusted:
            if let allowOptionID = request.allowOptionID {
                return .selected(optionId: allowOptionID)
            }
            return .deny
        case .never:
            return .deny
        case .macConfirm, .wechatConfirm:
            break
        }

        let approval = approvalCoordinator.makeRequest(
            agentName: agent.name,
            userID: request.userID,
            message: request.message,
            command: request.command ?? request.toolName ?? "codex app-server",
            arguments: request.summary.isEmpty ? [] : [request.summary],
            cwd: request.cwd,
            risk: risk,
            allowsWechatApproval: agent.allowsWechatApproval(for: risk),
            timeoutSeconds: agent.effectiveApprovalTimeoutSeconds,
            source: "Codex app-server",
            toolName: request.toolName,
            operationSummary: request.summary
        )

        let approvalTask = Task { @MainActor in
            await approvalCoordinator.requestApproval(approval)
        }
        await approvalNotifier?(approval.wechatPrompt)

        guard await approvalTask.value else {
            return .deny
        }
        return .selected(optionId: request.allowOptionID ?? "accept")
    }

    private func assessRisk(for request: ACPPermissionRequest) -> WeChatApprovalRequest.Risk {
        let text = [
            request.toolName,
            request.command,
            request.summary,
        ]
            .compactMap { $0 }
            .joined(separator: " ")
            .lowercased()

        let highRiskHints = [
            "rm ", "sudo", "curl ", "wget ", "chmod", "chown",
            "brew ", "npm ", "pnpm ", "yarn ", "pip ", "gem ",
            "delete", "remove", "install", "push", "reset", "checkout",
            "删除", "移除", "安装", "提交", "推送", "重置",
        ]
        if highRiskHints.contains(where: { text.contains($0) }) {
            return .high
        }

        let mediumRiskHints = [
            "write", "edit", "patch", "apply_patch", "shell", "bash",
            "test", "xcodebuild", "swift test", "git commit",
            "写", "修改", "运行", "执行", "测试",
        ]
        if mediumRiskHints.contains(where: { text.contains($0) }) {
            return .medium
        }

        return .low
    }
}
