import Foundation
import SwiftUI
import WidgetKit
import AppIntents
import DevBarCore

// MARK: - Widget Background Mode

enum WidgetBackgroundMode: String, AppEnum {
    case transparent = "transparent"
    case liquidGlass = "liquid_glass"
    case dark = "dark"

    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "背景模式")
    }

    static var caseDisplayRepresentations: [WidgetBackgroundMode: DisplayRepresentation] {
        [
            .transparent: DisplayRepresentation(title: "透明", subtitle: "完全透明背景"),
            .liquidGlass: DisplayRepresentation(title: "液态玻璃", subtitle: "模糊毛玻璃效果"),
            .dark: DisplayRepresentation(title: "深色", subtitle: "深色不透明背景"),
        ]
    }
}

// MARK: - Widget Background Intent

struct AgentWatcherBackgroundIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Agent Watcher 背景"
    static var description = IntentDescription("选择小组件的背景样式")

    @Parameter(title: "背景模式", default: .transparent)
    var backgroundMode: WidgetBackgroundMode

    func perform() async throws -> some IntentResult {
        // 保存到 UserDefaults（App Group）
        let defaults = UserDefaults(suiteName: DevBarCoreConstants.AppGroup.groupID)
        defaults?.set(backgroundMode.rawValue, forKey: "agentWatcherWidgetBackgroundMode")
        defaults?.synchronize()

        // 触发小组件重新加载
        WidgetCenter.shared.reloadAllTimelines()

        return .result()
    }
}

// MARK: - Background View Modifier

struct WidgetBackgroundModifier: ViewModifier {
    let mode: WidgetBackgroundMode

    func body(content: Content) -> some View {
        switch mode {
        case .transparent:
            content
                .containerBackground(.clear, for: .widget)
        case .liquidGlass:
            content
                .background {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(.ultraThinMaterial)
                }
                .containerBackground(.clear, for: .widget)
        case .dark:
            content
                .background(Color.black)
                .containerBackground(.clear, for: .widget)
        }
    }
}

extension View {
    func widgetBackground(_ mode: WidgetBackgroundMode) -> some View {
        modifier(WidgetBackgroundModifier(mode: mode))
    }
}

// MARK: - Frosted Card (磨砂衬底)

struct FrostedCard<Content: View>: View {
    let cornerRadius: CGFloat
    let padding: CGFloat
    let isDark: Bool
    @ViewBuilder let content: () -> Content

    init(
        cornerRadius: CGFloat = 12,
        padding: CGFloat = 10,
        isDark: Bool = false,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.cornerRadius = cornerRadius
        self.padding = padding
        self.isDark = isDark
        self.content = content
    }

    var body: some View {
        content()
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(isDark ? Color.white.opacity(0.1) : Color.white.opacity(0.15))
            )
    }
}

// MARK: - Shadow Modifier

extension View {
    @ViewBuilder
    func shadowIf(_ enabled: Bool) -> some View {
        if enabled {
            self.shadow(color: .black.opacity(0.5), radius: 2)
        } else {
            self
        }
    }
}

// MARK: - Transparent Background Setup (Private API)

enum WidgetTransparentBackground {
    /// 需要透明背景的小组件 kind
    private static let transparentKinds: Set<String> = [
        "cc.xjpz.DevBar.AgentWatcherWidget",
    ]

    /// 在 widget 扩展加载时自动执行
    static func setup() {
        guard let descriptorClass = NSClassFromString("CHSMutableWidgetDescriptor") else {
            print("[WidgetBG] CHSMutableWidgetDescriptor class not found")
            return
        }

        let initSelector = NSSelectorFromString("init")
        guard let initMethod = class_getInstanceMethod(descriptorClass, initSelector) else {
            print("[WidgetBG] init method not found")
            return
        }

        let originalIMP = method_getImplementation(initMethod)

        let block: @convention(block) (AnyObject) -> AnyObject? = { selfObj in
            // 调用原始 init
            let result = unsafeBitCast(originalIMP, to: (@convention(c) (AnyObject, Selector) -> AnyObject?).self)(selfObj, initSelector)

            // 获取 kind 并应用透明背景
            if let result = result {
                applyBackgroundStyle(to: result)
            }
            return result
        }

        let newIMP = imp_implementationWithBlock(block)
        method_setImplementation(initMethod, newIMP)
        print("[WidgetBG] Swizzled CHSMutableWidgetDescriptor.init successfully")
    }

    /// 对 descriptor 应用背景样式
    private static func applyBackgroundStyle(to descriptor: AnyObject) {
        let kindSelector = NSSelectorFromString("kind")
        guard descriptor.responds(to: kindSelector) else { return }

        guard let kind = descriptor.perform(kindSelector)?.takeUnretainedValue() as? String else { return }

        guard transparentKinds.contains(kind) else { return }

        // 读取用户选择的背景模式
        let defaults = UserDefaults(suiteName: DevBarCoreConstants.AppGroup.groupID)
        let modeRaw = defaults?.string(forKey: "agentWatcherWidgetBackgroundMode") ?? "transparent"

        let preferredStyle: Int
        switch modeRaw {
        case "liquid_glass":
            preferredStyle = 2 // blurred
        case "dark":
            preferredStyle = 0 // default (opaque)
        default:
            preferredStyle = 1 // transparent
        }

        // 设置背景
        let bgRemovableSel = NSSelectorFromString("setBackgroundRemovable:")
        if descriptor.responds(to: bgRemovableSel) {
            _ = descriptor.perform(bgRemovableSel, with: preferredStyle != 0)
        }

        let transparentSel = NSSelectorFromString("setTransparent:")
        if descriptor.responds(to: transparentSel) {
            _ = descriptor.perform(transparentSel, with: preferredStyle == 1)
        }

        let styleSel = NSSelectorFromString("setPreferredBackgroundStyle:")
        if descriptor.responds(to: styleSel) {
            _ = descriptor.perform(styleSel, with: preferredStyle)
        }

        print("[WidgetBG] Applied style \(preferredStyle) to: \(kind)")
    }
}
