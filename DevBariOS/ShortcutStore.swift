import Combine
import DevBarCore
import SwiftUI

/// 快捷方式动作状态管理
///
/// 解耦 AppDelegate 事件捕获与 SwiftUI 视图导航响应。
/// AppDelegate 和 SwiftUI App 通过 `shared` 共享同一实例。
final class ShortcutStore: ObservableObject {
    static let shared = ShortcutStore()

    enum Action: Hashable {
        case memo
        case qrScan
        case apiClient
        case lockMac
        case wakeMacDisplay
        case sleepMacDisplay
        case ocr
    }

    static func action(for shortcutAction: DeviceRelayHomeScreenShortcutAction) -> Action {
        switch shortcutAction {
        case .memo: return .memo
        case .qrScan: return .qrScan
        case .apiClient: return .apiClient
        case .lockMac: return .lockMac
        case .wakeMacDisplay: return .wakeMacDisplay
        case .sleepMacDisplay: return .sleepMacDisplay
        case .ocr: return .ocr
        }
    }

    static func action(for url: URL) -> Action? {
        guard url.scheme == "devbar" else { return nil }

        switch url.host {
        case "quota", "mac-dashboard":
            return nil
        case "mac-control":
            let action = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?
                .first { $0.name == "action" }?
                .value
            switch action {
            case "lock":
                return .lockMac
            case "wakeDisplay":
                return .wakeMacDisplay
            case "sleepDisplay":
                return .sleepMacDisplay
            default:
                return nil
            }
        default:
            return nil
        }
    }

    @Published private(set) var pendingAction: Action?

    @MainActor
    func handle(_ action: Action) {
        pendingAction = action
    }

    @MainActor
    func consume() {
        pendingAction = nil
    }
}
