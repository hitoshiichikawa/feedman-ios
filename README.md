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

```cron
*/2 * * * * BASE_BRANCH=develop PROMOTION_TARGET_BRANCH=main REPO=hitoshiichikawa/feedman-ios REPO_DIR=/home/hitoshi/github/feedman-ios /home/hitoshi/bin/idd-codex-issue-watcher.sh >> /home/hitoshi/.idd-codex/issue-watcher/cron.log 2>&1
```
