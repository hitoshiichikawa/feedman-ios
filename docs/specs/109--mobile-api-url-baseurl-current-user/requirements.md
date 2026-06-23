# Requirements Document

## Introduction

Issue #109 は、iOS アプリの認証 URL、API origin、current user endpoint を Android / iOS 共通の v1 モバイル API 契約へ合わせるための要件である。
現状の `localhost` 固定 default、native OAuth URL の `code_challenge_method=S256` 欠落、`GET /auth/me` への mobile current user 取得は、実サーバ接続時のログイン後 API 呼び出し失敗につながる。
関連サーバ Issue `hitoshiichikawa/feedman#207` では、mobile current user は `GET /api/users/me`、web 用 `GET /auth/me` は Cookie 専用、native login は `flow=native` と PKCE S256 method を含む契約として明文化される。
本要件は Stage A の PM 要件定義のみを扱い、実装・テスト・commit・PR 作成は後続 stage に委ねる。

## Requirements

### Requirement 1: API origin configuration

**Objective:** As a Developer, I want アプリの API origin を環境ごとに設定できる, so that Release 相当や実機接続で `localhost` 固定に依存せず実サーバへ接続できる

#### Acceptance Criteria

1. When the app creates a Release-equivalent runtime configuration, the app shall use an explicitly configured API origin instead of treating `http://localhost:3000` as the fixed release default.
2. If no explicit local-development override is supplied for a Release-equivalent configuration, the app shall not silently fall back to `http://localhost:3000`.
3. When a configured API origin is available, the app shall use that same origin for authenticated API requests.
4. When a configured API origin is available, the app shall use that same origin as the base for native Google login URL construction.
5. If the configured API origin is missing or invalid, the app shall expose a developer-observable configuration failure before relying on an unintended production endpoint.

### Requirement 2: Native Google login URL contract

**Objective:** As a Feedman user, I want Google ログイン開始 URL が mobile API 契約に合う, so that サーバーの native OAuth flow で 400 にならずログインを開始できる

#### Acceptance Criteria

1. When the user starts Google login, the app shall construct the login URL for `/auth/google/login` with `flow=native`.
2. When the app constructs a Google login URL with a PKCE challenge, the app shall include `code_challenge=<current challenge>`.
3. When the app constructs a Google login URL with a PKCE challenge, the app shall include `code_challenge_method=S256`.
4. If the configured auth base URL already contains `flow`, the app shall normalize `flow` to `native` for the generated login URL.
5. If the configured auth base URL already contains `code_challenge`, the app shall normalize `code_challenge` to the current login attempt's challenge.
6. If the configured auth base URL already contains `code_challenge_method`, the app shall normalize `code_challenge_method` to `S256`.
7. If the configured auth base URL contains unrelated query parameters, the app shall preserve those parameters unless they conflict with the mobile auth contract.
8. The app shall not use WebView Cookie login fallback as part of this native login URL correction.

### Requirement 3: Mobile current user contract

**Objective:** As a logged-in Feedman user, I want アカウント表示が mobile current user endpoint を使う, so that Bearer token 認証の実サーバ環境で現在ユーザー情報を取得できる

#### Acceptance Criteria

1. When the account feature loads the current user for mobile app usage, the app shall request `GET /api/users/me`.
2. When current user is requested by the mobile app, the app shall send the request as an authenticated Bearer token API request.
3. When the server returns current user data from `GET /api/users/me`, the app shall display that current user through the existing account loading success path.
4. If a mobile current user request would target `GET /auth/me`, the app shall treat that endpoint as the wrong mobile contract and avoid using it for current user loading.
5. When account deletion is invoked by existing account deletion behavior, the app shall keep using `DELETE /api/users/me`.

### Requirement 4: Developer documentation and smoke checklist

**Objective:** As a Developer, I want README と smoke checklist で Simulator 接続先と mobile auth/current user 契約を確認できる, so that ローカル検証と Release 相当検証で接続先の誤解を減らせる

#### Acceptance Criteria

1. When README documents API origin setup, README shall explain how the app's API origin is configured for Simulator or device testing.
2. When README documents Simulator access to a local server, README shall distinguish local-development origin usage from Release-equivalent origin usage.
3. When README documents native Google login smoke testing, README shall mention that the generated login URL includes `flow=native`, `code_challenge`, and `code_challenge_method=S256`.
4. When README documents account smoke testing, README shall mention that mobile current user loading uses `GET /api/users/me`.
5. If production, staging, signing, OAuth client, or secret values are not present in the authoritative sources, README shall not invent those values.

### Requirement 5: Regression coverage

**Objective:** As a Maintainer, I want 契約補正を自動テストまたは確認可能な形で固定する, so that 後続変更で mobile API 契約から再びずれない

#### Acceptance Criteria

1. When login URL tests are run, the test suite shall verify that the generated Google login URL contains `code_challenge_method=S256`.
2. When login URL tests are run with an auth base URL that already contains stale auth query parameters, the test suite shall verify that `flow`, `code_challenge`, and `code_challenge_method` are normalized to the current mobile contract.
3. When account repository tests are run, the test suite shall verify that current user loading requests `/api/users/me`.
4. When API origin configuration tests or code checks are run, the verification shall show that Release-equivalent API origin is not fixed to `http://localhost:3000`.
5. When macOS/Xcode test execution is available, the implementer shall run `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Feedman.xcodeproj -scheme Feedman -destination 'platform=iOS Simulator,name=iPhone 16' test` or report why it could not be run.

## Non-Functional Requirements

### NFR 1: Contract compatibility

1. The app shall remain compatible with iOS 16+ for the affected login, account, and configuration flows.
2. The app shall keep existing Bearer token authentication behavior for authenticated mobile API requests.
3. The app shall preserve web Cookie endpoint compatibility by not redefining `GET /auth/me` as the mobile current user endpoint.
4. The app shall keep API date strings and user response fields aligned with the mobile API contract without treating prototype mock JSON as authoritative.

### NFR 2: Configuration safety

1. The app shall make Release-equivalent API origin selection observable to developers through code, tests, or documented configuration behavior.
2. The app shall not require real tokens, secrets, or personal information in committed test fixtures or README examples.
3. The app shall fail configuration validation in a developer-observable way within one app launch attempt when a required Release-equivalent API origin is absent.

### NFR 3: Documentation consistency

1. README shall remain consistent with `AGENTS.md`, `design/SPEC-iOS.md`, `design/SERVER.md`, and the mobile API contract from `hitoshiichikawa/feedman#207`.
2. README shall distinguish confirmed behavior from unresolved production or staging URL values.
3. README shall keep keyword push notification, OPML, feed URL change UI, offline full-text cache, feed-scoped search UI, and WebView Cookie login fallback out of the v1 smoke checklist.

## Out of Scope

- サーバーリポジトリ側の `hitoshiichikawa/feedman#207` 実装、契約文書作成、handler / router / middleware 変更。
- item detail、search pagination、cross-feed baseline parameter、feed metadata response など、#109 本文に含まれない mobile API 契約差分の補正。
- `POST /api/auth/token`、`POST /api/auth/refresh`、`POST /api/auth/revoke` の契約変更。
- ログアウト、退会、credential clear、session restoration の新規挙動追加。
- Universal Links callback への切り替え。
- production / staging の正式 URL、OAuth client ID、signing、bundle identifier、secret 値の決定。
- キーワードプッシュ通知、OPML import/export、フィード URL 変更 UI、オフライン全文 cache、Feed-scoped search UI、WebView Cookie login fallback。
- Developer stage の実装、Xcode test 実行、commit、PR 作成。

## Open Questions

- なし。既存 `design/SPEC-iOS.md` / `design/SERVER.md` に残る `GET /auth/me` 記載は、関連サーバ Issue `hitoshiichikawa/feedman#207` の mobile API 契約で `GET /api/users/me` へ補正される前提として扱う。
