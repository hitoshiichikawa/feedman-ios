# Issue #21 ASWebAuthenticationSession login screen 要件定義

## 概要 / 目的

Issue #21 は Parent: #3 の子 Issue として、Google ログイン画面から `ASWebAuthenticationSession` による native OAuth flow を開始し、OAuth callback 後の token exchange 成功をアプリの認証済み状態へ接続する Stage A の縦切りを定義する。

`design/SPEC-iOS.md` では、iOS の Google ログインは `ASWebAuthenticationSession` で `/auth/google/login?flow=native&code_challenge=...` を開き、`feedman://auth/callback?auth_code=...` を受け取った後に `POST /api/auth/token` で token exchange する方針が確定している。`design/SERVER.md` では、`auth_code` は PKCE に紐付く 60 秒・単回の一時コードであり、交換後に Bearer access token と refresh token が返る。

本要件では、先行 Issue の #18（PKCE generation / callback parsing）、#19（Keychain TokenStore）、#20（AuthRepository / token exchange。PR #74 が develop merge 済み・`codex-staged-for-release` とコメントで確認済み）を前提に、ログイン画面、`ASWebAuthenticationSession` 起動、callback 結果の橋渡し、成功/失敗/キャンセル時の UI 状態を扱う。

## 参照した Issue コメントの反映

- Issue 本文の期待値どおり、Google login tap で `flow=native` と PKCE challenge 付きの `ASWebAuthenticationSession` を開く。
- Issue 本文の期待値どおり、callback 成功時は `auth_code` を `AuthRepository` 経由で交換する。
- Issue 本文の期待値どおり、login 失敗またはキャンセル時はログイン画面に留まり、エラーまたはキャンセル状態を表示可能にする。
- Issue 本文のスコープ外どおり、Account screen logout と API feature screens は含めない。
- コメントで確認された `Depends on: #20` は PR #74 が develop merge 済み・`codex-staged-for-release` のため、本 Issue の実装ブロックとして扱わない。
- Path Overlap Checker コメントの edit paths は `Feedman/Core/` と `Feedman/Features/` であり、本 Issue の想定変更範囲もこの配下に閉じる。

## スコープ内

- SwiftUI のログイン画面またはログイン状態 View を追加し、Google ログインボタンを 1 つ表示する。
- Google ログインボタン tap から `ASWebAuthenticationSession` を開始する。
- OAuth 開始ごとに PKCE `code_verifier` / `code_challenge` を生成し、`code_verifier` は token exchange 完了または失敗まで保持する。
- `/auth/google/login` を `flow=native` と `code_challenge` 付きで開く。
- `ASWebAuthenticationSession` の `callbackURLScheme` は `feedman` を使い、`feedman://auth/callback?auth_code=...` を受け取る。
- callback URL から `auth_code` を抽出し、`AuthRepository` に `auth_code` と対応する `code_verifier` を渡して token exchange を実行する。
- token exchange 成功時に、認証済み shell へ遷移できる状態を ViewModel または app route state に反映する。
- login 中、成功、失敗、キャンセルの UI 状態を ViewModel で表現し、SwiftUI View が表示できるようにする。
- Unit test で ViewModel / session coordinator / repository mock による loading、success、failure、cancel を検証する。

## スコープ外

- Account screen、logout、`/api/auth/revoke`、`POST /auth/logout`。
- `APIClient` の 401 refresh retry、`/api/auth/refresh`、access token expiry handling。
- 横断タイムライン、フィード一覧、スター、検索などの API feature screen 実装。
- サーバー側 OAuth / token endpoint / middleware の変更。
- WebView Cookie login fallback。
- Universal Links callback の実装。Stage A は custom scheme `feedman://auth/callback` に限定する。
- Google OAuth 画面自体のカスタマイズ。
- プッシュ通知、OPML、keyword notification UI。

## 機能要件（EARS 形式）

### Requirement 1: Login screen presentation

**Objective:** As a Feedman user, I want ログイン前に Google ログインだけを選べる画面を見る, so that v1 の認証方式に迷わず進める

#### Acceptance Criteria

1. When the app is unauthenticated, the app shall show a login screen with one Google login action.
2. When the login screen is shown, the screen shall not expose WebView Cookie login fallback, email login, OPML, keyword notification, logout, or account deletion actions.
3. When the user has not started login, the Google login action shall be enabled.
4. While a login attempt is in progress, the login screen shall prevent duplicate login attempts and expose a loading state.

### Requirement 2: Native OAuth session start

**Objective:** As a Feedman user, I want Google ログインボタンから native OAuth flow を開始できる, so that iOS 標準の安全な認証体験でログインできる

#### Acceptance Criteria

1. When the user taps Google login, the app shall generate a fresh PKCE `code_verifier` and S256 `code_challenge` for that login attempt.
2. When the user taps Google login, the app shall open `ASWebAuthenticationSession` with `/auth/google/login` including `flow=native` and the generated `code_challenge`.
3. When the app opens `ASWebAuthenticationSession`, the session shall use `callbackURLScheme` value `feedman`.
4. When the app starts native OAuth, the app shall not use `WKWebView`, `SFSafariViewController`, or Cookie session sharing for login.
5. If `ASWebAuthenticationSession` cannot be started, the app shall remain on the login screen and surface a retryable login error state.

### Requirement 3: Callback handling and token exchange

**Objective:** As a Feedman user, I want Google 認可完了後にアプリへ戻って認証済み状態へ進む, so that token auth の初回ログインを完了できる

#### Acceptance Criteria

1. When `ASWebAuthenticationSession` returns `feedman://auth/callback?auth_code=<value>`, the app shall parse `<value>` as `auth_code` using the established callback parsing boundary.
2. When a valid `auth_code` is received, the app shall call `AuthRepository` to exchange the `auth_code` with the matching PKCE `code_verifier`.
3. When token exchange succeeds, the app shall transition from login state to authenticated app shell state.
4. When token exchange succeeds, the app shall not require the user to tap login again before entering the authenticated shell.
5. When callback parsing fails, the app shall remain on the login screen and surface a login error state.
6. When token exchange fails, the app shall remain on the login screen and surface a login error state.
7. When token exchange completes or fails, the app shall clear the in-flight PKCE verifier from transient login state.

### Requirement 4: Cancellation behavior

**Objective:** As a Feedman user, I want Google ログインをキャンセルしてもアプリが壊れない, so that 再試行できる

#### Acceptance Criteria

1. When the user cancels `ASWebAuthenticationSession`, the app shall remain unauthenticated on the login screen.
2. When the user cancels `ASWebAuthenticationSession`, the app shall clear loading state and allow another Google login attempt.
3. When the user cancels `ASWebAuthenticationSession`, the app shall not perform token exchange.
4. When the user cancels `ASWebAuthenticationSession`, the app shall not persist or modify refresh token credentials.

### Requirement 5: Authenticated route handoff

**Objective:** As an app shell 実装者, I want login 成功が routing state に反映される, so that 後続の横断タイムライン表示へ接続できる

#### Acceptance Criteria

1. When login succeeds, the app shall expose an authenticated state that the root view or app shell can observe.
2. When login succeeds, the app shall hide the login screen from the primary route.
3. When login succeeds, the app shall not implement API feature screen loading inside the login screen responsibility.
4. If authenticated handoff requires a user/session model not yet available in Stage A, the app shall use the minimal existing auth state from `AuthRepository` or app route state without adding unrelated account feature requirements.

## 非機能・設計制約

- The implementation shall follow `design/SPEC-iOS.md` and `design/SERVER.md` as the authoritative auth contract.
- The implementation shall use SwiftUI, Swift Concurrency, and iOS 16+ compatible APIs.
- The implementation shall keep View code free from direct `URLSession` and Keychain access.
- The implementation shall keep `AuthRepository` as the token exchange boundary and shall not duplicate `/api/auth/token` request construction in the View.
- The implementation shall keep PKCE and callback parsing in reusable Core auth boundaries instead of reimplementing those rules in the View.
- The implementation shall store only transient `code_verifier` state needed for the active login attempt and shall not log `auth_code`, access token, refresh token, or secrets.
- The implementation shall keep access token persistence, refresh token persistence, and token rotation responsibilities in the existing auth storage/repository layer.
- The implementation shall not change established `docs/specs/*` from implementation PRs without an explicit design gate.
- The implementation shall keep this Issue scoped to `Feedman/Core/` and `Feedman/Features/` unless Xcode project registration requires the minimum necessary project file update.
- Swift type names, identifiers, and file names shall be English.
- docs/specs 記述は日本語とし、EARS の `When` / `If` / `While` / `Where` / `shall` は英語固定にする。

## 受入基準

- When the app launches without authenticated credentials, the app shall present the login screen instead of an authenticated feature screen.
- When the user taps Google login, the app shall open `ASWebAuthenticationSession` with `flow=native`, a PKCE `code_challenge`, and `callbackURLScheme` `feedman`.
- When `feedman://auth/callback?auth_code=...` is returned, the app shall exchange the code through `AuthRepository` using the matching `code_verifier`.
- When token exchange succeeds, the app shall transition to authenticated shell state.
- When the OAuth session is cancelled, callback parsing fails, or token exchange fails, the app shall remain on the login screen and allow retry.
- When login is in progress, repeated taps shall not start duplicate OAuth sessions.
- The implementation shall not add Account logout, API feature screen behavior, WebView Cookie login fallback, or server-side changes.

## テスト観点

- Login ViewModel の initial state が unauthenticated / idle であること。
- Google login action で PKCE challenge を生成し、`ASWebAuthenticationSession` 起動境界に `flow=native`、`code_challenge`、`callbackURLScheme=feedman` 相当が渡ること。
- Login in progress 中に二重 tap しても session start が重複しないこと。
- Mock session が valid callback URL を返した場合、`AuthRepository` mock に `auth_code` と対応する `code_verifier` が渡ること。
- `AuthRepository` success 時に authenticated shell state へ遷移すること。
- Mock session cancellation 時に token exchange が呼ばれず、login screen の retry 可能 state に戻ること。
- Callback parser error 時に token exchange が呼ばれず、login error state になること。
- Token exchange error 時に login error state になり、retry 可能になること。
- Test fixture やログに実 token、Secret、個人情報を含めないこと。
- macOS/Xcode 環境では以下を確認すること。

```bash
xcodebuild -project Feedman.xcodeproj -scheme Feedman -destination 'platform=iOS Simulator,name=iPhone 16' test
```

## 確認事項

なし。
