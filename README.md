<p align="center">
  <img src="DevBar/appstore.png" alt="DevBar" width="120" height="120">
</p>

<h1 align="center">DevBar （开发吧）</h1>

<div align="center">
**English** · [简体中文](README_zh.md)
</div>


<p align="center">
  <strong>A macOS menu bar tool for monitoring Zhipu BigModel API usage in real time</strong><br>
  <a href="#Installation">Installation</a> · <a href="#features">Features</a> · <a href="#preview">Preview</a> · <a href="#development">Development</a>
</p>

---

## Features

- **Menu Bar Display** — Shows the highest usage percentage directly in the macOS menu bar
- **Token Usage Monitoring** — Real-time progress of Token and time usage with dynamic color indicators
- **MCP Usage Breakdown** — Per-model MCP call counts (search-prime, web-reader, etc.)
- **Subscription Management** — Auto-detects plan validity, shows expiry date and renewal price
- **Multiple Login Methods** — Browser login (QR code / account) and API Key login
- **Local Notifications** — Low quota alerts, exhaustion alerts, quota reset alerts with smart debouncing
- **Auto Refresh** — Configurable 3/5/10/30-minute intervals or manual refresh, auto-pause when closed
- **Tabbed Settings** — Organized into General, Notifications, and About tabs
- **Dock Visibility Control** — Option to hide from the Dock
- **Customizable Icon** — Choose from 10 SF Symbol icons
- **Auto Update Check** — Background update check when settings are opened

## Installation

### Download from Release

Download the latest `.dmg` or `.zip` file and drag DevBar into your Applications folder.

### Build from Source

```bash
git clone https://github.com/xjpz/DevBar.git
cd DevBar
open DevBar.xcodeproj
```

Select `My Mac` as the run destination in Xcode and press `Cmd + R`.

**System Requirements:** macOS 14.0+

## Usage

1. **Login**
   - **Browser Login** — Click "Browser Login" → Scan QR code or sign in with your account
   - **API Key Login** — Click "API Key Login" → Enter API Key → Click "Login"
2. **View Usage** — Click the menu bar icon to expand the panel and view Token / MCP usage
3. **Manual Refresh** — Click the refresh button to fetch the latest data
4. **Settings** — Click the gear icon to open the settings panel
   - **General** — Switch menu bar icon, adjust refresh interval, launch at login, Dock visibility
   - **Notifications** — Enable low quota / exhaustion / reset alerts, set low quota threshold
   - **About** — View version info, GitHub repository, check for updates

## Preview

![Preview](preview.png)

## Development

- **SwiftUI** — Native macOS UI framework
- **MenuBarExtra** — Menu bar integration (`.window` style)
- **MVVM** — Clean separation of Models / Views / ViewModels
- **Keychain Services** — Secure credential storage
- **UserNotifications** — Local notification support
- **URLSession** — HTTP API requests

## Project Structure

```
DevBar/
├── DevBarApp.swift                # App entry point, MenuBarExtra config
├── Models/
│   ├── AuthCredentials.swift      # Auth credentials (Token + Cookie)
│   ├── NotificationSettings.swift # Notification settings model
│   ├── QuotaResponse.swift       # Usage API response model
│   ├── SettingsTab.swift         # Settings tab enum
│   └── SubscriptionResponse.swift # Subscription API response model
├── Services/
│   ├── BigModelAPIClient.swift   # Zhipu BigModel API client
│   ├── AuthService.swift         # Authentication state management
│   ├── KeychainService.swift     # Keychain storage service
│   └── NotificationService.swift # Notification service (permissions, sending, debounce)
├── ViewModels/
│   ├── AppViewModel.swift        # Global app state
│   ├── QuotaViewModel.swift     # Usage data & refresh logic
│   └── UpdateViewModel.swift    # Auto update check
├── Views/
│   ├── MenuBarView.swift        # Main popup panel
│   ├── LoginView.swift          # Browser login flow
│   ├── QuotaRowView.swift       # Single usage progress bar
│   ├── SettingsView.swift       # Settings panel container
│   ├── SettingsGeneral.swift    # General settings
│   ├── SettingsNotifications.swift # Notification settings
│   └── SettingsAbout.swift      # About page
└── Utils/
    ├── Constants.swift          # API URLs, default config
    └── Extensions.swift         # Date/String extensions
```

## API

| Endpoint | Description | Frequency |
|----------|-------------|-----------|
| `GET /api/biz/subscription/list` | Fetch subscription list | Once after login |
| `GET /api/monitor/usage/quota/limit` | Fetch usage quota | Periodic refresh |

Authentication: `Authorization` header + `bigmodel_token_production` cookie.

## Configuration

| Setting | Default | Description |
|---------|---------|-------------|
| Auto refresh interval | 5 minutes | 3/5/10/30 min / hourly / never |
| Low quota alert threshold | 20% | 10/20/30/50% |
| Low quota notification cooldown | 30 minutes | Same threshold notified at most once per 30 min |
| Menu bar icon | sparkles | 10 SF Symbol options |
| Dock visibility | Visible | Can be hidden |

## License

MIT License
