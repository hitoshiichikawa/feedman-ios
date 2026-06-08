# Feedman iOS

Feedman RSS reader の iOS client です。

## Stack

- Swift + SwiftUI
- iOS 16+
- MVVM + Repository
- URLSession + Codable
- ASWebAuthenticationSession + PKCE token auth

## Inputs

- `design/SPEC-iOS.md`
- `design/SERVER.md`
- `design/Feedman iPhone.html`
- `design/mobile/*.jsx`

## Development

Open `Feedman.xcodeproj` in Xcode and run the `Feedman` scheme on an iOS Simulator.

Linux 上では Xcode build は実行できません。macOS では以下を使います。

```bash
xcodebuild -project Feedman.xcodeproj -scheme Feedman -destination 'platform=iOS Simulator,name=iPhone 16' test
```

## idd-codex

This repository is configured for idd-codex local watcher.

```cron
*/2 * * * * REPO=hitoshiichikawa/feedman-ios REPO_DIR=/home/hitoshi/github/feedman-ios /home/hitoshi/bin/idd-codex-issue-watcher.sh >> /home/hitoshi/.idd-codex/issue-watcher/cron.log 2>&1
```

