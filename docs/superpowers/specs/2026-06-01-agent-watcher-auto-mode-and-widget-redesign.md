# Agent Watcher 自动审核通知抑制与小组件改版设计

## 目标

1. Codex 处于无需人工确认的权限模式时，不向 Mac 或 iPhone 发送 Agent Watcher 通知。
2. 重构 Agent Watcher 桌面小组件，采用紧凑状态面板布局，提高小号与中号组件的信息层级和可读性。

## Codex 自动审核通知抑制

### 权限模式识别

新增 `CodexPermissionModePolicy`，集中判断 `permission_mode` 是否代表无需人工确认。

识别前先规范化字符串：

- 忽略大小写。
- 移除空格。
- 移除 `-`。
- 移除 `_`。

以下值视为无需人工确认：

- `auto`
- `never`
- `full-auto`
- `bypassPermissions`

规范化后也兼容 `full_auto`、`FULL-AUTO`、`bypass_permissions` 等同义格式。

### 行为

Codex hook 事件仍写入 `AgentSessionStore`，因此：

- 菜单栏状态继续更新。
- Widget 数据继续更新。
- stalled 检测继续工作。
- 用户仍可在 Agent Watcher 页面查看会话。

但无需人工确认模式产生的 Codex 事件标记为不可通知：

- 不发送 Mac 本地通知。
- 不发送 iPhone Relay 推送。
- 不安排延迟升级推送。

普通人工审批模式保持现有行为。

## Agent Watcher Widget 改版

### 视觉方向

采用紧凑状态面板风格。等待数量使用自然数格式，例如 `3`，不显示为 `03`。

### 小号

- 顶部：`AGENT WATCHER` 与状态点。
- 中间：等待处理数量。
- 底部：运行中、stalled 数量。
- 没有等待任务时突出正常状态。

### 中号

- 顶部：标题、等待数量、运行中状态胶囊。
- 主体：最多两张优先任务卡。
- 底部：相对更新时间。

任务优先级：

1. 等待授权
2. stalled
3. 等待输入
4. 其他等待状态

### 运行概览模式

桌面编辑选择 `运行概览` 时，突出三个统计值：

- 运行中
- 等待处理
- stalled

### 背景样式

透明、液态玻璃、深色三个 Agent Watcher Widget 入口继续复用同一套 View。布局不复制，仅根据 `WidgetVisualStyle` 调整：

- 文字对比度
- 面板透明度
- 卡片填充色
- 描边强度

## 文件边界

### 新增

- `DevBar/Services/AgentWatcher/CodexPermissionModePolicy.swift`
- `DevBarTests/CodexPermissionModePolicyTests.swift`

### 修改

- `DevBar/Services/AgentWatcher/AgentEvent.swift`
  - 为事件增加是否允许发送通知的字段。
- `DevBar/Services/AgentWatcher/CodexHookHandler.swift`
  - 根据 `permission_mode` 设置通知能力。
- `DevBar/Services/AgentWatcher/AgentWatcherService.swift`
  - Mac 通知、iPhone 推送和延迟升级统一遵守事件通知能力。
- `DevBarWidget/AgentWatcherWidget.swift`
  - 按小号、中号和内容模式拆分紧凑布局。

## 验证标准

1. `CodexPermissionModePolicy` 单元测试覆盖无需人工确认模式与普通模式。
2. 自动审核 Codex 事件仍进入会话，但不会触发 Mac 或 iPhone 通知。
3. Agent Watcher 小号显示自然数格式等待数量。
4. Agent Watcher 中号最多展示两张优先任务卡。
5. iOS Simulator 构建通过。
6. macOS 构建通过。
7. `git diff --check` 通过。
