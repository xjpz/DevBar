# DevBar 国际化 (i18n) 设计方案

## 一、架构决策

### 选择 String Catalog（`.xcstrings`）

**理由：**

1. Xcode 15+ 引入的 `.xcstrings` 是 Apple 推荐的现代本地化方案，与 SwiftUI 深度集成
2. SwiftUI 的 `Text("key")` 自动查找本地化字符串，无需手动调用 `NSLocalizedString`
3. String Catalog 是单一 JSON 文件（`Localizable.xcstrings`），管理所有语言的翻译
4. 项目目标 macOS 14.0+，完全兼容
5. 自动提取：Xcode 可自动扫描代码中的 `Text()` 字面量并生成条目

### 语言切换机制

macOS 系统标准做法是跟随系统语言（`Locale.current`），但用户要求 Settings 内切换。方案：

- 使用 `@AppStorage("app_language")` 存储语言偏好（`"system"` / `"zh-Hans"` / `"en"`）
- 通过 `Environment(\.locale)` 注入自定义 `Locale` 到 SwiftUI 视图树
- 不修改 `UserDefaults.standard` 的 `AppleLanguages`（避免副作用）
- 切换语言后，视图树因 `@AppStorage` 变化自动刷新

## 二、完整字符串清单

### MenuBarView.swift（12 个）

| 当前中文 | Key | 英文 |
|---------|-----|------|
| `"加载中..."` | `loading` | `"Loading..."` |
| `"获取用量..."` | `fetching_usage` | `"Fetching usage..."` |
| `"暂无数据"` | `no_data` | `"No data"` |
| `"刷新"` (help) | `refresh` | `"Refresh"` |
| `"设置"` (help) | `settings` | `"Settings"` |
| `"没有可用套餐"` | `no_subscription` | `"No subscription available"` |
| `"请前往 BigModel 官网订阅"` | `go_subscribe` | `"Please subscribe on BigModel website"` |
| `"订阅截止"` | `subscription_ends` | `"Subscription ends"` |
| `"重试"` | `retry` | `"Retry"` |
| `"退出登录"` | `log_out` | `"Log Out"` |
| `"退出"` | `quit` | `"Quit"` |
| `"DevBar"` | 品牌名不翻译 | `"DevBar"` |

### LoginView.swift（11 个）

| 当前中文 | Key | 英文 |
|---------|-----|------|
| `"开发吧"` | `tagline` | `"Dev Bar"` |
| `"登录已过期，请重新登录"` | `login_expired` | `"Session expired, please log in again"` |
| `"扫码或账号登录"` | `scan_or_account_login` | `"Scan QR code or login with account"` |
| `"浏览器登录"` | `browser_login` | `"Browser Login"` |
| `"或"` | `or` | `"or"` |
| `"请输入API Key"` | `enter_api_key` | `"Enter API Key"` |
| `"API Key登录"` | `api_key_login` | `"API Key Login"` |
| `"凭据仅保存在本地设备"` | `credentials_local_only` | `"Credentials stored locally only"` |
| `"API Key 无效"` | `api_key_invalid` | `"Invalid API Key"` |
| `"Token 无效，请重新登录"` | `token_invalid` | `"Invalid token, please log in again"` |
| `"登录 BigModel"` | `login_bigmodel` | `"Login to BigModel"` |

### SettingsGeneral.swift（10 个）

| 当前中文 | Key | 英文 |
|---------|-----|------|
| `"菜单栏图标"` | `menu_bar_icon` | `"Menu Bar Icon"` |
| `"自动刷新间隔"` | `auto_refresh_interval` | `"Auto Refresh Interval"` |
| `"通用"` | `general` | `"General"` |
| `"登录时启动"` | `launch_at_login` | `"Launch at Login"` |
| `"不在 Dock 栏显示"` | `hide_from_dock` | `"Hide from Dock"` |
| `"状态"` | `status` | `"Status"` |
| `"上次更新: %@"` | `last_updated` | `"Last updated: %@"` |
| `"3 分钟"` | `minutes_3` | `"3 min"` |
| `"5 分钟"` | `minutes_5` | `"5 min"` |
| `"从不"` | `never` | `"Never"` |

### SettingsNotifications.swift（11 个）

| 当前中文 | Key | 英文 |
|---------|-----|------|
| `"通知权限"` | `notification_permission` | `"Notification Permission"` |
| `"已拒绝"` | `denied` | `"Denied"` |
| `"请求权限"` | `request_permission` | `"Request Permission"` |
| `"已授权"` | `authorized` | `"Authorized"` |
| `"低额度提醒"` | `low_quota_alert` | `"Low Quota Alert"` |
| `"启用低额度提醒"` | `enable_low_quota_alert` | `"Enable low quota alert"` |
| `"阈值"` | `threshold` | `"Threshold"` |
| `"启用用尽提醒"` | `enable_exhausted_alert` | `"Enable exhausted alert"` |
| `"启用额度重置提醒"` | `enable_reset_alert` | `"Enable quota reset alert"` |
| `"其他提醒"` | `other_alerts` | `"Other Alerts"` |
| `"用尽提醒在额度耗尽时通知，重置提醒在额度恢复时通知"` | `alerts_footer` | `"Exhausted alert: notified when quota depleted. Reset alert: notified when quota restored"` |

### SettingsAbout.swift（2 个）

| 当前中文 | Key | 英文 |
|---------|-----|------|
| `"DevBar %@"` | `devbar_version` | `"DevBar %@"` |
| `"检查更新"` | `check_for_updates` | `"Check for Updates"` |

### SettingsTab.swift（3 个）

| 当前中文 | Key | 英文 |
|---------|-----|------|
| `"通用"` | `tab_general` | `"General"` |
| `"通知"` | `tab_notifications` | `"Notifications"` |
| `"关于"` | `tab_about` | `"About"` |

### UpdateView.swift（15 个）

| 当前中文 | Key | 英文 |
|---------|-----|------|
| `"正在检查更新..."` | `checking_update` | `"Checking for updates..."` |
| `"发现新版本"` | `new_version_found` | `"New version available"` |
| `"跳过此版本"` | `skip_version` | `"Skip this version"` |
| `"查看详情"` | `view_details` | `"View Details"` |
| `"立即更新"` | `update_now` | `"Update Now"` |
| `"正在下载更新..."` | `downloading_update` | `"Downloading update..."` |
| `"取消"` | `cancel` | `"Cancel"` |
| `"下载完成"` | `download_complete` | `"Download complete"` |
| `"需要重启应用以完成安装"` | `restart_required` | `"Restart required to complete installation"` |
| `"稍后"` | `later` | `"Later"` |
| `"立即重启"` | `restart_now` | `"Restart Now"` |
| `"正在安装..."` | `installing` | `"Installing..."` |
| `"当前已是最新版本"` | `up_to_date` | `"You're up to date"` |
| `"关闭"` | `close` | `"Close"` |
| `"重试"` | `retry` | `"Retry"` |

### QuotaRowView.swift（2 个）

| 当前中文 | Key | 英文 |
|---------|-----|------|
| `"已使用 %d%%"` | `used_percentage` | `"Used %d%%"` |
| `"重置: %@"` | `reset_at` | `"Reset: %@"` |

### QuotaResponse.swift — QuotaLimit 扩展（7 个）

| 当前中文 | Key | 英文 |
|---------|-----|------|
| `"Token 使用额度"` | `token_quota` | `"Token Usage Quota"` |
| `"MCP 每月额度"` | `mcp_monthly_quota` | `"MCP Monthly Quota"` |
| `"每月"` | `per_month` | `"Monthly"` |
| `"每小时"` | `per_hour` | `"Hourly"` |
| `"每%d小时"` | `per_n_hours` | `"Every %d hours"` |
| `"每周"` | `per_week` | `"Weekly"` |

### NotificationService.swift（6 个）

| 当前中文 | Key | 英文 |
|---------|-----|------|
| `"DevBar 额度提醒"` | `notif_low_quota_title` | `"DevBar Quota Alert"` |
| `"您的 %@ 额度即将用完，还剩 %d%%"` | `notif_low_quota_body` | `"Your %@ quota is running low, %d%% remaining"` |
| `"DevBar 额度用尽"` | `notif_exhausted_title` | `"DevBar Quota Exhausted"` |
| `"您的 %@ 额度已用完，请及时充值"` | `notif_exhausted_body` | `"Your %@ quota is exhausted, please recharge"` |
| `"DevBar 额度重置"` | `notif_reset_title` | `"DevBar Quota Reset"` |
| `"您的 %@ 额度已重置，可以继续使用"` | `notif_reset_body` | `"Your %@ quota has been reset, ready to use"` |

### BigModelAPIClient.swift — APIError（5 个）

| 当前中文 | Key | 英文 |
|---------|-----|------|
| `"未登录"` | `not_logged_in` | `"Not logged in"` |
| `"无效的响应"` | `invalid_response` | `"Invalid response"` |
| `"请求失败 (%d)"` | `http_error` | `"Request failed (%d)"` |
| `"登录已过期，请重新登录"` | `login_expired` | `"Session expired, please log in again"` |
| `"数据解析失败: %@"` | `decoding_failed` | `"Data parsing failed: %@"` |

### UpdateService.swift — UpdateError（6 个）

| 当前中文 | Key | 英文 |
|---------|-----|------|
| `"网络错误: %@"` | `network_error` | `"Network error: %@"` |
| `"未找到发布版本"` | `no_release_found` | `"No release found"` |
| `"未找到可用的更新包"` | `no_update_package` | `"No update package found"` |
| `"下载失败"` | `download_failed` | `"Download failed"` |
| `"更新包无效"` | `invalid_package` | `"Invalid update package"` |
| `"安装失败: %@"` | `installation_failed` | `"Installation failed: %@"` |

### UpdateViewModel.swift（2 个）

| 当前中文 | Key | 英文 |
|---------|-----|------|
| `"DevBar 更新"` | `devbar_update` | `"DevBar Update"` |
| `"未找到可用的更新包"` | `no_update_package` | （复用） |

### AppViewModel.swift（1 个）

| 当前中文 | Key | 英文 |
|---------|-----|------|
| `"设置"` | `settings` | `"Settings"` |

### 语言选择器（1 个）

| Key | 英文 | 中文 |
|-----|------|------|
| `follow_system` | `"Follow System"` | `"跟随系统"` |

**总计：约 95 个本地化条目**

## 三、实现步骤

### 阶段 1：基础设施（3 个文件）

1. **创建 `LanguageManager.swift`**
   - `AppLanguage` 枚举：`.system` / `.zhHans` / `.en`
   - `@AppStorage("app_language")` 持久化
   - `currentLocale` 计算属性
2. **创建 `Localizable.xcstrings`**
   - 添加 `en` 和 `zh-Hans`
   - 录入所有 key-value 对
3. **更新 `project.pbxproj`**
   - 添加 `zh-Hans` 到 `knownRegions`
   - 添加资源引用

### 阶段 2：重构 SettingsTab（1 个文件）

- `rawValue` 改为英文标识符
- 添加 `localizedName` 计算属性
- 更新所有引用 `tab.rawValue` 的地方

### 阶段 3：替换所有硬编码字符串（约 15 个文件）

逐文件替换，按以下顺序：
1. Views（MenuBarView、LoginView、Settings*、UpdateView、QuotaRowView）
2. Models（SettingsTab、QuotaResponse）
3. ViewModels（AppViewModel、QuotaViewModel、UpdateViewModel）
4. Services（NotificationService、BigModelAPIClient、UpdateService）

### 阶段 4：语言切换器 UI

- 在 SettingsGeneral 中添加语言 Picker
- 选项：跟随系统 / 简体中文 / English

### 阶段 5：环境注入

- `DevBarApp.swift`：注入 `.environment(\.locale, ...)`
- `AppViewModel.showSettings()`：NSHostingView 注入 locale
- `UpdateViewModel.showWindow()`：NSHostingView 注入 locale

### 阶段 6：修复日期格式化

- `Extensions.swift`：`DateFormatter` 根据当前 locale 动态切换

## 四、文件结构

```
DevBar/
├── DevBar/
│   ├── Resources/
│   │   └── Localizable.xcstrings        # 新建：String Catalog
│   ├── Utils/
│   │   ├── LanguageManager.swift         # 新建：语言管理
│   │   ├── Extensions.swift             # 修改：日期格式化
│   │   └── Constants.swift
│   ├── Models/
│   │   ├── SettingsTab.swift            # 修改：rawValue 改英文
│   │   └── QuotaResponse.swift          # 修改：显示名本地化
│   ├── Views/
│   │   ├── MenuBarView.swift            # 修改
│   │   ├── LoginView.swift              # 修改
│   │   ├── SettingsView.swift           # 修改
│   │   ├── SettingsGeneral.swift        # 修改：+语言选择器
│   │   ├── SettingsNotifications.swift  # 修改
│   │   ├── SettingsAbout.swift          # 修改
│   │   ├── UpdateView.swift             # 修改
│   │   └── QuotaRowView.swift           # 修改
│   ├── ViewModels/
│   │   ├── AppViewModel.swift           # 修改
│   │   ├── QuotaViewModel.swift         # 修改
│   │   └── UpdateViewModel.swift        # 修改
│   ├── Services/
│   │   ├── NotificationService.swift    # 修改
│   │   ├── BigModelAPIClient.swift      # 修改
│   │   └── UpdateService.swift          # 修改
│   └── DevBarApp.swift                  # 修改：环境注入
```

## 五、风险与缓解

| 风险 | 严重程度 | 缓解措施 |
|------|---------|---------|
| String Catalog 条目遗漏 | 中 | 逐文件 grep 中文硬编码字符串验证 |
| SettingsTab rawValue 变更导致 `@AppStorage` 旧值不匹配 | 中 | 迁移：检测到旧值时自动映射到新值 |
| NSWindow 中的视图不响应 locale 变化 | 高 | 创建 NSHostingView 时显式注入 `.environment(\.locale)` |
| 带参数的字符串插值提取错误 | 中 | 使用 `String(localized:)` 显式指定 key |
| 语言切换后部分 UI 不刷新 | 中 | LanguageManager 作为 @EnvironmentObject 传递 |
