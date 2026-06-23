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
ローカルの build / test は macOS + Xcode 環境を前提にします。

Canonical test command:

```bash
xcodebuild -project Feedman.xcodeproj -scheme Feedman -destination 'platform=iOS Simulator,name=iPhone 16' test
```

`iPhone 16` simulator がローカルに無い場合は、利用可能な iPhone simulator を確認して
`name=` の値を読み替えます。

```bash
xcrun simctl list devices available
```

Linux / non-Xcode 環境では Xcode build/test は実行できません。canonical test は macOS +
Xcode で確認します。

## Configuration

### API base URL

アプリの runtime API origin は `FEEDMAN_API_BASE_URL` で設定します。Scheme の
Environment Variables、または build setting から `Info.plist` の `FeedmanAPIBaseURL` へ展開される
値を使います。`AppEnvironment.production()` はこの設定を解決し、欠落・不正値・`localhost`
指定を起動時に developer-observable な設定不備として扱います。

Simulator から macOS 上の local server に接続する開発用途では、Scheme の Environment Variables に
次のような origin を明示します。

```text
FEEDMAN_API_BASE_URL=http://127.0.0.1:3000
```

Release 相当の確認では local-development origin を使わず、server / release 方針で確定した origin を
同じ `FEEDMAN_API_BASE_URL` として明示してください。正式な production / staging URL はこの
README では未確定値として扱い、仮の endpoint は記載しません。

Debug / Release / Staging / Local の正式な API base URL 文字列は未決です。release
configuration として扱う前に、server / release 方針で確定してください。

API path と response contract は `design/SPEC-iOS.md` と `design/SERVER.md` を正本にします。
README では endpoint table を重複管理しません。セットアップ履歴の背景は
`design/ZERO-TO-IDD-CODEX-NOTES.md` も参照できますが、API / auth contract の正本ではありません。

### Native auth callback

iOS v1 の Google login は `ASWebAuthenticationSession` + PKCE token auth を使います。
`ASWebAuthenticationSession` の `callbackURLScheme` は `feedman` です。

Expected callback shape:

```text
feedman://auth/callback?auth_code=...
```

アプリは受け取った `auth_code` と PKCE `code_verifier` を `POST /api/auth/token` で交換し、
以後は Bearer token、refresh、revoke を `design/SERVER.md` の契約に従って扱います。
Universal Links は後続 Issue で方針変更されない限り、v1 の README / smoke test では
custom scheme `feedman://auth/callback` を対象にします。WebView Cookie login fallback は
v1 の supported path ではありません。

### Mock and preview data

Mock repositories と preview data は SwiftUI preview と unit test 用です。mock data や prototype
JSON の形は authoritative API contract として扱いません。API contract の確認は
`design/SPEC-iOS.md` と `design/SERVER.md` を参照してください。

Unit test は mock repositories を使える範囲では real network、real Keychain、real OAuth に依存させません。
一方、real v1 smoke test は native token auth と v1 API contract を実装した server が必要です。

## v1 Smoke Test Checklist

Release 前や大きな merge 後に、以下の最小導線を実機または iOS Simulator で確認します。
v1 default では keyword notification feature は disabled です。`/api/devices` と
`/api/keywords` は next phase API のため、この checklist の成功条件には含めません。

1. Google login を開始し、`feedman://auth/callback?auth_code=...` から token exchange が完了する。
   生成される native login URL が `flow=native`、`code_challenge`、
   `code_challenge_method=S256` を含むことも確認する。必要に応じてアプリ再起動後の
   session restore も確認し、横断タイムラインが表示される。
2. 横断タイムラインの記事を開き、記事詳細 sheet が表示される。
3. 記事詳細から元記事を開き、`SFSafariViewController` で外部記事が表示される。
4. 一覧または詳細で star / unstar し、Starred list に変更が反映される。
5. drawer から feed を開き、all / unread / starred filter を切り替えられる。
6. feed URL を登録し、subscriptions / drawer refresh 後に新しい購読が確認できる。
7. non-empty query で global search を実行し、検索結果の詳細を開ける。
8. account を表示し、mobile current user が `GET /api/users/me` で取得されることを確認する。
   その後 logout し、unauthenticated login state へ戻る。
9. Account deletion は破壊的操作のため default smoke checklist には含めません。必要な場合だけ
   destructive manual-only check として別途確認します。

## CI

GitHub Actions の `.github/workflows/ios-tests.yml` が、macOS runner 上で Xcode test を実行します。

- check run 名: **`iOS Tests`** (workflow の job name。idd-codex promote pipeline の ST 判定が参照するため変更しない)
- 実行条件: `develop` 向け PR、および `develop` への push (merge を含む)
- 実行内容: `xcodebuild -project Feedman.xcodeproj -scheme Feedman -destination 'platform=iOS Simulator,name=<simulator>' test`

simulator は README / AGENTS.md の検証コマンドと揃えて `iPhone 16` を優先し、runner image に
存在しない場合のみ利用可能な iPhone simulator へ自動で寄せます (選定結果は CI ログの
`Resolve simulator destination` step で確認できます)。

idd-codex promote pipeline の ST gate と接続するには、cron / launchd の watcher 環境変数に
以下を設定します。

```bash
ST_CHECK_RUN_NAME="iOS Tests"
```

GitHub Actions が利用できない場合や simulator 名が変わった場合は、macOS 上で以下の手動検証
コマンドを実行して同等の確認ができます (`iPhone 16` が無い環境では `xcrun simctl list devices available`
で利用可能な iPhone simulator 名に読み替えます)。

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

This repository is configured for idd-codex local watcher. The current setup uses
the idd-codex per-repo env file loader so the launchd / cron entry stays small
and full-auto flags are managed in one local file.

Required GitHub repository settings for automatic development:

- Repository auto-merge: enabled.
- `develop` branch protection required checks: `iOS Tests`, `codex-review`.
- `develop` branch protection strict mode: enabled, so PR branches must be up to date.

Per-repo env file path:

```bash
~/.idd-codex/hitoshiichikawa-feedman-ios.env
```

Recommended idd-codex env-loader file contents for automatic development up to `develop`.
This file is parsed by idd-codex's per-repo env-loader, not sourced as a shell script.
For values containing spaces, write the raw value without shell quotes.

```text
FULL_AUTO_ENABLED=true
PR_REVIEWER_ENABLED=true
PR_REVIEWER_TOOL=codex
PR_REVIEWER_STATUS_CHECK_ENABLED=true
AUTO_MERGE_ENABLED=true
AUTO_MERGE_DESIGN_ENABLED=true
FAILED_RECOVERY_ENABLED=true
NEEDS_DECISIONS_MODE=classified
STALE_PICKUP_REAPER_ENABLED=true

AUTO_REBASE_MODE=codex
AUTO_REBASE_SEMANTIC=on
MECHANICAL_PATHS=README.md

DEPENDENCY_AUTO_UNBLOCK_ENABLED=true
BLOCKED_CYCLE_DETECTION_ENABLED=true
PATH_OVERLAP_CHECK=true

MERGE_QUEUE_ENABLED=true
MERGE_QUEUE_RECHECK_ENABLED=true
PR_ITERATION_ENABLED=true
PR_ITERATION_DESIGN_ENABLED=true
DESIGN_REVIEW_RELEASE_ENABLED=true
QUOTA_AWARE_ENABLED=true
RUN_SUMMARY_ENABLED=true
TC_ENABLED=true
STAGE_CHECKPOINT_ENABLED=true
PER_TASK_LOOP_ENABLED=true
DEBUGGER_ENABLED=true
IDD_CODEX_HOOKS_ENABLED=true
SCAFFOLDING_HEALTH_HALT=on
PARALLEL_SLOTS=4

# iOS local verification is kept off in watcher; CI is the verification gate.
STAGE_A_VERIFY_ENABLED=false

# Release/promote automation is separate from automatic development.
PROMOTE_PIPELINE_ENABLED=false
PROMOTION_TARGET_BRANCH=main
PROMOTE_MODE=on-demand
ST_CHECK_RUN_NAME=iOS Tests
```

Linux / WSL では cron で 2 分ごとに watcher を起動します。

```cron
*/2 * * * * BASE_BRANCH=develop REPO=hitoshiichikawa/feedman-ios REPO_DIR=/home/hitoshi/github/feedman-ios WATCHER_ENV_FILE=/home/hitoshi/.idd-codex/hitoshiichikawa-feedman-ios.env /home/hitoshi/bin/idd-codex-issue-watcher.sh >> /home/hitoshi/.idd-codex/issue-watcher/cron.log 2>&1
```

macOS では cron ではなくユーザー LaunchAgent を使います。`~/Library/LaunchAgents/` に
plist を置き、`EnvironmentVariables` で少なくとも以下を指定します。

- `BASE_BRANCH=develop`
- `REPO=hitoshiichikawa/feedman-ios`
- `REPO_DIR=/Users/<user>/github/github/feedman-ios`
- `WATCHER_ENV_FILE=/Users/<user>/.idd-codex/hitoshiichikawa-feedman-ios.env`

`xcodebuild` を watcher から実行する macOS 環境で active developer directory が Command Line Tools
を指している場合のみ、`DEVELOPER_DIR` を任意で追加します。値は環境ごとの Xcode developer directory
に合わせ、`xcode-select -p` が Xcode を指している環境では固定指定しません。

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
