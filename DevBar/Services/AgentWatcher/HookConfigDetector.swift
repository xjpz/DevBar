import Foundation
import Combine

// MARK: - Hook Config Status

enum HookConfigStatus {
    case detected
    case notDetected
    case error(String)

    var isConfigured: Bool {
        if case .detected = self { return true }
        return false
    }

    var displayName: String {
        switch self {
        case .detected: return "✅ \(String(localized: "已检测到"))"
        case .notDetected: return "⚠️ \(String(localized: "未检测到"))"
        case .error(let msg): return "❌ \(msg)"
        }
    }
}

// MARK: - Hook Config Detector

class HookConfigDetector {
    private static let claudePermissionCommand = "curl -s -X POST http://127.0.0.1:49321/agent/claude/permission-request -H 'Content-Type: application/json' -d @-"
    private static let claudeNotificationCommand = "curl -s -X POST http://127.0.0.1:49321/agent/claude/notification -H 'Content-Type: application/json' -d @-"
    private static let claudeStopCommand = "curl -s -X POST http://127.0.0.1:49321/agent/claude/stop -H 'Content-Type: application/json' -d @-"
    private static let claudePreToolUseCommand = "curl -s -X POST http://127.0.0.1:49321/agent/claude/pre-tool-use -H 'Content-Type: application/json' -d @-"
    private static let codexPermissionCommand = "curl -s -X POST http://127.0.0.1:49321/agent/codex/permission-request -H 'Content-Type: application/json' -d @-"
    private static let codexStopCommand = "curl -s -X POST http://127.0.0.1:49321/agent/codex/stop -H 'Content-Type: application/json' -d @-"

    private let claudeConfigPath: String
    private let codexConfigPath: String
    private let codexHooksPath: String

    init() {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        claudeConfigPath = "\(homeDir)/.claude/settings.json"
        codexConfigPath = "\(homeDir)/.codex/config.toml"
        codexHooksPath = "\(homeDir)/.codex/hooks.json"
    }

    // MARK: - Detection

    func detectClaudeConfig() -> HookConfigStatus {
        let fileManager = FileManager.default

        guard fileManager.fileExists(atPath: claudeConfigPath) else {
            return .notDetected
        }

        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: claudeConfigPath))
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

            guard let hooks = json?["hooks"] as? [String: Any] else {
                return .notDetected
            }

            if Self.containsHook(command: Self.claudePermissionCommand, eventName: "PermissionRequest", in: hooks) ||
                Self.containsHook(command: Self.claudeNotificationCommand, eventName: "Notification", in: hooks) ||
                Self.containsHook(command: Self.claudeStopCommand, eventName: "Stop", in: hooks) {
                return .detected
            } else {
                return .notDetected
            }
        } catch {
            return .error(String(format: String(localized: "读取配置失败: %@"), error.localizedDescription))
        }
    }

    func detectCodexConfig() -> HookConfigStatus {
        let fileManager = FileManager.default

        // 优先检查 hooks.json
        if fileManager.fileExists(atPath: codexHooksPath) {
            do {
                let data = try Data(contentsOf: URL(fileURLWithPath: codexHooksPath))
                let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

                if let hooks = json?["hooks"] as? [String: Any],
                   Self.containsHook(command: Self.codexPermissionCommand, eventName: "PermissionRequest", in: hooks) {
                    return .detected
                }
            } catch {
                return .error(String(format: String(localized: "读取 hooks.json 失败: %@"), error.localizedDescription))
            }
        }

        // 检查 config.toml
        if fileManager.fileExists(atPath: codexConfigPath) {
            do {
                let content = try String(contentsOfFile: codexConfigPath, encoding: .utf8)
                if content.contains(Self.codexPermissionCommand) {
                    return .detected
                }
            } catch {
                return .error(String(format: String(localized: "读取 config.toml 失败: %@"), error.localizedDescription))
            }
        }

        return .notDetected
    }

    // MARK: - Config Generation

    func generateClaudeConfig() -> String {
        return """
        {
          "hooks": {
            "PreToolUse": [
              {
                "matcher": "",
                "hooks": [
                  {
                    "type": "command",
                    "command": "curl -s -X POST http://127.0.0.1:49321/agent/claude/pre-tool-use -H 'Content-Type: application/json' -d @-"
                  }
                ]
              }
            ],
            "PermissionRequest": [
              {
                "matcher": "",
                "hooks": [
                  {
                    "type": "command",
                    "command": "curl -s -X POST http://127.0.0.1:49321/agent/claude/permission-request -H 'Content-Type: application/json' -d @-"
                  }
                ]
              }
            ],
            "Notification": [
              {
                "matcher": "",
                "hooks": [
                  {
                    "type": "command",
                    "command": "curl -s -X POST http://127.0.0.1:49321/agent/claude/notification -H 'Content-Type: application/json' -d @-"
                  }
                ]
              }
            ],
            "Stop": [
              {
                "matcher": "",
                "hooks": [
                  {
                    "type": "command",
                    "command": "curl -s -X POST http://127.0.0.1:49321/agent/claude/stop -H 'Content-Type: application/json' -d @-"
                  }
                ]
              }
            ]
          }
        }
        """
    }

    func generateCodexHooksConfig() -> String {
        return """
        {
          "hooks": {
            "PermissionRequest": [
              {
                "matcher": "",
                "hooks": [
                  {
                    "type": "command",
                    "command": "curl -s -X POST http://127.0.0.1:49321/agent/codex/permission-request -H 'Content-Type: application/json' -d @-",
                    "statusMessage": "Notifying DevBar"
                  }
                ]
              }
            ],
            "Stop": [
              {
                "matcher": "",
                "hooks": [
                  {
                    "type": "command",
                    "command": "curl -s -X POST http://127.0.0.1:49321/agent/codex/stop -H 'Content-Type: application/json' -d @-",
                    "statusMessage": "Notifying DevBar"
                  }
                ]
              }
            ]
          }
        }
        """
    }

    // MARK: - Config Installation

    func installClaudeConfig() -> Bool {
        // 读取现有配置并合并 hooks，而不是覆盖
        var existingConfig: [String: Any] = [:]
        if let data = try? Data(contentsOf: URL(fileURLWithPath: claudeConfigPath)),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            existingConfig = json
        }

        return writeJSONConfig(to: claudeConfigPath, content: Self.mergingClaudeHooks(into: existingConfig))
    }

    func installCodexConfig() -> Bool {
        // 读取现有 hooks.json 并合并，避免覆盖用户已有的其他 hooks
        var existingConfig: [String: Any] = [:]
        if let data = try? Data(contentsOf: URL(fileURLWithPath: codexHooksPath)),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            existingConfig = json
        }

        return writeJSONConfig(to: codexHooksPath, content: Self.mergingCodexHooks(into: existingConfig))
    }

    static func mergingClaudeHooks(into config: [String: Any]) -> [String: Any] {
        var config = config
        var hooks = config["hooks"] as? [String: Any] ?? [:]
        appendHook(command: claudePreToolUseCommand, eventName: "PreToolUse", to: &hooks)
        appendHook(command: claudePermissionCommand, eventName: "PermissionRequest", to: &hooks)
        appendHook(command: claudeNotificationCommand, eventName: "Notification", to: &hooks)
        appendHook(command: claudeStopCommand, eventName: "Stop", to: &hooks)
        config["hooks"] = hooks
        return config
    }

    static func mergingCodexHooks(into config: [String: Any]) -> [String: Any] {
        var config = config
        var hooks = config["hooks"] as? [String: Any] ?? [:]
        appendHook(command: codexPermissionCommand, eventName: "PermissionRequest", to: &hooks, statusMessage: "Notifying DevBar")
        appendHook(command: codexStopCommand, eventName: "Stop", to: &hooks, statusMessage: "Notifying DevBar")
        config["hooks"] = hooks
        return config
    }

    private static func appendHook(
        command: String,
        eventName: String,
        matcher: String = "",
        to hooks: inout [String: Any],
        statusMessage: String? = nil
    ) {
        var entries = hooks[eventName] as? [[String: Any]] ?? []
        let alreadyInstalled = containsHook(command: command, eventName: eventName, in: hooks)
        guard !alreadyInstalled else { return }

        var commandHook: [String: Any] = ["type": "command", "command": command]
        if let statusMessage {
            commandHook["statusMessage"] = statusMessage
        }
        entries.append(["matcher": matcher, "hooks": [commandHook]])
        hooks[eventName] = entries
    }

    private static func containsHook(command: String, eventName: String, in hooks: [String: Any]) -> Bool {
        let entries = hooks[eventName] as? [[String: Any]] ?? []
        return entries.contains { entry in
            let commands = entry["hooks"] as? [[String: Any]] ?? []
            return commands.contains { $0["command"] as? String == command }
        }
    }

    private func writeJSONConfig(to path: String, content: [String: Any]) -> Bool {
        do {
            let directory = (path as NSString).deletingLastPathComponent
            try FileManager.default.createDirectory(
                atPath: directory,
                withIntermediateDirectories: true,
                attributes: nil
            )

            let data = try JSONSerialization.data(withJSONObject: content, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: URL(fileURLWithPath: path), options: .atomic)
            return true
        } catch {
            print("[HookConfigDetector] Failed to write config to \(path): \(error)")
            return false
        }
    }

    private func writeRawConfig(to path: String, content: String) -> Bool {
        do {
            let directory = (path as NSString).deletingLastPathComponent
            try FileManager.default.createDirectory(
                atPath: directory,
                withIntermediateDirectories: true,
                attributes: nil
            )

            try content.write(toFile: path, atomically: true, encoding: .utf8)
            return true
        } catch {
            print("[HookConfigDetector] Failed to write config to \(path): \(error)")
            return false
        }
    }
}
