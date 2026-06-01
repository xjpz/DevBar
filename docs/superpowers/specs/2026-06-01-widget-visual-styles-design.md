# DevBar 小组件透明、液态玻璃与深色样式设计

## 目标

将 `mashangqu-ios` 中已经使用的透明、液态玻璃、深色小组件能力移植到 DevBar，并覆盖以下三类桌面小组件：

1. AI 额度
2. Agent Watcher
3. Mac 主题

系统“添加小组件”面板直接展示每种内容与视觉样式的组合。用户添加到桌面后，仍可通过“编辑小组件”选择内容参数。锁屏小组件与 Live Activity 保持现有行为。

## 用户体验

### 添加面板

现有三个桌面小组件入口替换为九个样式化入口：

| 内容 | 透明 | 液态玻璃 | 深色 |
| --- | --- | --- | --- |
| AI 额度 | AI 额度 - 透明 | AI 额度 - 液态玻璃 | AI 额度 - 深色 |
| Agent Watcher | Agent Watcher - 透明 | Agent Watcher - 液态玻璃 | Agent Watcher - 深色 |
| Mac 主题 | Mac 主题 - 透明 | Mac 主题 - 液态玻璃 | Mac 主题 - 深色 |

不再在 Widget Bundle 中注册现有的 `DevBarWidget`、`AgentWatcherWidget` 和 `MacThemeWidget` 桌面入口。已经添加到桌面的旧组件可能需要用户删除后重新添加。

### 桌面编辑

- AI 额度：继续使用 `ConfigurationAppIntent`，用户可选择 `GLM`、`OpenAI` 或 `MiMo`。
- Agent Watcher：新增 `AgentWatcherConfigurationIntent`，用户可选择展示内容：
  - `等待处理`：优先展示等待确认、等待输入和 stalled 会话。
  - `运行概览`：展示活跃任务和等待任务总览。
- Mac 主题：继续使用 `MacThemeWidgetConfigurationIntent`，用户可选择默认页面和 AI 额度提供方。

## 架构

### 共享视觉样式

新增 `WidgetVisualStyle`，统一定义：

- `.transparent`
- `.liquidGlass`
- `.dark`

每种样式同时提供：

1. SwiftUI 内容背景，用于控制组件内部可见底板、材质和文字对比度。
2. WidgetKit 描述符背景样式，用于向系统声明透明、模糊或深色呈现方式。

样式由 Widget 壳固定传入，不作为桌面编辑参数暴露。这样添加面板中的九个入口语义稳定，长按编辑只负责内容选择。

### 九个轻量 Widget 壳

三类内容分别保留一套 Timeline Provider 和一套内容 View。新增九个轻量 Widget 壳，仅负责：

- 唯一 `kind`
- 添加面板标题与描述
- 固定 `WidgetVisualStyle`
- 支持尺寸
- 对应的 Widget Configuration Intent

支持尺寸：

| 内容 | 支持尺寸 |
| --- | --- |
| AI 额度 | 小号、中号、大号 |
| Agent Watcher | 小号、中号 |
| Mac 主题 | 大号 |

锁屏 AI 额度组件和两个 Live Activity 继续独立注册，不参与九个桌面入口。

### 私有 API 隔离

沿用 `mashangqu-ios` 已采用的 WidgetKit 描述符注入方式：

1. 新增 Objective-C++ 文件，仅编译进 `DevBarWidgetExtension`。
2. 在 Widget Extension 初始化时对描述符读取流程做 runtime 注入。
3. 使用 `kind -> background style` 映射配置九个桌面 Widget：
   - 透明：`preferredBackgroundStyle = 0x1`
   - 液态玻璃：`preferredBackgroundStyle = 0x2`，开启 vibrant content
   - 深色：系统透明描述符保持可移除背景，SwiftUI 层绘制深色不透明底板
4. runtime 查询不到目标类或注入失败时静默降级到 SwiftUI 背景，不阻断 Widget Extension。

私有 API 代码不进入主 App、通知扩展或 Core 包。

## 文件边界

### 新增

- `DevBarWidget/WidgetVisualStyle.swift`
  - 定义视觉样式、SwiftUI 背景和壳共用辅助方法。
- `DevBarWidget/DesktopStyledWidgets.swift`
  - 定义九个轻量 Widget 壳。
- `DevBarWidget/WidgetDescriptorBackgroundInjector.h`
  - Objective-C++ 注入器声明。
- `DevBarWidget/WidgetDescriptorBackgroundInjector.mm`
  - WidgetKit 描述符背景样式注入实现。
- `DevBarWidget/DevBarWidget-Bridging-Header.h`
  - Widget Extension 的 Objective-C 桥接头。

### 修改

- `DevBarWidget/AppIntent.swift`
  - 新增 Agent Watcher 内容选择枚举与 Intent。
- `DevBarWidget/DevBarWidget.swift`
  - 将 AI 额度 View 改为接收固定视觉样式；保留 Provider 和锁屏组件。
- `DevBarWidget/AgentWatcherWidget.swift`
  - Timeline Provider 接收 Agent Watcher 内容配置；View 根据配置和视觉样式展示内容。
- `DevBarWidget/MacThemeWidget.swift`
  - Mac 主题 View 接收固定视觉样式。
- `DevBarWidget/Views/MacThemeLargeWidgetView.swift`
  - 根据视觉样式调整内部面板对比度和背景。
- `DevBarWidget/DevBarWidgetBundle.swift`
  - 注册九个样式入口，保留锁屏组件与 Live Activity。
- `DevBar.xcodeproj/project.pbxproj`
  - 为 Widget Extension 配置桥接头和 Objective-C++ 非 ARC 编译参数。

### 移除

- `DevBarWidget/WidgetBackgroundStyle.swift`
  - 删除当前未完整接入的 Swift runtime 草稿，避免与 Objective-C++ 注入器并存。

## 数据流

1. 用户从系统添加面板选择某个固定样式入口。
2. Widget 壳将固定视觉样式传给内容 View。
3. 用户长按桌面组件并选择“编辑小组件”。
4. WidgetKit 使用对应 Intent 保存内容参数。
5. Timeline Provider 根据 Intent 和 App Group 数据生成 Entry。
6. SwiftUI View 使用 Entry 渲染内容，并依据固定样式绘制可见底板。
7. Widget Extension 描述符注入器根据 Widget `kind` 向系统声明透明或模糊背景能力。

## 降级策略

- 私有描述符接口变化：保留 SwiftUI 层背景；透明与液态玻璃效果可能退化，但组件仍可使用。
- iOS 26 以下：液态玻璃使用 `.ultraThinMaterial`。
- iOS 26 及以上：液态玻璃优先使用公开 `.glassEffect`，描述符层同步请求模糊背景。
- macOS：使用 SwiftUI 背景实现，不执行 iOS WidgetKit 私有描述符注入。

## 验证标准

1. Widget Bundle 注册九个桌面入口、一个锁屏入口和现有 Live Activity。
2. AI 额度三种样式均可编辑 Provider。
3. Agent Watcher 三种样式均可编辑显示内容。
4. Mac 主题三种样式均可编辑默认页面和 Provider，且仅支持大号尺寸。
5. iOS Simulator 构建通过。
6. macOS 构建通过。
7. Objective-C++ 注入器仅链接到 `DevBarWidgetExtension`。
8. `git diff --check` 通过。

## 已知风险

- WidgetKit 描述符注入依赖私有 API。尽管参考项目 `mashangqu-ios` 已使用同类实现并通过审核，系统版本变化或后续审核策略变化仍可能导致行为退化或审核失败。
- 旧桌面组件入口从 Bundle 中移除后，已存在的桌面实例可能需要用户重新添加。
