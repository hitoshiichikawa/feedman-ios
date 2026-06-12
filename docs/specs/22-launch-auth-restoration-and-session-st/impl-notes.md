# 実装メモ

## 実装内容

- `AppAuthenticationState` に `.restoring` を追加し、起動直後の「復元中」をセッション状態として表現した (Req 4.1)。`isAuthenticated` は restoring を未認証側として扱う。
- `AppEnvironment.restoreSessionAtLaunch()` を追加した。
  - `.restoring` 状態のときだけ実行 (冪等、Req 4.2)。
  - `AuthRepository.refreshTokens()` 成功 → `.authenticated(accessToken:)` (rotation 済み refresh token の保存は #20 の repository 内部で完結)。
  - `AuthRepositoryError.missingRefreshToken` → 消去なしで `.unauthenticated` (保存 token が無い = 消すものがない)。
  - その他の失敗 (401 拒否等) → `clearLocalCredentials()` で**ローカルのみ**消去して `.unauthenticated`。失効 token の server revoke は行わない (server 側で拒否されるため)。
- `AuthRepository` protocol に `clearLocalCredentials() throws` を追加し、`FeedmanAuthRepository` は `TokenStore.clearCredentials()` へ委譲。`UnavailableAuthRepository` と各テスト mock にも実装を追加 (既存メソッドの挙動は不変)。
- `AppEnvironment.production()` の初期状態を `.restoring` に変更。preview / テスト用 init の default (`.unauthenticated`) は不変。
- `FeedmanApp` で root に `.task { await environment.restoreSessionAtLaunch() }` を追加 (起動 trigger)。
- `RootView` の分岐を `if isAuthenticated` から `switch authenticationState` に変更し、`.restoring` では #27 の `FeedmanLoadingView` による「セッションを確認しています」表示を出す (login flash 防止、Req 1.3)。

## 実装上の判断

- APIClient の 401 refresh hook (#23) への結線は行わない。受入基準に含まれず、実データ repository の認証結線 (#38 以降) の責務とした。
- 復元失敗時の消去は `revokeAndClearCredentials` ではなく新設の `clearLocalCredentials` を使う。前者は server revoke 失敗時に消去しない契約のため、失効 token では消去に到達できない。

## テスト

- `FeedmanTests/AppEnvironmentSessionRestoreTests.swift` を追加した (5 tests、mock AuthRepository のみ)。
  - 復元成功 → authenticated + 消去なし。
  - token 不在 → unauthenticated + 消去なし。
  - refresh 拒否 → unauthenticated + `clearLocalCredentials` 1 回。
  - 非 restoring 状態 → no-op (refresh 不試行)。
  - `completeLogin` の authenticated 遷移が維持されること。

## 検証

- 実行: `xcodebuild -project Feedman.xcodeproj -scheme Feedman -destination 'platform=iOS Simulator,name=iPhone 17' test` (macOS / Xcode 26.0)
  - 結果: 成功。Executed 160 tests, with 0 failures (新規 5 tests を含む)。
- `plutil -lint Feedman.xcodeproj/project.pbxproj`: OK。

## 確認事項

- 本 Issue は promote pipeline の誤付与 (`codex-staged-for-release` の cycle 毎再付与) により watcher から dispatch 不能のため、Claude Code が直接実装した。pipeline 側の修正は idd-codex の課題。
