import AppIntents

struct DevBarAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: LockMacIntent(),
            phrases: [
                "用 \(.applicationName) 锁屏电脑",
                "\(.applicationName) 锁定我的电脑",
                "Lock my computer with \(.applicationName)",
            ],
            shortTitle: "锁屏电脑",
            systemImageName: "lock"
        )

        AppShortcut(
            intent: WakeMacDisplayIntent(),
            phrases: [
                "用 \(.applicationName) 点亮电脑",
                "\(.applicationName) 点亮我的电脑",
                "Wake my computer display with \(.applicationName)",
            ],
            shortTitle: "点亮电脑",
            systemImageName: "sun.max"
        )

        AppShortcut(
            intent: SleepMacDisplayIntent(),
            phrases: [
                "用 \(.applicationName) 关闭电脑显示器",
                "\(.applicationName) 关闭我的电脑显示器",
                "Turn off my computer display with \(.applicationName)",
            ],
            shortTitle: "关闭显示器",
            systemImageName: "moon"
        )

        AppShortcut(
            intent: ForwardSMSAlertIntent(),
            phrases: [
                "用 \(.applicationName) 转发短信提醒",
                "\(.applicationName) 提醒我的电脑这条短信",
                "Forward SMS alert with \(.applicationName)",
            ],
            shortTitle: "短信提醒",
            systemImageName: "message.badge"
        )
    }
}
