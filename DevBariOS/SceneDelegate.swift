import UIKit

/// 场景代理：捕获冷/热启动快捷方式事件
///
/// - 冷启动（进程被杀）：scene(_:willConnectTo:options:) 从 connectionOptions 获取 shortcutItem
/// - 热启动（后台恢复）：windowScene(_:performActionFor:completionHandler:) 直接接收
final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        if let shortcutItem = connectionOptions.shortcutItem {
            ShortcutStore.shared.handle(mapAction(shortcutItem))
        }
    }

    func windowScene(
        _ windowScene: UIWindowScene,
        performActionFor shortcutItem: UIApplicationShortcutItem,
        completionHandler: @escaping (Bool) -> Void
    ) {
        ShortcutStore.shared.handle(mapAction(shortcutItem))
        completionHandler(true)
    }

    private func mapAction(_ item: UIApplicationShortcutItem) -> ShortcutStore.Action {
        if let action = IOSHomeScreenShortcutController.action(for: item.type) {
            return ShortcutStore.action(for: action)
        }
        return .memo
    }
}
