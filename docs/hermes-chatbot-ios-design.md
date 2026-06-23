# Hermes ChatBot iOS Integration Design

Date: 2026-06-23
Status: design for review; implementation is gated on approval
Branch observed: `develop` at commit `1db8ac5`

## Goal

接入 Hermes API Server 到 DevBar 手机端，新增底部导航入口 `ChatBot`，提供一个参考截图风格的 Hermes Chat 页面。设置页新增 Hermes 配置页，可设置 API Base URL、API Key、是否启用流式输出；同时允许用户在设置中隐藏底部 `WebKit` tab。

本设计只覆盖 iPhone 端首版，不改变 macOS 菜单栏、widget、Live Activity、Provider quota 账户体系。

## Current App Context

当前 iOS 根入口是 `IOSRootView`，底部 tab 由 `IOSAppViewModel.TabSelection` 驱动，现有 tab 为：

- `dashboard`: Dashboard / Overview
- `webkit`: WebKit
- `tools`: Tools

设置入口目前在 Dashboard 顶部 toolbar，`IOSSettingsView` 是一个 Form，按外观、AI quota、设备系统、通知、关于分组。敏感凭据已经通过 `DevBarCore.KeychainService` 保存，普通设置通过 `UserDefaults` / store 类型保存。主题视觉通过 `IOSThemeTokens`、`.iosGeekScreenBackground`、`.iosGlassContainer` 统一。

## Design Brief

产品行为：用户可以在 iPhone 端打开 `ChatBot`，向 Hermes Agent 发送问题，查看普通文本、代码块、错误提示和流式增量回复。

视觉来源：用户提供的 Hermes Chat 截图。首版应复用 DevBar 现有主题 token，并吸收截图里的深色聊天布局、紫色品牌强调、在线状态、记忆提示条、左右消息气泡、代码块容器和底部输入栏。

交互级别：首版实现完整可用交互，包括配置保存、tab 显示开关、发送消息、加载/流式状态、错误恢复、复制内容。截图中的历史、更多菜单、查看记忆、展开日志、创建任务可以先作为非首版能力，不在本轮实现。

## Recommended Approach

推荐采用“Core API/Settings + iOS UI/ViewModel”的拆分：

- `DevBarCore` 新增 Hermes 配置模型、settings store、API client 和 chat 数据模型。
- `DevBariOS` 新增 `IOSHermesChatViewModel`、`IOSHermesChatView`、`IOSHermesSettingsView`，并扩展 `IOSRootView` tab 渲染。
- API client 隔离 Hermes 请求/响应协议，UI 不直接拼 URLRequest。

这样可以让网络协议、Keychain、UserDefaults、UI 状态互相隔离，后续若 macOS 也要接 Hermes，可复用 Core 层。

### Alternatives Considered

1. 只在 iOS 目录内实现 Hermes client 和存储。
   优点是改动少；缺点是 Keychain key、配置模型、API 协议会和现有 provider 体系分叉，后续复用成本高。

2. 把 Hermes 纳入现有 `QuotaProvider` / accounts 体系。
   优点是复用账户管理 UI；缺点是 Hermes 是聊天能力，不是 quota provider，强行挂到 provider 会污染账户语义。

3. 推荐方案：Core 放通用配置/API，iOS 放聊天体验。
   兼顾边界清晰和首版速度，是本次最稳妥方案。

## Navigation And Settings

### Bottom Tabs

`IOSAppViewModel.TabSelection` 新增：

- `chatbot`

`IOSRootView` tab 顺序建议：

1. Dashboard
2. ChatBot
3. WebKit, when enabled
4. Tools

`ChatBot` 使用 SF Symbol `bubble.left.and.bubble.right.fill` 或 `sparkle.magnifyingglass`，文案首版按用户暂定使用 `ChatBot`。如果未来要本地化，新增 `ios_tab_chatbot`。

### WebKit Visibility

新增设置项：

- UserDefaults key: `ios_webkit_tab_enabled`
- 默认值：`true`
- 设置位置：`IOSSettingsView` 新增“导航”或“功能入口”分组
- 行为：关闭后底部 tab 不展示 WebKit；如果当前正在 WebKit tab，立即切回 Dashboard 或 ChatBot。

该设置只影响底部入口，不删除 WebKit 功能代码，不影响内部历史数据。

### Hermes Settings

`IOSSettingsView` 新增 Hermes 设置入口，建议放在 AI quota 分组之后或新增 AI Features 分组：

- API Base URL: TextField，URL keyboard，禁用自动大写和纠错
- API Key: SecureField，保存在 Keychain
- Streaming Output: Toggle，保存在 UserDefaults
- Connection Test: 可选首版按钮，发送轻量请求验证 base URL 和 key

配置摘要：

- 已配置：显示 `Configured`
- 未配置：显示 `API Key required`
- Base URL 无效：显示 `Invalid URL`

## Hermes API Contract

实现前需要以 Hermes API Server 实际文档确认协议。首版 adapter 先按 OpenAI-compatible Chat Completions 形状设计，因为现有 DevBar 已有类似 `BigModelAPIClient.sendPing` 的 chat-completions 请求经验：

Request:

```json
{
  "messages": [
    { "role": "system", "content": "..." },
    { "role": "user", "content": "..." }
  ],
  "stream": true
}
```

Headers:

- `Authorization: Bearer <api-key>`
- `Content-Type: application/json`
- `Accept: application/json` for non-streaming
- `Accept: text/event-stream` for streaming

The final implementation should keep endpoint path composition inside `HermesAPIClient`, for example by normalizing Base URL and appending the Hermes server chat path. If Hermes uses a non-OpenAI protocol, only the adapter models should change; `IOSHermesChatViewModel` should keep the same send/stream interface.

## Storage

Add constants in `DevBarCoreConstants`:

- Keychain: `hermesAPIKeyKey = "hermes_api_key"`
- Defaults: `hermesAPIBaseURLKey = "hermes_api_base_url"`
- Defaults: `hermesStreamingEnabledKey = "hermes_streaming_enabled"`
- Defaults: `iosWebKitTabEnabledKey = "ios_webkit_tab_enabled"`

Suggested defaults:

- API Base URL: empty string unless the user provides an official default before implementation
- Streaming: `true`
- WebKit tab visible: `true`

API Key stays in Keychain. Base URL and streaming preference stay in UserDefaults. Chat messages are in-memory for the first version; persistent chat history is intentionally out of scope.

## ChatBot Screen

### Layout

Use a full-screen `NavigationStack` child under the tab, with hidden/transparent nav background like Dashboard.

Top region:

- leading menu icon reserved for future conversations
- Hermes avatar mark using SF Symbol or bundled asset
- title `Hermes Chat`
- subtitle `Hermes Agent 在线` when configured, otherwise `Hermes 未配置`
- trailing history/more buttons reserved or disabled if not implemented

Memory banner:

- show a glass container matching the screenshot
- copy: `会话记忆已启用` / `已载入你的长期记忆、技能和项目上下文`
- action button `查看记忆` can be disabled or hidden in首版 if no memory endpoint exists

Message list:

- user messages align trailing with purple gradient bubble
- assistant messages align leading in a glass card
- assistant header shows `Hermes Agent` and timestamp
- support Markdown-ish rendering for paragraphs, numbered lists and fenced code blocks
- code blocks have monospaced font, border, filename/language label, copy button

Composer:

- bottom safe-area input bar
- attachment icon reserved but disabled in首版
- input hint `输入你的问题...`
- send button purple circular icon
- disable send when API Key/Base URL missing, input empty, or request in flight
- show stop button during streaming if cancellation is implemented

### States

- Empty: show compact prompt suggestions inside the message area, not a marketing page.
- Missing config: show inline configuration card with a Settings navigation link.
- Sending: append user message immediately, then assistant draft bubble with typing indicator.
- Streaming: append tokens into the active assistant message.
- Error: assistant card shows readable error and a retry button.
- Offline/no network: same error surface, preserving the user draft.

## View Model

`IOSHermesChatViewModel` responsibilities:

- load Hermes settings snapshot
- validate configuration
- maintain `[HermesChatMessage]`
- send user prompt
- choose streaming/non-streaming path from settings
- cancel active stream
- expose UI state: idle, sending, streaming, failed

It should not own Keychain writes. Settings writes remain in the settings store / settings view model path.

Core models:

- `HermesSettings`
- `HermesChatMessage`
- `HermesChatRole`
- `HermesChatRequest`
- `HermesChatResponse`
- `HermesStreamEvent`
- `HermesAPIClient`
- `HermesSettingsStore`

## Streaming Design

Use `URLSession.bytes(for:)` for streaming when Hermes returns SSE or newline-delimited chunks. The parser should live in Core and emit an `AsyncThrowingStream<String, Error>` of text deltas.

Non-streaming should call the same API client and return a final assistant message. The UI path should be nearly identical: create an assistant draft bubble, then either append deltas or replace content once.

Cancellation should cancel the active Task and mark the partial assistant response as stopped, not failed.

## Localization

Add localized keys for:

- tab: ChatBot
- settings section and Hermes settings labels
- missing configuration state
- composer input hint and error actions
- streaming toggle
- WebKit tab visibility toggle

Existing tests include localization resource checks, so new keys should be covered by the same resource validation.

## Accessibility

- message bubbles expose role and timestamp
- send button has an accessibility label
- copy code buttons identify the code block language/title
- streaming updates should avoid excessive VoiceOver announcements; announce completion or failure
- settings fields use clear labels and secure text entry for API Key

## Testing Plan

Unit tests:

- Hermes settings store default/load/save behavior
- Base URL normalization and invalid URL rejection
- API Key Keychain save/load/delete via existing test pattern if available
- streaming parser handles data chunks, done event and malformed event
- WebKit visibility default is enabled

iOS view/model tests where feasible:

- selecting hidden WebKit tab falls back to a visible tab
- send disabled when Hermes config is incomplete
- non-streaming success appends user and assistant messages
- streaming success appends deltas in order
- cancellation preserves partial content

Manual verification:

- iPhone Simulator: Dashboard / ChatBot / WebKit / Tools tab layout
- Settings toggles WebKit tab off and on
- Hermes settings save, clear and survive app restart
- Chat page renders long Chinese text, numbered lists and code blocks without overlap
- Dark/geek/light theme smoke check

## Implementation Sequence After Approval

1. Add Core constants, settings model/store and Hermes API client.
2. Add iOS app state for Hermes settings and WebKit tab visibility.
3. Add Hermes settings page and Settings entry.
4. Add ChatBot tab and fallback behavior when WebKit is hidden.
5. Build ChatBot UI and view model with non-streaming path.
6. Add streaming parser and streaming UI updates.
7. Add tests and localization keys.
8. Run targeted Swift tests and iOS build/simulator smoke check.

## Out Of Scope For First Version

- persistent chat history
- multiple conversations
- memory browser implementation
- attachment upload
- creating tasks from chat
- log expansion actions
- macOS Hermes UI
- Hermes server deployment or API schema changes

## Review Notes

The only implementation detail that must be confirmed before coding is the Hermes API Server chat endpoint and response format. The design intentionally isolates that uncertainty inside `HermesAPIClient`, so the UI and settings work can remain stable once the API contract is known.
