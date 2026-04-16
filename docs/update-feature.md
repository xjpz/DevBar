# 实现计划: DevBar 自动更新功能

## Context

DevBar 当前通过 GitHub Releases + DMG 分发，用户需要手动检查和下载新版本。需要增加自动检查更新、提醒、下载并安装重启的完整更新流程，提升用户体验。

**方案**: 自定义实现（不引入 Sparkle），通过 GitHub Releases API 检查更新，下载 zip 包后程序化解压替换并重启。Release 同时上传 DMG（手动安装）和 zip（自动更新用）。

## 新增文件 (4 个)

| 文件 | 说明 |
|------|------|
| `DevBar/Models/GitHubRelease.swift` | GitHub API 响应模型 (~40 行) |
| `DevBar/Services/UpdateService.swift` | 检查/下载/安装更新核心逻辑 (~200 行) |
| `DevBar/ViewModels/UpdateViewModel.swift` | 更新状态管理 (~80 行) |
| `DevBar/Views/UpdateView.swift` | 更新提醒+下载进度+安装 UI (~120 行) |

## 修改文件 (4 个)

| 文件 | 修改内容 |
|------|----------|
| `DevBar/Utils/Constants.swift` | 添加 `Update` 常量枚举 + 2 个 UserDefaults key |
| `DevBar/ViewModels/AppViewModel.swift` | 添加 `updateViewModel` 属性 + 启动时触发检查 |
| `DevBar/DevBarApp.swift` | 传递 `updateViewModel` 环境对象 |
| `DevBar/Views/MenuBarView.swift` | footer 添加"检查更新"按钮 + UpdateView sheet |

## 实现步骤

### Step 1: Constants 扩展
- 在 `Constants` 中新增 `Update` 枚举: owner, repo, releasesURL, checkInterval(24h), launchDelay(5s)
- 在 `Defaults` 中新增 `lastUpdateCheckKey`, `skippedVersionKey`

### Step 2: GitHubRelease 模型
- `GitHubRelease`: tagName, name, body, htmlUrl, assets, publishedAt
- `GitHubAsset`: name, browserDownloadUrl, size
- 均遵循 `Codable, Sendable`，与现有模型风格一致

### Step 3: UpdateService
- `checkForUpdates() async throws -> GitHubRelease?` — GET GitHub latest release API，比较版本号
- `isUpdateAvailable(remoteTag:) -> Bool` — SemVer 三段式比较（strip `v` 前缀）
- `downloadAsset(from:progress:) async throws -> URL` — URLSession 下载到临时目录，回调进度
- `installAndRelaunch(from:) throws` — ditto 解压 → bash 脚本等待进程退出 → rm -rf 旧 app → mv 新 app → open 重启
- `shouldCheckForUpdate() -> Bool` — 24h 间隔判断 + 跳过版本判断
- `UpdateError` 枚举: 网络错误/无 asset/下载失败/无效压缩包/安装失败

### Step 4: UpdateViewModel
- `UpdateState` 枚举: idle / checking / available(release) / downloading(progress) / downloaded(zipURL) / installing / error(String) / upToDate
- `@Published var state` + `@Published var showUpdateSheet`
- `checkForUpdates(silent:)` — silent=true 仅在有更新时弹出；silent=false 手动触发时显示结果
- `downloadUpdate()` / `installAndRelaunch()` / `skipThisVersion()` / `openReleasePage()`

### Step 5: UpdateView UI
- Sheet 形式弹出，三个状态:
  - **发现更新**: 版本号 + release notes + "跳过此版本"/"查看详情"/"立即更新"按钮
  - **下载中**: 进度条 + 百分比 + "取消"按钮
  - **下载完成**: "需要重启应用" + "稍后"/"立即重启"按钮
  - **已是最新**: 提示文字，2 秒后自动关闭

### Step 6: AppViewModel 集成
- 添加 `let updateViewModel = UpdateViewModel()`
- 在 `appDidFinishLaunching()` 中延迟 5s 调用 `updateViewModel.checkForUpdates(silent: true)`

### Step 7: 环境对象传递 + UI 挂载
- `DevBarApp.swift`: `.environmentObject(appViewModel.updateViewModel)`
- `MenuBarView.swift` footer: 在"退出登录"前添加"检查更新"按钮，有新版本时显示圆点标记
- `.sheet(isPresented: $updateViewModel.showUpdateSheet)` 展示 `UpdateView`

## 安装重启策略

```
1. ditto 解压 zip 到临时目录
2. 验证解压产物包含 DevBar.app
3. 通过 Bundle.main.bundleURL 获取当前安装路径（兼容非 /Applications 安装）
4. 启动 bash 后台脚本:
   while kill -0 <当前PID>; do sleep 0.5; done
   rm -rf <当前app路径>
   mv <新app路径> <当前app路径>
   open <当前app路径>
5. NSApplication.shared.terminate(nil)
```

## 验证方式

1. 构建并运行应用，5 秒后检查控制台是否输出更新检查日志
2. 发布一个测试 Release（如 v99.0.0）附带 DevBar.zip，验证弹出更新提醒
3. 点击"立即更新"，验证下载进度条正常
4. 下载完成点击"立即重启"，验证应用替换并重启
5. 重启后验证版本号正确
6. 测试"跳过此版本"后不再自动提醒
7. 测试无网络时静默处理不影响正常功能
