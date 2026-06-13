//
//  AppIntent.swift
//  DevBarWidget
//

import AppIntents
import DevBarCore
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
