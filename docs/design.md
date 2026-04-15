# DevBar - BigModel 套餐用量菜单栏工具实现方案

## Context

BigModel（智谱大模型）提供 coding-plan 等套餐服务，用户需要频繁打开网页查看用量剩余情况。
本工具在 Mac 菜单栏常驻显示用量百分比，点击可查看详细用量信息，免去打开浏览器的步骤。

## 需求概述

1. **菜单栏常驻图标**：显示当前用量百分比（如 `63%`）
2. **微信扫码登录**：通过 WKWebView 加载 BigModel 官方登录页，扫码获取认证信息
3. **用量查询**：定时调用 `/api/monitor/usage/quota/limit` 接口获取用量
4. **自动获取 Org/Project ID**：登录成功后自动提取，无需用户手动配置

## 技术方案

### 架构：MVVM + SwiftUI

```
DevBar/
├── DevBarApp.swift                  # MenuBarExtra 入口
├── Models/
│   ├── QuotaResponse.swift          # API 响应模型
│   └── AuthCredentials.swift        # 凭证模型
├── Services/
│   ├── AuthService.swift            # 登录流程控制
│   ├── BigModelAPIClient.swift      # API 客户端
│   └── KeychainService.swift        # Keychain 安全存储
├── Views/
│   ├── MenuBarView.swift            # 菜单栏 Popover 主视图
│   ├── QuotaRowView.swift           # 配额行视图
│   ├── LoginView.swift              # WKWebView 登录视图
│   └── SettingsView.swift           # 设置视图
├── ViewModels/
│   ├── AppViewModel.swift           # 全局状态管理
│   └── QuotaViewModel.swift         # 用量数据管理
└── Utils/
    ├── Constants.swift              # API URLs、配置常量
    └── Extensions.swift             # 通用扩展
```

### Phase 1: 项目基础改造

**修改文件：**
- `DevBar/DevBarApp.swift` — WindowGroup → MenuBarExtra
- `DevBar.xcodeproj/project.pbxproj` — 添加 entitlements 文件引用

**新建文件：**
- `DevBar/DevBar.entitlements` — 启用网络出站权限 (`com.apple.security.network.client`)
- `DevBar/Utils/Constants.swift` — API 地址等常量

**关键变更：**
```swift
// DevBarApp.swift
@main
struct DevBarApp: App {
    @State private var appViewModel = AppViewModel()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environment(appViewModel)
        } label: {
            Label(appViewModel.statusText, systemImage: "chart.bar.fill")
        }
        .menuBarExtraStyle(.window)
    }
}
```

### Phase 2: 认证模块

**LoginView（WKWebView 登录）：**
- WKWebView 加载 `https://bigmodel.cn/login`
- 页面自动展示微信二维码，用户扫码
- 通过 `WKNavigationDelegate.decidePolicyFor` 监听导航：
  - 如果 URL 从 `/login` 跳转到主页 → 登录成功
- 登录成功后通过 `WKWebsiteDataStore.default().httpCookieStore.getAllCookies()` 获取 cookies
- 提取 `bigmodel_token_production` cookie 作为 Authorization token

**自动获取 Organization / Project ID：**
- 登录成功后，WKWebView 导航到 `https://bigmodel.cn/coding-plan/personal/overview`
- 通过 `WKUserScript` 注入 JavaScript，监听 XHR/fetch 请求：
  - 拦截包含 `/api/monitor/` 的请求，提取 `Bigmodel-organization` 和 `Bigmodel-project` 请求头
- 备选方案：从页面 JS 变量（如 `window.__NEXT_DATA__` 或全局 store）中提取

**KeychainService：**
- 存储：Authorization token, Organization ID, Project ID, Cookie 字符串
- 读取：App 启动时恢复登录态
- 清除：用户主动退出登录时

### Phase 3: API 客户端

**BigModelAPIClient：**
- GET `https://bigmodel.cn/api/monitor/usage/quota/limit`
- Headers：
  - `Authorization`: JWT token（来自 `bigmodel_token_production` cookie）
  - `Bigmodel-organization`: org ID（登录后自动获取）
  - `Bigmodel-project`: proj ID（登录后自动获取）
  - `Accept`: `application/json`
  - `Cookie`: 完整 cookie 字符串（从登录时获取）

**QuotaResponse 模型：**
```swift
struct QuotaResponse: Codable {
    let code: Int
    let msg: String
    let data: QuotaData
    let success: Bool
}

struct QuotaData: Codable {
    let limits: [QuotaLimit]
    let level: String
}

struct QuotaLimit: Codable, Identifiable {
    var id: String { type }
    let type: String          // "TIME_LIMIT" | "TOKENS_LIMIT"
    let unit: Int?
    let number: Int?
    let usage: Int?
    let currentValue: Int?
    let remaining: Int?
    let percentage: Int
    let nextResetTime: Int64?
    let usageDetails: [UsageDetail]?
}

struct UsageDetail: Codable, Identifiable {
    var id: String { modelCode }
    let modelCode: String
    let usage: Int
}
```

### Phase 4: UI 展示

**菜单栏图标：**
- 未登录：显示默认图标（`chart.bar`）
- 已登录：图标 + 用量百分比文字（如 `63%`）

**Popover 内容（MenuBarView）：**

```
┌─────────────────────────┐
│ DevBar          [刷新] [⚙️] │
├─────────────────────────┤
│ 套餐等级: Lite          │
│                         │
│ 次数限制 (5分钟/1次)     │
│ ████████████░░░░  63%   │
│   search-prime    29    │
│   web-reader     34    │
│   zread           0    │
│ 剩余: 37  重置: 2h 30m  │
│                         │
│ Token 限制              │
│ █████░░░░░░░░░░░  14%   │
│ 重置: 明天 10:30        │
│                         │
│ ─────────────────────── │
│ 退出登录                │
└─────────────────────────┘
```

**定时刷新：**
- 默认每 5 分钟自动刷新
- 可在设置中调整（1/5/10/30 分钟）
- 下拉菜单关闭时停止刷新，打开时恢复

### Phase 5: 状态管理

**AppViewModel（全局状态）：**
```swift
@Observable
class AppViewModel {
    enum AuthState {
        case loading, notLoggedIn, loggedIn, expired
    }

    var authState: AuthState = .loading
    var quotaData: QuotaData?
    var lastError: String?
    var statusText: String = "DevBar"
    var refreshInterval: TimeInterval = 300
}
```

**启动流程：**
1. App 启动 → 从 Keychain 读取 token
2. 如果有 token → 尝试调用 API 验证
3. API 成功 → `loggedIn`，显示用量
4. API 返回 401 → `expired`，引导重新登录
5. 无 token → `notLoggedIn`，显示登录界面

## 关键文件清单

| 文件 | 操作 | 说明 |
|------|------|------|
| `DevBar/DevBarApp.swift` | 修改 | WindowGroup → MenuBarExtra |
| `DevBar/ContentView.swift` | 删除 | 不再需要 |
| `DevBar/DevBar.entitlements` | 新建 | 网络权限 |
| `DevBar/Utils/Constants.swift` | 新建 | API 常量 |
| `DevBar/Utils/Extensions.swift` | 新建 | 扩展方法 |
| `DevBar/Models/QuotaResponse.swift` | 新建 | 响应模型 |
| `DevBar/Models/AuthCredentials.swift` | 新建 | 凭证模型 |
| `DevBar/Services/KeychainService.swift` | 新建 | Keychain 存储 |
| `DevBar/Services/AuthService.swift` | 新建 | 登录流程 |
| `DevBar/Services/BigModelAPIClient.swift` | 新建 | API 客户端 |
| `DevBar/Views/LoginView.swift` | 新建 | 登录 WebView |
| `DevBar/Views/MenuBarView.swift` | 新建 | 主视图 |
| `DevBar/Views/QuotaRowView.swift` | 新建 | 配额行 |
| `DevBar/Views/SettingsView.swift` | 新建 | 设置 |
| `DevBar/ViewModels/AppViewModel.swift` | 新建 | 全局 VM |
| `DevBar/ViewModels/QuotaViewModel.swift` | 新建 | 用量 VM |

## 风险评估

| 级别 | 风险 | 缓解措施 |
|------|------|----------|
| HIGH | Org/Project ID 自动提取可能失败 | 备选方案：JS 注入提取页面数据，或添加设置页面手动配置 |
| MEDIUM | App Sandbox 限制 Cookie 访问 | WKWebsiteDataStore 在沙盒内可用，无需额外权限 |
| MEDIUM | Token 过期时间未知 | 每次请求检测 401，自动触发重新登录 |
| LOW | WKWebView 在 MenuBarExtra 中的生命周期 | Popover 显示时创建，关闭时销毁并取消请求 |

## 验证方案

1. **构建验证**：`xcodebuild build -scheme DevBar -destination 'platform=macOS'`
2. **登录验证**：启动 App → 显示登录页 → 微信扫码 → 登录成功 → 用量显示
3. **API 验证**：菜单栏显示百分比 → 点击显示详细用量 → 数据与网页一致
4. **持久化验证**：重启 App → 自动恢复登录态 → 自动刷新用量
5. **过期验证**：Token 过期后 → 提示重新登录 → 扫码后恢复
