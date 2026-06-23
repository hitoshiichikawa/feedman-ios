# Feedman iOS プロジェクトガイド

このファイルは Codex CLI 本体および idd-codex の全サブエージェントが毎回参照するプロジェクト憲章です。
作業開始前に必ず読み直してください。

## 言語方針

- 内部 reasoning は英語ベースで行う。
- GitHub Issue / PR / review comment / `docs/specs/*` は日本語で書く。
- EARS の `When` / `If` / `While` / `Where` / `shall` は英語固定。
- Conventional Commits の prefix と branch slug は英語固定。
- Swift の型名、識別子、ファイル名は英語固定。

## 技術スタック

- Platform: iOS 16+
- Language: Swift
- UI: SwiftUI
- Architecture: MVVM + Repository
- Async: Swift Concurrency (`async` / `await`)
- Network: `URLSession` + `Codable`
- Auth: `ASWebAuthenticationSession`, PKCE, Bearer token, Keychain
- External article view: `SFSafariViewController`
- Project: standard `.xcodeproj`
- Tests: XCTest

## 正本となる仕様

- 要求仕様: `design/SPEC-iOS.md`
- サーバー追加仕様: `design/SERVER.md`
- 視覚基準: `design/Feedman iPhone.html`
- デザイン部品: `design/mobile/*.jsx`
- idd-codex issue backlog: `design/IDD-CODEX-ISSUES.md`
- ゼロ開始手順メモ: `design/ZERO-TO-IDD-CODEX-NOTES.md`

仕様が衝突した場合は、API 契約は `design/SPEC-iOS.md` と `design/SERVER.md` を優先し、見た目は prototype を参考にする。mock data の JSON 形を API 契約として扱わない。

## v1 スコープ

- Google ログイン（native token auth）
- 横断タイムライン
- フィード別記事一覧
- 記事詳細 sheet
- 既読・スター
- SFSafariViewController で元記事を開く
- スター一覧
- 横断検索
- フィード登録
- 購読設定
- アカウント、ログアウト、退会

## v1 スコープ外

- キーワードプッシュ通知
- OPML import/export
- フィード URL 変更 UI
- オフライン全文 cache
- Feed-scoped search UI
- WebView Cookie login fallback

キーワード通知の UI 案は prototype に存在するが、v1 では drawer 導線も非表示にする。

## アーキテクチャ方針

- Feature は `Feedman/Features/<FeatureName>` 配下に置く。
- 共有 UI は `Feedman/DesignSystem` に置く。
- API 型、API client、repository protocol は `Feedman/Core` に置く。
- View は直接 `URLSession` や Keychain を触らない。
- Repository は protocol を先に定義し、mock と real implementation を差し替え可能にする。
- ViewModel は UI 状態と user action の調停に集中する。
- API の日付文字列は decode 時に `Date` へ自動変換しない。仕様どおり RFC3339 `String` として保持し、表示層で整形する。
- favicon の `data:` URL は `AsyncImage` に渡さず、専用 component で decode する。

## Swift コード規約

- Swift API Design Guidelines に従う。
- `struct` と `let` を優先し、可変状態は必要な範囲に閉じる。
- `@MainActor` が必要な ViewModel / UI state は明示する。
- 非同期処理は `async` / `await` を使い、callback chain を増やさない。
- エラーは握りつぶさず、UI が表示可能な domain error へ変換する。
- Secret、実 token、個人情報を commit しない。
- 既存の仕様外 refactor は Issue の scope に含めない。

## テスト規約

- Unit test は XCTest で書く。
- API model decode、pagination、auth refresh、date formatting、favicon data URL decode は優先して単体テストする。
- 1 test は 1 観点に絞る。
- fixture は `FeedmanTests/Fixtures` など、テスト側に集約する。
- mock repository を使って ViewModel の loading / success / empty / error を検証する。
- 実ネットワークや実 Keychain に依存するテストは、明示的な integration test として分ける。

## idd-codex 運用

- 1 PR = 1 Issue を原則とする。
- 大きな設計判断、新規 API、複数 feature 横断の変更は design PR gate を通す。
- 通常の実装 PR / 設計 PR の base branch は `develop` とする。
- `main` は production release branch として扱う。通常開発 PR を `main` に直接向けない。
- `release/x.y.z` は App Store 提出用に `develop` から切る release-candidate branch とする。
- App Store 審査中の修正は `release/x.y.z` に入れ、必要に応じて `develop` へ back-merge する。
- 公開完了後に `release/x.y.z` を `main` へ merge する。この時点を production release とみなす。
- `Closes #N` / `Fixes #N` / `Resolves #N` などの closing keyword は、`develop` merge 時に Issue を閉じる目的で使わない。Issue close は `main` 到達時の release 処理で行う。
- `codex-staged-for-release` は「`develop` には入ったが `main` には未到達」の Issue を表す。release notes の入力として扱う。
- release notes は `codex-staged-for-release` Issue 群から起こし、production release 完了後に該当 Issue を close する。
- Issue 本文には `Depends on:` を明記し、依存 Issue が未完了なら実装へ進まない。
- Developer は設計 PR で確定済みの `docs/specs/*` を実装 PR で勝手に書き換えない。
- 不明点は推測で進めず、Issue comment で確認する。
- Codex CLI には Claude Code の subagent 起動機構が無いため、`.codex/agents/*.md` は別 context へ
  spawn されるのではなく、各 stage で watcher が役割定義として prompt 先頭へ注入する。
  prompt 中の「サブエージェントを起動」は「そのロールとして振る舞う」と読み替える。

## 検証

Linux 環境では Xcode build は実行できない。macOS/Xcode 環境では以下を確認する。

```bash
xcodebuild -project Feedman.xcodeproj -scheme Feedman -destination 'platform=iOS Simulator,name=iPhone 16' test
```
