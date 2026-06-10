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

## Branch and Release Flow

This repository uses a gitflow-style release model.

- `develop`: integration branch for normal development and idd-codex PRs.
- `release/x.y.z`: release-candidate branch cut from `develop` for App Store build, review, and release fixes.
- `main`: production release branch. Code reaches `main` only after the App Store release is approved and published.

Standard flow:

1. Feature and fix PRs target `develop`.
2. Merged issues remain open after `develop` merge and may be marked `codex-staged-for-release`.
3. Cut `release/x.y.z` from `develop` when preparing an App Store submission.
4. Build and submit the app from `release/x.y.z`.
5. Apply review/release fixes to `release/x.y.z`, then back-merge them to `develop`.
6. After the version is approved and publicly released, merge `release/x.y.z` into `main`.
7. Generate release notes from `codex-staged-for-release` issues and close those issues as part of the production release.

GitHub's default branch intentionally remains `main`. Closing keywords such as `Closes #123` should not close issues when PRs merge into `develop`; issues should close only when the corresponding change reaches the production release on `main`.

## idd-codex

This repository is configured for idd-codex local watcher.

Linux / WSL では cron で 2 分ごとに watcher を起動します。

```cron
*/2 * * * * BASE_BRANCH=develop PROMOTION_TARGET_BRANCH=main REPO=hitoshiichikawa/feedman-ios REPO_DIR=/home/hitoshi/github/feedman-ios /home/hitoshi/bin/idd-codex-issue-watcher.sh >> /home/hitoshi/.idd-codex/issue-watcher/cron.log 2>&1
```

macOS では cron ではなくユーザー LaunchAgent を使います。`~/Library/LaunchAgents/` に
plist を置き、`EnvironmentVariables` で少なくとも以下を指定します。

- `BASE_BRANCH=develop`
- `PROMOTION_TARGET_BRANCH=main`
- `REPO=hitoshiichikawa/feedman-ios`
- `REPO_DIR=/Users/<user>/github/github/feedman-ios`

登録と起動:

```bash
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.local.idd-codex-issue-watcher.plist
launchctl kickstart -k gui/$(id -u)/com.local.idd-codex-issue-watcher-feedman-ios
```

`bootstrap` は通常 Terminal.app / iTerm などの GUI ログインセッションから実行します。
SSH や非 GUI セッションから `gui/$(id -u)` を操作すると
`Domain does not support specified action` になることがあります。sudo は通常不要です。

`Bootstrap failed: 5: Input/output error` が出ても、登録と `RunAtLoad` 起動が完了している
場合があります。まず状態とログを確認してください。

```bash
launchctl list com.local.idd-codex-issue-watcher-feedman-ios
tail -f ~/.idd-codex/issue-watcher/cron.log
```

再登録する場合は、既存 job を外してから `bootstrap` します。

```bash
launchctl bootout gui/$(id -u) ~/Library/LaunchAgents/com.local.idd-codex-issue-watcher.plist
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.local.idd-codex-issue-watcher.plist
```

起動済み job を今すぐ再実行するだけなら、再 `bootstrap` ではなく `kickstart` を使います。

```bash
launchctl kickstart -k gui/$(id -u)/com.local.idd-codex-issue-watcher-feedman-ios
```
