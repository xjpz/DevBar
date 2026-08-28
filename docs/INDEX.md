# DevBar 设计文档索引

新设计必须登记状态；既有文档在人工确认前统一视为 `legacy-unclassified`，不得据此推断已获实施或发布授权。

| 文档 | 状态 | 范围 | 审批 | 验证 | 提交/发布 | 待办 |
| --- | --- | --- | --- | --- | --- | --- |
| `ios-mac-relay-workbench-redesign.md` | verified | iPhone Tools 的单 Mac Relay 状态与快捷控制 | 最终改选预览 1 上半部分；移除远程任务和任务状态；网速替代显示器指标；禁用按钮置灰 | Core 305 测试通过；`codex-verify build` 通过；待真机双路径验收 | 未提交、未发布 | iPhone + Mac 验收局域网/远程路径及三项控制 |
| `mac-relay-device-identity-recovery-design.md` | verified | macOS 中继 `invalid_device_secret` 安全恢复、旧配对清理与 Keychain 防复发 | 用户回复“开始实现”批准 | Core 292 测试；macOS/iOS Simulator Debug 构建通过；diff/本地化 JSON 校验通过 | 未提交、未发布 | 安装 Mac 构建后执行身份重置、真机扫码与远程/局域网双路径验收 |
| `push-message-persistence-account-link-design.md` | verified | Apple 登录账号、iPhone 设备归属、Device Push Key 与普通 Push 业务消息持久化闭环 | 已批准实施 | Core 284 测试；服务端聚焦 38 测试；两仓库 build 通过 | 未提交、未发布 | 独立 MySQL evolution 验证、生产 migration/部署/真机 APNs 另行授权 |
| `ios-apns-token-registration-recovery-design.md` | verified | iOS 普通 APNs token 当前进程所有权与串行注册恢复 | 用户回复“修复”批准 | Core 260 测试；macOS/iOS 编译通过 | 未提交、未发布 | 安装更新 Debug 包并做真机 APNs 验收 |
| `push-notification-url-opening-design.md` | verified | Device Push Key 文本通知 URL 点击打开（DevBar iOS + playdev-server） | 已批准并实施 | 服务端 20 测试；Core 251 测试；macOS/iOS 编译通过 | 未提交、未发布 | 真机 APNs 点击验收 |
| `ios-home-assistant-heartbeat-crash-fix-design.md` | implemented | iOS Home Assistant WebSocket 心跳 continuation 重复恢复崩溃 | 已回复“开始实现” | Home Assistant 54 项；`codex-verify fast` 335 项；`codex-verify build` 通过 | 未提交、未发布 | 生成新 TestFlight 后在受影响 iOS 27 真机复测 |
| 既有文档 | legacy-unclassified | 待核对 | 未知 | 未知 | 未知 | 按需逐项补录 |

状态使用：`draft`、`awaiting-approval`、`approved`、`implemented`、`verified`、`deployed`、`superseded`。

新文档 front matter 参考 `/Users/xjpz/Documents/Codex/.codex/templates/design-frontmatter.yaml`。本仓库 `docs/` 当前被忽略，提交文档前需单独确认版本控制策略。
