import AppIntents
import DevBarCore
import Foundation

struct LockMacIntent: AppIntent {
    static var title: LocalizedStringResource = "锁屏 Mac"
    static var description = IntentDescription("通过 DevBar Relay 锁定已配对的 Mac。")

    @Parameter(title: "Mac")
    var mac: MacDeviceEntity?

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let text = await MacControlIntentRunner.run(.lockScreen, selectedMac: mac)
        return .result(dialog: IntentDialog(stringLiteral: text))
    }
}

struct WakeMacDisplayIntent: AppIntent {
    static var title: LocalizedStringResource = "点亮 Mac"
    static var description = IntentDescription("通过 DevBar Relay 点亮已配对 Mac 的显示器。")

    @Parameter(title: "Mac")
    var mac: MacDeviceEntity?

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let text = await MacControlIntentRunner.run(.wakeDisplay, selectedMac: mac)
        return .result(dialog: IntentDialog(stringLiteral: text))
    }
}

struct SleepMacDisplayIntent: AppIntent {
    static var title: LocalizedStringResource = "关闭 Mac 显示器"
    static var description = IntentDescription("通过 DevBar Relay 关闭已配对 Mac 的显示器。")

    @Parameter(title: "Mac")
    var mac: MacDeviceEntity?

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let text = await MacControlIntentRunner.run(.displaySleep, selectedMac: mac)
        return .result(dialog: IntentDialog(stringLiteral: text))
    }
}

enum MacControlIntentRunner {
    static func run(_ command: DeviceRelayCommandType, selectedMac: MacDeviceEntity?) async -> String {
        let store = DeviceRelayStore()
        guard let token = store.loadDeviceToken(), !token.isEmpty else {
            return "还没有配对 Mac，请先在 DevBar 中扫码配对。"
        }

        let targetMac: MacDeviceEntity?
        if let selectedMac {
            targetMac = selectedMac
        } else {
            targetMac = await MacDeviceEntityQuery.defaultResult()
        }

        guard let targetMac else {
            return "还没有配对 Mac，请先在 DevBar 中扫码配对。"
        }

        do {
            _ = try await DeviceRelayService.shared.sendDeviceCommand(
                type: command,
                targetDeviceId: targetMac.id,
                deviceToken: token
            )
            return successText(for: command, macName: targetMac.name)
        } catch DeviceRelayError.serverError(let code) where code == "target_offline" {
            return "Mac 当前不在线，无法执行。"
        } catch {
            return "DevBar 发送命令失败：\(error.localizedDescription)"
        }
    }

    private static func successText(for command: DeviceRelayCommandType, macName: String) -> String {
        switch command {
        case .lockScreen:
            return "已发送锁屏命令到 \(macName)。"
        case .wakeDisplay:
            return "已发送点亮显示器命令到 \(macName)。"
        case .displaySleep:
            return "已发送关闭显示器命令到 \(macName)。"
        }
    }
}
