//
//  AppIntent.swift
//  DevBarWidget
//

import AppIntents
import DevBarCore
import Foundation
import WidgetKit

enum WidgetProviderSelection: String, AppEnum, CaseIterable {
    case glm
    case openai
    case mimo
    case deepseek

    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "Provider")
    }

    static var caseDisplayRepresentations: [WidgetProviderSelection: DisplayRepresentation] {
        [
            .glm: DisplayRepresentation(title: "GLM"),
            .openai: DisplayRepresentation(title: "OpenAI"),
            .mimo: DisplayRepresentation(title: "MiMo"),
            .deepseek: DisplayRepresentation(title: "DeepSeek")
        ]
    }

    var displayName: String {
        switch self {
        case .glm: return "GLM"
        case .openai: return "OpenAI"
        case .mimo: return "MiMo"
        case .deepseek: return "DeepSeek"
        }
    }

    static var enabledSelectionsFromAppGroup: [WidgetProviderSelection] {
        guard let rawValues = UserDefaults(suiteName: DevBarCoreConstants.AppGroup.groupID)?
            .array(forKey: DevBarCoreConstants.AppGroup.enabledWidgetProvidersKey) as? [String] else {
            return []
        }
        return rawValues.compactMap(WidgetProviderSelection.init(rawValue:))
    }
}

struct ConfigurationAppIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource { "DevBar Quota" }
    static var description: IntentDescription { "Choose the Provider shown by this widget." }

    @Parameter(title: "Provider", default: .glm)
    var provider: WidgetProviderSelection
}
#if os(macOS)
enum AgentWatcherContentSelection: String, AppEnum {
    case waiting
    case overview

    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "显示内容")
    }

    static var caseDisplayRepresentations: [AgentWatcherContentSelection: DisplayRepresentation] {
        [
            .waiting: DisplayRepresentation(title: "等待处理", subtitle: "优先显示需要处理的任务"),
            .overview: DisplayRepresentation(title: "运行概览", subtitle: "显示活跃和等待任务数量")
        ]
    }
}

struct AgentWatcherConfigurationIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource { "Agent Watcher" }
    static var description: IntentDescription { "选择 Agent Watcher 小组件显示的内容。" }

    @Parameter(title: "显示内容", default: .waiting)
    var content: AgentWatcherContentSelection
}
#endif

enum MacThemeWidgetPageSelection: String, AppEnum {
    case quota
    case macConsole

    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "Page")
    }

    static var caseDisplayRepresentations: [MacThemeWidgetPageSelection: DisplayRepresentation] {
        [
            .quota: DisplayRepresentation(title: "AI 额度"),
            .macConsole: DisplayRepresentation(title: "电脑控制台")
        ]
    }

    var corePage: MacThemeWidgetPage {
        switch self {
        case .quota: return .quota
        case .macConsole: return .macConsole
        }
    }
}

struct MacThemeWidgetConfigurationIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource { "DevBar 电脑主题" }
    static var description: IntentDescription { "选择默认页面和 AI 额度提供方。" }

    @Parameter(title: "默认页面", default: .quota)
    var defaultPage: MacThemeWidgetPageSelection

    @Parameter(title: "AI 额度提供方", default: .glm)
    var provider: WidgetProviderSelection
}

struct SetMacThemeWidgetPageIntent: AppIntent {
    static var title: LocalizedStringResource { "切换小组件页面" }
    static var description = IntentDescription("在小组件内切换显示页面。")
    static var openAppWhenRun = false

    @Parameter(title: "页面")
    var page: MacThemeWidgetPageSelection

    init() {}

    init(page: MacThemeWidgetPageSelection) {
        self.page = page
    }

    func perform() async throws -> some IntentResult {
        let defaults = UserDefaults(suiteName: DevBarCoreConstants.AppGroup.groupID)
        defaults?.set(page.rawValue, forKey: DevBarCoreConstants.AppGroup.macThemeWidgetSelectedPageKey)
        WidgetCenter.shared.reloadTimelines(ofKind: "DevBarMacThemeWidget")
        return .result()
    }
}

enum WidgetProviderPageDirection: String, AppEnum {
    case previous
    case next

    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "Provider 分页方向")
    }

    static var caseDisplayRepresentations: [WidgetProviderPageDirection: DisplayRepresentation] {
        [
            .previous: DisplayRepresentation(title: "上一页"),
            .next: DisplayRepresentation(title: "下一页")
        ]
    }

    var delta: Int {
        switch self {
        case .previous: return -1
        case .next: return 1
        }
    }
}

struct SetDesktopQuotaProviderPageIntent: AppIntent {
    static var title: LocalizedStringResource { "切换 AI 额度 Provider 页" }
    static var description = IntentDescription("在 AI 额度小组件内切换 Provider 分页。")
    static var openAppWhenRun = false

    @Parameter(title: "方向")
    var direction: WidgetProviderPageDirection

    init() {}

    init(direction: WidgetProviderPageDirection) {
        self.direction = direction
    }

    func perform() async throws -> some IntentResult {
        WidgetProviderPageStore.advance(
            key: DevBarCoreConstants.AppGroup.desktopQuotaWidgetProviderPageKey,
            direction: direction
        )
        WidgetCenter.shared.reloadTimelines(ofKind: "DevBarTransparentWidget")
        WidgetCenter.shared.reloadTimelines(ofKind: "DevBarLiquidGlassWidget")
        WidgetCenter.shared.reloadTimelines(ofKind: "DevBarDarkWidget")
        return .result()
    }
}

struct SetMacThemeQuotaProviderPageIntent: AppIntent {
    static var title: LocalizedStringResource { "切换 Mac 主题额度 Provider 页" }
    static var description = IntentDescription("在 Mac 主题小组件内切换 AI 额度 Provider 分页。")
    static var openAppWhenRun = false

    @Parameter(title: "方向")
    var direction: WidgetProviderPageDirection

    init() {}

    init(direction: WidgetProviderPageDirection) {
        self.direction = direction
    }

    func perform() async throws -> some IntentResult {
        WidgetProviderPageStore.advance(
            key: DevBarCoreConstants.AppGroup.macThemeWidgetQuotaProviderPageKey,
            direction: direction
        )
        WidgetCenter.shared.reloadTimelines(ofKind: "DevBarMacThemeWidget")
        WidgetCenter.shared.reloadTimelines(ofKind: "DevBarTransparentWidget")
        WidgetCenter.shared.reloadTimelines(ofKind: "DevBarLiquidGlassWidget")
        WidgetCenter.shared.reloadTimelines(ofKind: "DevBarDarkWidget")
        return .result()
    }
}

enum MacThemeControlAction: String, AppEnum {
    case lockScreen
    case wakeDisplay
    case displaySleep

    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "Mac 控制")
    }

    static var caseDisplayRepresentations: [MacThemeControlAction: DisplayRepresentation] {
        [
            .lockScreen: DisplayRepresentation(title: "锁定 Mac"),
            .wakeDisplay: DisplayRepresentation(title: "点亮"),
            .displaySleep: DisplayRepresentation(title: "熄屏")
        ]
    }

    var command: DeviceRelayCommandType {
        switch self {
        case .lockScreen:
            return .lockScreen
        case .wakeDisplay:
            return .wakeDisplay
        case .displaySleep:
            return .displaySleep
        }
    }
}

struct RunMacThemeControlIntent: AppIntent {
    static var title: LocalizedStringResource { "执行 Mac 控制" }
    static var description = IntentDescription("通过 DevBar Relay 控制已配对的 Mac。")
    static var openAppWhenRun = false

    @Parameter(title: "动作")
    var action: MacThemeControlAction

    init() {}

    init(action: MacThemeControlAction) {
        self.action = action
    }

    func perform() async throws -> some IntentResult {
        let store = DeviceRelayStore()
        guard let token = store.loadDeviceToken(), !token.isEmpty else {
            print("[DevBar:WidgetMacControl] Missing relay device token.")
            return .result()
        }

        guard let targetDeviceID = Self.loadOnlineTargetMacDeviceID() else {
            print("[DevBar:WidgetMacControl] Missing online target Mac device ID.")
            return .result()
        }

        do {
            _ = try await DeviceRelayService.shared.sendDeviceCommand(
                type: action.command,
                targetDeviceId: targetDeviceID,
                deviceToken: token
            )
            WidgetCenter.shared.reloadTimelines(ofKind: "DevBarMacThemeWidget")
        } catch {
            print("[DevBar:WidgetMacControl] Failed to send \(action.rawValue): \(error.localizedDescription)")
        }
        return .result()
    }

    private static func loadOnlineTargetMacDeviceID() -> String? {
        guard let defaults = UserDefaults(suiteName: DevBarCoreConstants.AppGroup.groupID),
              let raw = defaults.data(forKey: DevBarCoreConstants.AppGroup.macThemeWidgetSnapshotKey),
              let snapshot = try? JSONDecoder().decode(MacThemeWidgetSnapshot.self, from: raw),
              snapshot.schemaVersion == MacThemeWidgetSnapshot.currentSchemaVersion,
              snapshot.macStatus?.isOnline == true,
              let deviceID = snapshot.macStatus?.deviceID,
              !deviceID.isEmpty else {
            return nil
        }
        return deviceID
    }
}

enum WidgetProviderPageStore {
    static let pageSize = 3

    static func currentPage(for key: String, providerCount: Int) -> Int {
        let defaults = UserDefaults(suiteName: DevBarCoreConstants.AppGroup.groupID)
        let storedPage = defaults?.integer(forKey: key) ?? 0
        return clampedPage(storedPage, providerCount: providerCount)
    }

    static func pageCount(for providerCount: Int) -> Int {
        max(1, (providerCount + pageSize - 1) / pageSize)
    }

    static func pageRange(page: Int, providerCount: Int) -> Range<Int> {
        guard providerCount > 0 else { return 0..<0 }
        let lowerBound = min(max(page, 0) * pageSize, providerCount)
        let upperBound = min(lowerBound + pageSize, providerCount)
        return lowerBound..<upperBound
    }

    static func advance(key: String, direction: WidgetProviderPageDirection) {
        let enabledProviderCount = WidgetProviderSelection.enabledSelectionsFromAppGroup.count
        let providerCount = enabledProviderCount > 0 ? enabledProviderCount : WidgetProviderSelection.allCases.count
        let defaults = UserDefaults(suiteName: DevBarCoreConstants.AppGroup.groupID)
        let currentPage = clampedPage(defaults?.integer(forKey: key) ?? 0, providerCount: providerCount)
        let nextPage = clampedPage(currentPage + direction.delta, providerCount: providerCount)
        defaults?.set(nextPage, forKey: key)
    }

    private static func clampedPage(_ page: Int, providerCount: Int) -> Int {
        guard providerCount > 0 else { return 0 }
        let lastPage = pageCount(for: providerCount) - 1
        return min(max(page, 0), lastPage)
    }
}
