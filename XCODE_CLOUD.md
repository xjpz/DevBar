# Xcode Cloud TestFlight 工作流

## 发布约定

- 工作流名称：`TestFlight Tags`
- 触发类型：`Tag Changes`
- 标签规则：`Tags beginning with testflight/`
- 构建动作：Archive `DevBariOS` scheme
- 发布动作：成功归档后发布到 TestFlight 内部测试
- 不配置 App Store 发布动作，避免测试标签触发正式上架

Xcode Cloud 的标签条件填写前缀 `testflight/`，不是把 `testflight/*` 作为标签名称或正则表达式填写。

## 创建测试构建

标签需要指向已经推送到远端的提交。示例：

```bash
git tag -a testflight/1.3.0-18 -m "TestFlight 1.3.0 (18)"
git push origin testflight/1.3.0-18
```

推送后由 Xcode Cloud 自动分配递增构建号、归档 iOS App，并把成功构建加入 TestFlight 内部测试。标签命名中的版本和构建号用于人工识别，不负责覆盖 Xcode Cloud 的构建号。

## 仓库前置条件

`DevBar.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved` 必须提交，以便 Xcode Cloud 使用与本地一致的 Swift Package 版本。
