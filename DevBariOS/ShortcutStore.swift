import Combine
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
        case ocr
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
