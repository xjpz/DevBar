import Foundation

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
        case .detected: return "✅ 已检测到"
        case .notDetected: return "⚠️ 未检测到"
        case .error(let msg): return "❌ \(msg)"
        }
    }
}

// MARK: - Hook Config Detector

class HookConfigDetector {
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

            // 检查是否有 Notification 或 Stop hook
            let hasNotification = hooks["Notification"] != nil
            let hasStop = hooks["Stop"] != nil

            if hasNotification || hasStop {
                return .detected
            } else {
                return .notDetected
            }
        } catch {
            return .error("读取配置失败: \(error.localizedDescription)")
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
                   hooks["PermissionRequest"] != nil {
                    return .detected
                }
            } catch {
                return .error("读取 hooks.json 失败: \(error.localizedDescription)")
            }
        }

        // 检查 config.toml
        if fileManager.fileExists(atPath: codexConfigPath) {
            do {
                let content = try String(contentsOfFile: codexConfigPath, encoding: .utf8)
                if content.contains("PermissionRequest") || content.contains("hooks") {
                    return .detected
                }
            } catch {
                return .error("读取 config.toml 失败: \(error.localizedDescription)")
            }
        }

        return .notDetected
    }

    // MARK: - Config Generation

    func generateClaudeConfig() -> String {
        return """
        {
          "hooks": {
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
            "SessionStart": [
              {
                "matcher": "startup|resume",
                "hooks": [
                  {
                    "type": "command",
                    "command": "curl -s -X POST http://127.0.0.1:49321/agent/codex/session-start -H 'Content-Type: application/json' -d @-",
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
        let config = generateClaudeConfig()
        return writeConfig(to: claudeConfigPath, content: config)
    }

    func installCodexConfig() -> Bool {
        let config = generateCodexHooksConfig()
        return writeConfig(to: codexHooksPath, content: config)
    }

    private func writeConfig(to path: String, content: String) -> Bool {
        do {
            // 确保目录存在
            let directory = (path as NSString).deletingLastPathComponent
            try FileManager.default.createDirectory(
                atPath: directory,
                withIntermediateDirectories: true,
                attributes: nil
            )

            // 写入文件
            try content.write(toFile: path, atomically: true, encoding: .utf8)
            return true
        } catch {
            print("[HookConfigDetector] Failed to write config to \(path): \(error)")
            return false
        }
    }
}
