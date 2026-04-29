// WeChatAgentDetector.swift
// DevBar

import Combine
import Foundation

@MainActor
final class WeChatAgentDetector: ObservableObject {
    @Published var isScanning = false

    /// Detect available agent binaries and return configs for those not already configured.
    func scan(existingAgents: [WeChatAgentRouter.AgentConfig]) async -> [WeChatAgentRouter.AgentConfig] {
        isScanning = true
        defer { isScanning = false }

        let pathEnv = WeChatShellEnvironment.buildPATH()
        let existingNames = Set(existingAgents.map(\.name))

        // Find all candidate binaries
        var foundPaths: [String: String] = [:] // binaryName -> fullPath

        await withTaskGroup(of: (String, String?).self) { group in
            let uniqueBinaries = Set(WeChatAgentRouter.AgentConfig.detectionCandidates.map(\.binaryName))
            let pathCopy = pathEnv
            for binary in uniqueBinaries {
                group.addTask {
                    let path = Self.whichNonisolated(binary: binary, pathEnv: pathCopy)
                    return (binary, path)
                }
            }
            for await (binary, path) in group {
                if let path { foundPaths[binary] = path }
            }
        }

        // Select best candidate per agent name (lowest priority = ACP preferred)
        var bestCandidates: [String: WeChatAgentRouter.AgentConfig.DetectionCandidate] = [:]
        for candidate in WeChatAgentRouter.AgentConfig.detectionCandidates {
            guard foundPaths[candidate.binaryName] != nil else { continue }
            if let existing = bestCandidates[candidate.agentName] {
                if candidate.priority < existing.priority {
                    bestCandidates[candidate.agentName] = candidate
                }
            } else {
                bestCandidates[candidate.agentName] = candidate
            }
        }

        // Build configs, skipping already-configured agents
        var configs: [WeChatAgentRouter.AgentConfig] = []
        for (agentName, candidate) in bestCandidates.sorted(by: { $0.key < $1.key }) {
            guard !existingNames.contains(agentName) else { continue }
            let fullPath = foundPaths[candidate.binaryName]!

            let config = WeChatAgentRouter.AgentConfig(
                name: agentName,
                type: candidate.type,
                command: fullPath,
                args: candidate.args,
                cwd: nil,
                env: nil,
                model: nil,
                systemPrompt: nil,
                aliases: nil,
                endpoint: nil,
                apiKey: nil,
                headers: nil,
                maxHistory: nil,
                approvalPolicy: nil,
                approvalTimeoutSeconds: nil,
                allowWechatConfirmForLowRisk: nil
            )
            configs.append(config)
        }
        return configs
    }

    /// Nonisolated which — safe to call from any isolation domain
    private nonisolated static func whichNonisolated(binary: String, pathEnv: String) -> String? {
        let directories = pathEnv.split(separator: ":")
        for dir in directories {
            let fullPath = "\(dir)/\(binary)"
            if FileManager.default.isExecutableFile(atPath: fullPath) {
                return fullPath
            }
        }
        return nil
    }
}
