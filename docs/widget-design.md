# DevBar WidgetKit 通知中心小组件

## 概述

为 DevBar macOS 菜单栏应用添加 WidgetKit 小组件扩展，让用户可以在通知中心（Today View）直接查看 BigModel 额度使用情况。

## 需求

- 在 macOS 通知中心添加小组件，展示额度使用百分比和进度条
- 支持小/中/大三种尺寸（systemSmall / systemMedium / systemLarge）
- 数据与主应用实时同步

## 约束

- 沙盒已关闭（`ENABLE_APP_SANDBOX = NO`）
- `REGISTER_APP_GROUPS = YES` 已启用
- 认证凭据存储在 Keychain（`kSecAttrAccessibleAfterFirstUnlock`）
- macOS 部署目标 14.0+
- 数据模型已实现 `Codable` & `Sendable`

## 安全设计

- Widget **不直接访问 API**，不持有 token
- 主应用负责数据获取和写入，Widget 只读取缓存
- App Groups UserDefaults 只存放脱敏展示数据（百分比、名称等）

## 架构

### 数据流

```
主应用 (DevBar)
  | QuotaViewModel.fetchQuota() 成功后
  | --> 写入 App Groups UserDefaults
  | --> WidgetCenter.shared.reloadAllTimelines()
  v
Widget Extension (DevBarWidget)
  | TimelineProvider 读取共享 UserDefaults
  | --> 渲染 UI
```

### 数据共享方案

使用 App Groups + UserDefaults（数据量极小，原子写入，性能优于 FileManager）。

### 共享数据结构

```swift
struct WidgetSharedData: Codable, Sendable {
    let schemaVersion: Int
    let limits: [WidgetQuotaLimit]
    let level: String?
    let subscriptionName: String?
    let lastUpdated: Date
}

struct WidgetQuotaLimit: Codable, Sendable, Identifiable {
    var id: String { type }
    let type: String
    let displayName: String
    let percentage: Int
    let unitDescription: String?
    let formattedResetTime: String?
}
```

### Timeline 刷新策略

| 触发方式 | 频率 | 说明 |
|---------|------|------|
| 主应用 reloadAllTimelines() | 每次获取额度后 | 主要刷新路径 |
| WidgetKit .after(nextUpdate) | 15 分钟 | 兜底方案 |
| 额度重置时间点 | 按实际时间 | 额外 timeline entry |

## 文件结构

```
DevBar/
├── DevBar/                          # 主应用 (修改)
│   ├── Models/QuotaResponse.swift   # 添加 toWidgetData()
│   ├── Services/WidgetDataManager.swift  # 新建
│   ├── Utils/Constants.swift        # 添加 AppGroup
│   ├── ViewModels/QuotaViewModel.swift   # 集成写入
│   └── DevBar.entitlements          # 添加 App Groups
│
├── DevBarWidget/                    # 新建 Widget Extension
│   ├── DevBarWidget.swift           # Widget 入口 + TimelineProvider
│   ├── Views/
│   │   ├── QuotaSmallView.swift
│   │   ├── QuotaMediumView.swift
│   │   └── QuotaLargeView.swift
│   ├── Models/
│   │   └── WidgetSharedData.swift
│   └── DevBarWidget.entitlements
```

## 实施阶段

### 阶段1: 主应用基础设施

1. Constants 添加 App Group ID（`group.cc.xjpz.DevBar`）
2. Entitlements 配置 App Groups
3. 创建 WidgetDataManager 服务（读写 App Groups UserDefaults）
4. QuotaLimit/QuotaData 添加 toWidgetData() 转换
5. QuotaViewModel.fetchQuota 成功后写入共享数据并刷新 Widget

### 阶段2-3: Widget Extension + Timeline

1. 创建 DevBarWidget 目录结构和共享数据模型
2. 实现 QuotaTimelineProvider（placeholder/snapshot/timeline）
3. 定义 Widget 主体（StaticConfiguration）

### 阶段4: Widget UI

1. DevBarWidgetEntryView（路由不同尺寸和状态）
2. QuotaSmallView（圆形进度指示器 + 百分比）
3. QuotaMediumView（圆形进度 + 额度列表）
4. QuotaLargeView（完整面板：进度条、重置时间、更新时间）
5. NotLoggedInView / NoDataView（占位视图）

### 阶段5-6: 集成与本地化

1. DevBarApp 首次启动写入占位数据
2. 设置页添加 Widget 使用引导
3. Widget 字符串中英文本地化

## 风险

| 风险 | 严重程度 | 缓解措施 |
|------|---------|---------|
| App Group ID 与 Developer Portal 不匹配 | 高 | 提前确认 |
| 两端 WidgetSharedData 模型不同步 | 中 | schemaVersion 字段 |
| 用户未启动主应用就添加 Widget | 中 | 占位视图引导 |
| parseResetTime 跨年解析错误 | 低 | 假设当前年份 |
