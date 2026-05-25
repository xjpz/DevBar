import AppIntents

struct DevBarAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: LockMacIntent(),
            phrases: [
                "用 \(.applicationName) 锁屏 Mac",
                "\(.applicationName) 锁定我的 Mac",
                "Lock my Mac with \(.applicationName)",
            ],
            shortTitle: "锁屏 Mac",
            systemImageName: "lock"
        )

        AppShortcut(
            intent: WakeMacDisplayIntent(),
            phrases: [
                "用 \(.applicationName) 点亮 Mac",
                "\(.applicationName) 点亮我的 Mac",
                "Wake my Mac display with \(.applicationName)",
            ],
            shortTitle: "点亮 Mac",
            systemImageName: "sun.max"
        )

        AppShortcut(
            intent: SleepMacDisplayIntent(),
            phrases: [
                "用 \(.applicationName) 关闭 Mac 显示器",
                "\(.applicationName) 关闭我的 Mac 显示器",
                "Turn off my Mac display with \(.applicationName)",
            ],
            shortTitle: "关闭显示器",
            systemImageName: "moon"
        )
    }
}
