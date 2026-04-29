// WeChatViewModel.swift
// DevBar

import Combine
import Foundation
import SwiftUI

@MainActor
final class WeChatViewModel: ObservableObject {
    @Published var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: Constants.Defaults.wechatEnabledKey)
            if isEnabled {
                startIfConfigured()
            } else {
                stop()
            }
        }
    }

    @Published var connectionState: ConnectionState = .disconnected

    enum ConnectionState {
        case disconnected
        case connecting
        case connected
        case error(String)
    }

    let authService = WeChatAuthService()
    let messageService = WeChatMessageService()
    let agentRouter = WeChatAgentRouter()
    let agentDetector = WeChatAgentDetector()

    var defaultAgent: String {
        get { agentRouter.defaultAgent }
        set { agentRouter.defaultAgent = newValue }
    }

    private var healthTask: Task<Void, Never>?

    init() {
        self.isEnabled = UserDefaults.standard.bool(forKey: Constants.Defaults.wechatEnabledKey)
    }

    func setup() {
        authService.loadAccounts()
        agentRouter.loadFromWeClawConfig()

        // Auto-detect agents if none configured
        if agentRouter.agents.isEmpty {
            Task {
                let detected = await agentDetector.scan(existingAgents: agentRouter.agents)
                for config in detected {
                    agentRouter.agents.append(config)
                }
                if agentRouter.defaultAgent.isEmpty, let first = detected.first {
                    agentRouter.defaultAgent = first.name
                }
                if !detected.isEmpty {
                    agentRouter.saveToWeClawConfig()
                }
            }
        }

        if isEnabled && !authService.accounts.isEmpty {
            startIfConfigured()
        }
    }

    func startIfConfigured() {
        guard !messageService.isRunning else {
            connectionState = .connected
            return
        }

        let accounts = authService.accounts
        guard !accounts.isEmpty else {
            connectionState = .disconnected
            return
        }

        connectionState = .connecting
        messageService.start(accounts: accounts, router: agentRouter)
        startHealthCheck()

        Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            if messageService.isRunning {
                connectionState = .connected
            }
        }
    }

    func stop() {
        agentRouter.stopAllClients()
        messageService.stop()
        healthTask?.cancel()
        healthTask = nil
        connectionState = .disconnected
    }

    func restart() {
        stop()
        startIfConfigured()
    }

    /// Manually trigger agent detection
    func detectAgents() async {
        let detected = await agentDetector.scan(existingAgents: agentRouter.agents)
        for config in detected {
            agentRouter.agents.append(config)
        }
        if agentRouter.defaultAgent.isEmpty, let first = detected.first {
            agentRouter.defaultAgent = first.name
        }
        if !detected.isEmpty {
            agentRouter.saveToWeClawConfig()
        }
    }

    var accountCount: Int { authService.accounts.count }
    var hasAccounts: Bool { !authService.accounts.isEmpty }

    // MARK: - Health Check

    private func startHealthCheck() {
        healthTask?.cancel()
        healthTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 30_000_000_000)
                guard let self, self.isEnabled else { return }

                if !self.messageService.isRunning {
                    self.connectionState = .disconnected
                    self.startIfConfigured()
                }
            }
        }
    }
}

// MARK: - Constants Extension

extension Constants.Defaults {
    static let wechatEnabledKey = "wechat_enabled"
}
