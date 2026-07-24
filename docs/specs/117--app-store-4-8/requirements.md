# Issue #117 パスキーでのログイン / アカウント新規作成 要件定義

## 概要

Issue #117 は、Feedman iOS が Google OAuth のみをログイン手段としている状態を解消し、App Store Review Guideline 4.8 に対応するために、パスキーによるログイン、ユーザー名による新規アカウント作成、既存アカウントへのパスキー追加登録を追加する。

サーバ側 Issue `hitoshiichikawa/feedman#216` の設計レビュー PR #217 では、iOS クライアント向けに `POST /api/passkey/registration/begin|finish`、`POST /api/passkey/authentication/begin|finish`、`POST /api/passkey/registration/add/begin|finish`、および `/.well-known/apple-app-site-association` が定義されている。新規登録 finish は `{user_id}` のみを返し、ログイン済み遷移に必要な `auth_code` は後続の passkey authentication finish が返す。パスキー認証 begin は既存 Google native auth と同じく PKCE S256 の `code_challenge` だけを受け取り、finish 成功時に `auth_code` を返す。iOS はその `auth_code` と保持中の `code_verifier` を既存 `AuthRepository.exchangeAuthCode` に渡し、既存 token 保存・認証済み route へ合流する。

## 参照した Issue コメントの反映

- ログイン画面の配置はコメント回答 `1.A` を採用し、Google を主ボタン、パスキーを副ボタンとして追加する。
- リカバリ用メールはコメント回答 `2.B` を採用し、初回パスキー登録フローでは入力させない。サーバ #216 の新規登録 begin は `email?` を許容するが、本 Issue の iOS 初回登録 request では送信しない。
- 既存アカウントへのパスキー後付け追加はサーバ #216 のコメント回答 `OptionA` に合わせ、本 Issue のスコープに含める。
- 既存 Account sheet には退会（アカウント削除）導線があるため、本 Issue では導線の存在を回帰確認し、退会 flow の再設計は行わない。
- サーバ #216 の実装 API 契約が完了前に変わった場合、iOS 実装前に本 spec を更新する必要がある。登録完了直後のログイン済み遷移は、`registration/finish` の `{user_id}` をログイン token として扱わず、platform registration 結果から得た作成直後 credential ID を iOS 側の assertion request `allowedCredentials` にだけ適用して、サーバ request は確定契約どおり `authentication/begin` `{code_challenge}` のまま進める。

## スコープ

- ログイン画面に Google 主導線、パスキーログイン副導線、新規作成導線を表示する。
- 新規作成ではユーザー名のみを入力し、AuthenticationServices の platform passkey 登録を開始する。
- パスキーログインではサーバ begin → iOS platform assertion → サーバ finish → 既存 `auth_code` token exchange へ合流する。
- パスキー新規作成後は、作成した認証情報でログイン済み状態へ遷移する。
- Google ログイン済みユーザーを含む認証済みユーザーが、Account sheet から自分のアカウントにパスキーを追加登録できる。
- Associated Domains entitlement に `webcredentials` を追加し、サーバ AASA の `webcredentials.apps` と整合させる。
- パスキー登録・認証のキャンセル、失敗、サーバエラーを UI 状態として扱い、アプリを不整合状態にしない。
- パスキー由来アカウントでも既存の主要機能（横断タイムライン、フィード一覧、記事閲覧）が既存 Bearer token flow で成立することを回帰確認する。

## スコープ外

- Sign in with Apple。
- パスワード認証。
- サーバ側実装、DB migration、AASA 配信実装。
- Web フロントのパスキー UI。
- パスキー credential の削除、リネーム、複数 credential 管理 UI。
- リカバリ用メールの編集 UI と保存 endpoint。初回登録でメールを収集しないことだけを本 Issue の責務とする。
- Google アカウント連携の解除または変更。
- account deletion flow の再設計。

## 依存関係

- Depends on: `hitoshiichikawa/feedman#216`。サーバ側 passkey API の実装 Issue が完了し、`develop` に merge 済みであることを iOS 実装開始条件とする。設計 PR #217 の merge だけでは本依存を満たさないため、#216 が未完了の場合は本 Issue の Developer フェーズへ進まない。

## 要件

### Requirement 1: Login screen passkey entry points

**Objective:** As a 未ログインユーザー, I want Google に加えてパスキーでログインまたは新規作成できる導線を見る, so that Google を使わずに Feedman を始められる

#### Acceptance Criteria

1. When the app is unauthenticated, the login screen shall Google login の主ボタン、パスキーでログインの副ボタン、アカウント新規作成の導線を表示する。
2. When the login screen is shown, the Google login action shall 既存の文言、PKCE 生成、ASWebAuthenticationSession flow を維持する。
3. When the login screen is shown, the passkey login action shall Google login より副次的な視覚優先度で表示される。
4. When the login screen is shown, the account creation action shall ユーザー名とパスキーで新規作成する導線として理解できる日本語文言を表示する。
5. While any login or passkey ceremony is in progress, the login screen shall duplicate attempts を防ぎ、対象 action の loading state を表示する。
6. When Dynamic Type or VoiceOver is enabled, the login screen shall 3 つの認証導線と状態メッセージを重ならず理解可能に表示する。

### Requirement 2: Passkey account creation

**Objective:** As a 新規ユーザー, I want ユーザー名とパスキーだけでアカウントを作成できる, so that メールアドレスを出さずに Feedman を使い始められる

#### Acceptance Criteria

1. When the user starts account creation, the app shall username input を表示し、recovery email input を初回登録フローに含めない。
2. When the user submits an empty or whitespace-only username, the app shall server request を送信せず、入力修正を促す。
3. When the user submits a username, the app shall PKCE `code_verifier` と S256 `code_challenge` を生成し、`POST /api/passkey/registration/begin` に `username` と `code_challenge` を送信する。
4. When registration begin succeeds, the app shall response の `challenge_id` と WebAuthn options から platform passkey registration request を作成する。
5. When platform passkey registration succeeds, the app shall attestation credential と `challenge_id` を `POST /api/passkey/registration/finish` に送信する。
6. When registration finish succeeds, the app shall `registration/finish` の `{user_id}` を token handoff として扱わず、platform registration 結果から得た作成直後 credential ID で iOS platform assertion request をローカル制限した passkey authentication begin/finish を実行し、既存 token exchange に合流してログイン済み状態へ遷移する。
7. If username is rejected or already taken before platform registration succeeds, the app shall platform credential を作成せず、入力画面に留まってユーザーが修正できるエラーを表示する。
8. If passkey registration is canceled, platform authorization fails, or `registration/finish` fails or becomes result-unknown after a platform credential may have been created, the app shall raw credential を保存せず、未ログイン状態を維持し、サーバを source of truth として再試行またはパスキーログインで照合できるエラーを表示する。

### Requirement 3: Passkey login

**Objective:** As a パスキー登録済みユーザー, I want Face ID / Touch ID などの platform passkey でログインできる, so that Google OAuth を使わずに既存機能へ戻れる

#### Acceptance Criteria

1. When the user taps passkey login, the app shall fresh PKCE `code_verifier` と S256 `code_challenge` を生成する。
2. When passkey login begins, the app shall `POST /api/passkey/authentication/begin` に `code_challenge` を送信する。
3. When authentication begin succeeds, the app shall response の `challenge_id` と WebAuthn options から platform passkey assertion request を作成する。
4. When platform passkey assertion succeeds, the app shall assertion credential と `challenge_id` を `POST /api/passkey/authentication/finish` に送信する。
5. When authentication finish returns `auth_code`, the app shall 既存 `AuthRepository.exchangeAuthCode(auth_code, codeVerifier:)` を使って token exchange を実行する。
6. When token exchange succeeds, the app shall existing `AppEnvironment.completeLogin` 境界に合流し、authenticated shell を表示する。
7. If authentication is canceled, rejected, expired, unknown credential, rate limited, or server failed, the app shall token exchange を実行せず、未ログイン状態を維持し、再試行可能なエラーを表示する。

### Requirement 4: Existing account passkey enrollment

**Objective:** As a Google ログイン済みユーザー, I want Account sheet から自分のアカウントにパスキーを追加できる, so that 次回からパスキーでもログインできる

#### Acceptance Criteria

1. When the user is authenticated, the account sheet shall パスキー追加 action を表示する。
2. When the user taps passkey add, the app shall current access token を使って `POST /api/passkey/registration/add/begin` を呼ぶ。
3. When add begin succeeds, the app shall response の `challenge_id` と WebAuthn options から platform passkey registration request を作成する。
4. When platform passkey registration succeeds, the app shall credential と `challenge_id` を `POST /api/passkey/registration/add/finish` に Bearer token 付きで送信する。
5. When add finish succeeds, the app shall account sheet 上に追加完了 notice を表示し、現在の authenticated session を維持する。
6. If add registration is canceled, platform authorization fails, or add finish fails or becomes result-unknown after a platform credential may have been created, the app shall current session と既存 token を維持し、サーバを source of truth として再試行または次回パスキーログインで照合できるエラーを表示する。
7. If the access token is expired, the app shall 既存 APIClient の 401 refresh retry hook に委ね、Account feature 内で独自 refresh を実装しない。

### Requirement 5: Associated Domains and passkey domain alignment

**Objective:** As an iOS platform, I want app entitlement とサーバ AASA が一致している, so that platform passkey requests can verify the relying party domain

#### Acceptance Criteria

1. When passkey support is implemented, the app target shall Associated Domains entitlement を持つ。
2. When Associated Domains is configured, the entitlement shall `webcredentials:$(FEEDMAN_WEBCREDENTIALS_DOMAIN)` を含み、その値は server #216 の `WEBAUTHN_RP_ID` と同じ fully qualified domain に解決される。
3. When App Store / production build is prepared, the configured app identifier shall サーバ AASA の `webcredentials.apps` に含まれる `TEAM_ID.com.hitoshiichikawa.feedman` 形式の値と整合する。
4. When local or test builds do not have a production RP domain, the implementation shall domain 値を発明せず、PR の確認事項または build configuration で未設定であることを明示する。
5. When entitlement or AASA mismatch causes platform authorization failure, the app shall local credentials を変更せず、ユーザーに再試行可能なエラーを表示する。

### Requirement 6: Auth state integration and existing feature compatibility

**Objective:** As a Feedman user, I want パスキー由来アカウントでも既存主要機能を使える, so that login method does not change app behavior after authentication

#### Acceptance Criteria

1. When passkey login or account creation succeeds, the app shall refresh token を既存 TokenStore 境界で保存する。
2. When passkey login or account creation succeeds, the app shall in-memory access token を既存 AppEnvironment 境界へ渡す。
3. When passkey-derived account is authenticated, the app shall 横断タイムラインを既存 Bearer token request で読み込める。
4. When passkey-derived account is authenticated, the app shall フィード一覧を既存 Bearer token request で読み込める。
5. When passkey-derived account is authenticated, the app shall 記事詳細 sheet と SFSafariViewController の元記事表示を既存 flow で使える。
6. When current user response includes username but not email, the account display shall username を表示候補として扱える。username が無い場合も fallback 表示で crash しない。
7. When the user uses Google login, the app shall 既存 Google login tests と OAuth URL contract を維持する。

### Requirement 7: Account deletion route confirmation

**Objective:** As an App Review reviewer, I want app 内にアカウント削除導線が存在する, so that Guideline 5.1.1(v) の要件を満たす

#### Acceptance Criteria

1. When the user is authenticated and opens account sheet, the app shall existing delete account action を引き続き表示する。
2. When passkey support is added, the app shall existing account deletion confirmation flow を削除・隠蔽・再設計しない。
3. When account deletion succeeds, the app shall existing local credential clear と unauthenticated transition を維持する。
4. When account deletion fails, the app shall existing failure behavior と session preservation を維持する。

### Requirement 8: Security, privacy, and testing constraints

**Objective:** As a Developer, I want パスキー導入が secrets と既存認証を安全に扱う, so that 認証方式追加による regression を検出できる

#### Acceptance Criteria

1. The implementation shall use SwiftUI, Swift Concurrency, MVVM + Repository, and iOS 16+ compatible AuthenticationServices APIs。
2. The implementation shall keep View code free from direct `URLSession` and Keychain access。
3. The implementation shall not log raw `auth_code`, access token, refresh token, `code_verifier`, platform credential raw data, or recovery email, and shall not persist them outside the existing auth boundaries. Refresh token persistence is allowed only through the existing `TokenStore` required by Requirement 6.1。
4. The implementation shall map user cancellation separately from server / validation failures where platform APIs expose cancellation。
5. The implementation shall use XCTest with mock repository / mock passkey coordinator and shall not depend on real network, real Keychain, or real Face ID / Touch ID。
6. The implementation shall add regression tests for Google login URL, passkey registration success/failure, passkey login success/failure, passkey add success/failure, duplicate in-flight guards, and account deletion route preservation。
7. When Xcode is available, the implementation shall pass `xcodebuild -project Feedman.xcodeproj -scheme Feedman -destination 'platform=iOS Simulator,name=iPhone 16' test`。
8. The implementation shall not change established `docs/specs/*` outside this spec directory in implementation PRs。
9. The implementation shall not collect interactions with the app for advertising purposes through the passkey login option without user consent。

## 受入基準

- When the app is unauthenticated, the login screen shall show Google login, passkey login, and account creation.
- When passkey account creation completes, the app shall reach authenticated shell through existing token exchange and token storage.
- When passkey login completes, the app shall reach authenticated shell through existing token exchange and token storage.
- When a Google-authenticated user adds a passkey, the current session shall remain authenticated and the account sheet shall show completion notice.
- When passkey ceremony is canceled or fails, the app shall preserve current auth state and credentials.
- When passkey-derived account is authenticated, timeline, feed list, and article detail shall use existing Bearer API flows.
- When passkey support is added, Google login and account deletion routes shall remain available.

## 確認事項

- サーバ #216 は本レビュー時点で未完了であり、設計 PR #217 は merge 済みでも実装開始条件を満たさない。Developer / watcher は #216 の実装完了と endpoint 契約差分を実装前に確認する。
- Associated Domains の production RP domain と Team ID はこの repo 内に正本が無い。Developer / 運用者は `WEBAUTHN_RP_ID` と AASA の `webcredentials.apps` に合わせて build configuration を確定する。
- リカバリ用メールは初回登録では収集しない。後から設定画面で追加するにはサーバ側 profile update endpoint が必要だが、本 Issue では未定義のためスコープ外とする。
