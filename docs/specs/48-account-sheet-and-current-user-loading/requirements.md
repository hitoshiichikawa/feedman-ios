# Issue #48 Account sheet and current user loading 要件定義

## 背景

Issue #48 は Parent: #11 の子 Issue として、アカウントシートを開いたときに現在ログイン中のユーザー情報を `/auth/me` から読み込み、アカウント関連 action を表示する。

`design/SPEC-iOS.md` では v1 スコープにアカウント、ログアウト、退会が含まれ、認証/ユーザー endpoint として `GET /auth/me`、`POST /auth/logout`、`DELETE /api/users/me` が列挙されている。また、ネイティブアプリは Bearer token 認証を採用し、認証必須 API には `Authorization: Bearer <access_token>` を付与する方針である。`design/SERVER.md` では既存 Cookie セッションと Bearer token 認証を並存させ、アプリは token flow を使うことが示されている。

親 Epic I11 は「アカウントシートで `/auth/me` のユーザー情報を表示する」「ログアウトは token revoke と local credential clear を行う」「退会は二段確認後に `DELETE /api/users/me` を呼ぶ」を含む。ただし Issue #48 本文では期待する挙動を "Account sheet loads current user data from /auth/me and displays account actions." とし、スコープ外に "Logout and delete account behavior." を明記している。そのため本 Issue は、現在ユーザー読み込み、表示状態、action の見た目と到達性までを扱い、ログアウト・退会の実挙動は後続 Issue に委ねる。

Issue コメントでは、依存 Issue #20 と #28 がすべて `develop` へ merge 済みであり、`codex-blocked` が除去され `codex-auto-dev` が付与されたことが人間により確認されている。Path Overlap Checker の edit path は `Feedman/` とされている。

## スコープ

- AppShell から開かれる account presentation を、placeholder ではなくアカウントシートとして表示する。
- アカウントシートの表示開始時に現在ユーザー情報を `/auth/me` から読み込む。
- 読み込み中、成功、エラー、再試行の UI 状態を用意する。
- 成功時は現在ユーザーの name / email 相当の情報を表示する。
- ログアウト action と退会 action をアカウントシート内に表示する。
- logout / delete account の実行処理は呼ばず、後続 Issue の責務であることが実装上も分かる境界に留める。
- `Features/Account` を中心に、必要な ViewModel、repository protocol、mock / real implementation の境界を定義できるようにする。

## スコープ外

- ログアウトの実挙動。
- `POST /api/auth/revoke` の呼び出し。
- `POST /auth/logout` の呼び出し。
- local credential / Keychain の clear。
- ログアウト成功後に login へ戻す session transition。
- 退会の実挙動。
- `DELETE /api/users/me` の呼び出し。
- 退会の二段確認と destructive API 実行。
- 退会成功後の credential clear、画面遷移、server-side cleanup の検証。
- Profile editing。
- Multi-account switching。
- Account 情報の編集、avatar upload、ユーザー設定 API。
- WebView Cookie login fallback。

## 要件

### Requirement 1: Account sheet presentation

**Objective:** As a ログイン済みユーザー, I want アカウントシートを開いて自分のアカウント状態を確認できる, so that アプリ内で現在のログイン状態を把握できる

#### Acceptance Criteria

1. When the account entry point is activated, the app shall account sheet を表示する。
2. When the account sheet is presented, the sheet shall native SwiftUI sheet behavior または既存 DesignSystem sheet primitive に沿って閉じられる。
3. When the account sheet is presented from the drawer, the app shall drawer と account sheet の presentation state が重複して操作不能にならないようにする。
4. When the account sheet is dismissed, the app shall current route と AppShell の主要状態を不必要に変更しない。
5. When account sheet UI is visible, the sheet shall 日本語の title と close affordance を持つ。

### Requirement 2: Current user loading from `/auth/me`

**Objective:** As a ログイン済みユーザー, I want アカウントシートを開くと現在ユーザー情報が読み込まれる, so that mock ではなく実際のログイン中ユーザーを確認できる

#### Acceptance Criteria

1. When the account sheet opens, the app shall `GET /auth/me` で現在ユーザー情報を読み込む。
2. When `/auth/me` is requested, the app shall 認証必須 endpoint として Bearer token 認証付きの APIClient / repository 境界を使う。
3. When current user loading is in progress, the sheet shall loading state を表示し、古い placeholder user を成功状態として見せない。
4. When current user loading succeeds, the sheet shall `/auth/me` から得た current user を表示する。
5. When the sheet is reopened after dismissal, the app shall current user loading を再実行する、または既存 repository / ViewModel の cache 方針が明示されている場合はその方針に従って最新状態を表示する。
6. If the access token is expired, the request shall 既存 APIClient の 401 refresh retry hook に委ね、account sheet 独自の token refresh 実装を持たない。
7. If no authenticated session exists, the sheet shall current user を成功状態として表示せず、認証切れとして扱える error state を表示する。

### Requirement 3: User information display

**Objective:** As a ログイン済みユーザー, I want name と email を確認できる, so that どのアカウントで Feedman にログインしているか分かる

#### Acceptance Criteria

1. When current user loading succeeds with a display name, the sheet shall その name を表示する。
2. When current user loading succeeds with an email address, the sheet shall その email を表示する。
3. If a display name is missing or empty, the sheet shall email または仕様で許容された fallback 表示を使い、空白だけの見出しを表示しない。
4. If an email address is missing or empty, the sheet shall name または仕様で許容された fallback 表示を使い、壊れた email 表示を出さない。
5. When user text is long, the sheet shall name / email / close control / action buttons が重ならない layout にする。
6. When Dynamic Type is large, the sheet shall name と email を読める形で折り返しまたは省略し、テキスト同士や action buttons と重ねない。
7. When VoiceOver is enabled, the sheet shall current user の name / email と account actions を理解できる日本語 accessibility label または標準 Text 読み上げで提供する。

### Requirement 4: Error and retry state

**Objective:** As a ログイン済みユーザー, I want current user 取得に失敗しても原因を認識して再試行できる, so that 一時的な通信失敗から復帰できる

#### Acceptance Criteria

1. When `/auth/me` fails, the sheet shall error state を表示する。
2. When user info is unavailable, the sheet shall retry action を表示する。
3. When the user taps retry, the app shall `/auth/me` の current user loading を再実行する。
4. When retry is in progress, the sheet shall loading state を再表示し、連続 tap による重複 request を防ぐ。
5. If the server returns a typed Feedman error response, the sheet shall 既存 error decoding / domain error mapping に沿ってユーザーに表示可能な日本語文言へ変換する。
6. If the failure indicates authentication loss after refresh retry, the sheet shall logout / delete account を実行せず、認証切れとして表現する。

### Requirement 5: Account action display only

**Objective:** As a ログイン済みユーザー, I want アカウントシートでログアウトと退会の action が見える, so that 後続 Issue で実挙動を接続できる UI 位置が確保される

#### Acceptance Criteria

1. When current user loading succeeds, the sheet shall ログアウト action を表示する。
2. When current user loading succeeds, the sheet shall 退会またはアカウント削除 action を destructive intent が分かる表示で提供する。
3. If current user loading fails, the sheet shall account actions を非表示または disabled にし、存在しない current user に対する実行可能 action と誤認させない。
4. When the user taps logout action in this Issue, the app shall `POST /api/auth/revoke`、`POST /auth/logout`、credential clear、login transition を実行しない。
5. When the user taps delete account action in this Issue, the app shall `DELETE /api/users/me`、credential clear、login transition を実行しない。
6. If placeholder handling is needed for action taps, the sheet shall 後続実装待ちであることが分かる非破壊 feedback に留める。
7. When action buttons are displayed, the sheet shall logout と delete account を視覚的に区別し、delete account を destructive action として扱う。

### Requirement 6: Repository and ViewModel boundary

**Objective:** As a Developer, I want account sheet が repository protocol 経由で current user を取得する, so that real API と mock を差し替えて ViewModel を検証できる

#### Acceptance Criteria

1. When account data access is introduced, the app shall View から `URLSession`、Keychain、raw token store を直接触らない。
2. When account repository is introduced, the app shall protocol を先に定義し、mock と real implementation を差し替え可能にする。
3. When Account ViewModel owns UI state, the ViewModel shall loading / success / error / retrying 相当の状態を明示的に表現する。
4. When Account ViewModel updates UI state from async work, the ViewModel shall `@MainActor` または同等の main actor 境界を明示する。
5. When the real repository decodes `/auth/me`, the model shall API 契約で明示された field を `Codable` で扱い、mock data の JSON 形を正本として扱わない。

## 非機能要件

### NFR 1: Compatibility

1. The implementation shall iOS 16+ SwiftUI で動作する。
2. The implementation shall Swift Concurrency (`async` / `await`) を使う。
3. Swift の型名、識別子、ファイル名は English にする。
4. The implementation shall MVVM + Repository 方針に従う。

### NFR 2: Scope control

1. The implementation shall Issue #48 の current user loading と account action display に閉じる。
2. The implementation shall logout / delete account の実挙動を追加しない。
3. The implementation shall token refresh、revoke、credential storage、session restoration の既存契約を再実装しない。
4. The implementation shall `design/SPEC-iOS.md`、`design/SERVER.md`、`docs/specs/*` の確定済み仕様を勝手に変更しない。
5. The implementation shall keyword notification、OPML、profile editing、multi-account switching の UI を追加しない。

### NFR 3: Accessibility and layout

1. The account sheet shall Dynamic Type で name / email / actions が重ならない layout を保つ。
2. The account sheet shall light / dark appearance で既存 `FeedmanTheme` または DesignSystem semantic style に沿う。
3. The account sheet shall tappable controls に実用的な hit area を持たせる。
4. The account sheet shall destructive action の色や文言を、既存 DesignSystem の danger 表現に合わせる。

### NFR 4: Verification expectation

1. When tests are added in implementation stage, the test suite shall mock repository を使って ViewModel の loading / success / error / retry state を検証する。
2. When API model decode tests are added in implementation stage, the test suite shall `/auth/me` の仕様上の current user response を fixture として検証する。
3. When Xcode test is available, the implementation shall `xcodebuild -project Feedman.xcodeproj -scheme Feedman -destination 'platform=iOS Simulator,name=iPhone 16' test` で検証する。
4. While Linux 環境または Xcode 未選択環境で作業している, the implementer shall Xcode build/test を実行できない制約を結果報告に明記する。

## 実装境界

- 想定領域は `Feedman/Features/Account` と、既存 AppShell の account presentation 接続に必要な最小範囲。
- 既存 `Feedman/Features/AppShell` に account placeholder がある場合は、account sheet 実体への接続に置き換える。
- API client の 401 refresh retry は既存 Core/Auth/Core/API の責務を使い、Account feature 内で重複実装しない。
- logout action と delete account action は UI 表示要件のみ。実行処理、API 呼び出し、credential clear、session transition は後続 Issue の責務。

## 確認事項

- `/auth/me` の current user response に含まれる正式な field 名と optionality が `design/SPEC-iOS.md` / `design/SERVER.md` 内で明文化されていない。実装前に、少なくとも id / name / email 相当の有無と JSON field 名を確認する必要がある。
- `/auth/me` が Bearer token で呼ばれた場合の response shape が既存 Web Cookie session の response と完全に同一か確認する必要がある。
- current user loading の cache 方針は未確定。Issue #48 では sheet open 時に読み込むことを基本とし、cache を入れる場合は鮮度と retry の扱いを実装側で明示する必要がある。
- logout / delete account action tap 時の一時的な placeholder feedback を表示するか、disabled に留めるかは未確定。ただし、どちらの場合も実 API や credential clear は実行しない。
