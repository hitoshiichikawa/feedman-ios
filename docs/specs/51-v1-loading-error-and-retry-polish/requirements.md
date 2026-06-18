# Issue #51 v1 loading error and retry polish 要件定義

## 背景

Issue #51 は Parent: #12 の子 Issue として、v1 の主要画面に loading、empty、error、retry、一時 feedback の一貫した挙動を適用する。対象は横断タイムライン、フィード別記事一覧、スター一覧、横断検索、記事詳細 sheet、フィード登録、購読設定、アカウント、ログアウト、退会を含む v1 画面である。

`design/SPEC-iOS.md` では、各一覧に空状態 / エラー / ローディングを用意すること、フィード別一覧の停止 / エラー時には警告バナーと再開導線を出すこと、フィード別 Pull-to-refresh の `FEED_COOLDOWN` では `retry_after_seconds` を案内すること、mutation は失敗時にユーザーへ表示可能な feedback を出すことが示されている。`design/SERVER.md` と `design/SPEC-iOS.md` の API 契約では、エラー形式は `{ error: { code, message, category, action, details? } }` であり、429 / `FEED_COOLDOWN` は `details.retry_after_seconds` と `Retry-After` header を持つ。

既存 Issue では #27 が shared loading / empty / recoverable error / toast / banner primitive、#33 が Timeline refresh / pagination state、#37 が read/star mutation failure rollback、#41 が manual feed fetch cooldown、#44 が feed registration 後の subscription refresh、#45 が Starred list、#47 が Search result to detail bridge、#50 が account deletion confirmation flow を扱っている。本 Issue はこれらを前提に、画面ごとの個別実装を横断レビューして一貫性を仕上げる。

## Issue コメントの反映

`gh issue view 51 --comments` で確認できたコメントは以下である。

- 依存 Issue #33 / #37 / #41 / #44 / #45 / #47 / #50 はすべて `staged-for-release` になり、`codex-blocked` が自動解除された。
- Path Overlap Checker の edit path は `Feedman/` と `FeedmanTests/` である。
- ローカル Codex CLI が design モードで処理を開始した。

loading / error / retry の具体文言や追加 scope に関する人間の決定コメントはない。

## スコープ

- v1 主要画面の初回 loading、初回 empty、初回 recoverable error、retry 導線、refresh / pagination failure、mutation failure feedback を一貫した policy に揃える。
- 既存 `Feedman/DesignSystem/SharedPrimitives.swift` の primitive を優先利用し、不足する小さな descriptor / helper があれば DesignSystem または Feature 内に追加する。
- ViewModel が repository error を UI 表示可能な title / message / retry action / auth-required boundary へ変換する責務を明確化する。
- recoverable error の retry は同じ操作を再実行する。初回読み込み retry、refresh retry、next page retry、mutation retry は混同しない。
- mutation failure は navigation state、sheet presentation、visible list を失わない non-destructive feedback として扱う。
- Drawer subscriptions、Login / auth restoration の loading / failure / retry も v1 主要導線として点検する。
- route、feed、filter、search query、selected item の変更後に stale async response が現在の表示を上書きしないことを確認する。
- XCTest で主要画面の loading / empty / error / retry / mutation failure state を mock repository で検証する。

## スコープ外

- v1 を超える新機能。
- キーワードプッシュ通知、OPML import/export、フィード URL 変更 UI、オフライン全文 cache、Feed-scoped search UI、WebView Cookie login fallback。
- 新規 server API、API response shape の変更、prototype mock JSON を API 契約として扱うこと。
- shared global state store の新規設計。ただし既存 `ItemStateCoordinator` の利用確認は含む。
- 既存 `docs/specs/*`、`design/SPEC-iOS.md`、`design/SERVER.md`、prototype files の変更。
- 実装範囲が大きくなる場合の全画面リライト。必要なら追加子 Issue へ分割する。

## 要件

### Requirement 1: Major screen initial loading / empty / error consistency

**Objective:** As a Feedman user, I want 各 v1 画面の読み込み中・空・失敗状態が同じ操作感で表示される, so that 画面を移動しても次に何をすればよいか迷わない

#### Acceptance Criteria

1. When API is slow on a major v1 screen, the screen shall show a visible loading state using shared DesignSystem primitives or an equivalent existing shared surface.
2. When the first page succeeds with no content, list screens shall show an empty state with screen-specific title, optional explanation, and an appropriate primary action only where useful.
3. When the first page fails with a recoverable error, list screens and loading sheets shall show a recoverable error state with retry.
4. When retry is activated from an initial error state, the ViewModel shall retry the same first-load operation that failed.
5. When a screen has existing visible content and a refresh fails, the screen shall preserve the visible content and show non-destructive feedback rather than replacing the screen with full-screen initial error.
6. When a screen has existing visible content and next-page loading fails, the screen shall preserve loaded items, keep pagination state retryable, and expose retry for the next page only.
7. If an error is not recoverable in-place because authentication is required, the screen shall route to the existing auth-required/session-loss handling instead of presenting a misleading retry loop.

### Requirement 2: Retry action semantics

**Objective:** As a Developer, I want retry action の意味を画面ごとに固定する, so that retry tap が別の request や destructive action を誤って実行しない

#### Acceptance Criteria

1. When initial load retry is tapped, the app shall call the same repository first-load method for that screen.
2. When refresh retry is offered after refresh failure, the app shall call the same refresh operation and shall not call next-page loading.
3. When next-page retry is tapped, the app shall request the next page using repository pagination state and shall not reset the first page session.
4. When feed-specific manual refresh fails with `FEED_COOLDOWN`, retry shall not be offered as an immediate action unless the UI clearly communicates the cooldown timing.
5. When mutation retry is offered, it shall retry only the failed mutation and shall not reload the entire screen unless the existing feature explicitly requires it.
6. If a destructive mutation fails, retry shall remain behind the same confirmation or explicit action boundary that protected the original mutation.
7. While an operation is in flight, duplicate retry taps for the same operation shall be ignored or disabled.

### Requirement 3: Mutation failure feedback preserves navigation state

**Objective:** As a Feedman user, I want 操作失敗時に現在の画面や sheet を失わずに理由と次の行動が分かる, so that 一時的な通信失敗でも作業を続けられる

#### Acceptance Criteria

1. When read/star mutation fails, the app shall roll back only the failed field and show non-blocking feedback.
2. When feed registration fails, the registration sheet shall keep the entered URL and show actionable error text.
3. When subscription settings save/resume/unsubscribe fails, the settings sheet shall keep the sheet open and preserve current selection / confirmation context as appropriate.
4. When account deletion fails before success, the app shall keep authenticated session state and show failure feedback in the account flow.
5. When logout fails before local clear policy is applied, the app shall follow the existing logout spec and show feedback without leaving the UI in an ambiguous half-logged-out state.
6. When mutation feedback is shown, it shall not dismiss article detail, registration, settings, account, or search presentation unless the mutation itself succeeded and the owning spec requires dismissal.
7. When multiple transient messages occur, the app shall use deterministic toast/banner replacement or existing feature-local message state, avoiding overlapping alerts.

### Requirement 4: Error presentation mapping

**Objective:** As a Developer, I want repository/API errors を UI 表示可能な category に変換する境界を明確にする, so that View が APIClient や raw error details に依存しない

#### Acceptance Criteria

1. When a `FeedmanAPIError.transportFailed` occurs, the UI shall present network-oriented guidance.
2. When a typed Feedman error response occurs, the ViewModel shall map code/category/action/details to Japanese title/message/action suitable for the current screen.
3. When `FeedmanAPIError.authRequired` occurs, the ViewModel or route owner shall expose auth-required handling instead of silently treating it as empty state.
4. When `FEED_COOLDOWN` or 429 with retry-after information occurs, feed refresh / registration related UI shall present retry timing where applicable.
5. When an unknown or malformed response occurs, the UI shall present a generic recoverable message and avoid exposing raw server payload, token, or personal data.
6. When a shared UI primitive displays an error, it shall receive already mapped title/message/action and shall not inspect endpoint-specific API error codes directly.

### Requirement 5: Coverage across v1 screens

**Objective:** As a QA/Developer, I want v1 画面ごとの状態 coverage を明示する, so that polish の抜け漏れを実装 PR で検出できる

#### Acceptance Criteria

1. When the implementation is complete, Timeline shall cover initial loading, empty, initial error retry, refresh failure preservation, next-page failure retry, and read/star mutation feedback.
2. When the implementation is complete, Feed list shall cover initial loading, empty by filter, initial error retry, status banner/resume, manual refresh cooldown/failure feedback, next-page failure retry, and read/star mutation feedback.
3. When the implementation is complete, Starred list shall cover initial loading, empty, initial error retry, refresh failure preservation, next-page failure retry, unstar failure restoration, and auth-required boundary.
4. When the implementation is complete, Global search shall cover idle suggestions, loading, empty results, error retry, auth-required boundary, result-to-detail failure feedback, and preservation of query text.
5. When the implementation is complete, Article detail shall cover summary/loading, detail loading, detail error retry, read marking failure, star mutation failure, and original-link failure feedback where the existing presenter can report it.
6. When the implementation is complete, Register feed shall cover submit loading, validation errors, duplicate/rate-limit/network/generic failures, success feedback, and preserving input on failure.
7. When the implementation is complete, Subscription settings shall cover busy states, success/failure messages, resume failure, unsubscribe confirmation failure, and preserving sheet context.
8. When the implementation is complete, Account / logout / deletion shall cover current-user loading, current-user error retry, logout/deletion in-flight states, failures, and session transition boundaries.
9. When the implementation is complete, Drawer subscriptions shall cover loading, empty, failure retry, previous feed preservation where available, and global drawer route usability.
10. When the implementation is complete, Login / auth restoration shall cover in-flight duplicate prevention, cancellation/failure feedback, restoration failure, credential clearing, and unauthenticated transition.

### Requirement 6: Navigation and stale response stability

**Objective:** As a Feedman user, I want route や入力を変えた後に古い通信結果で画面が戻らない, so that 自分が選んだ現在の文脈で操作を続けられる

#### Acceptance Criteria

1. When the user changes feed, filter, route, search query, or selected item while an async request is in flight, stale response shall not overwrite the currently visible state.
2. When Search retry or response completes after the query was changed, the Search screen shall keep the newer query state.
3. When Feed first-page response completes after feed id or filter was changed, the Feed screen shall apply the response only to the matching session.
4. When a sheet-local operation fails, the parent route shall remain intact behind the sheet.
5. When Drawer subscriptions are loading, empty, or failed, global drawer entries such as Timeline, Starred, Search, and Account shall remain usable.
6. When login is cancelled or fails, the app shall remain on the login screen and allow another login attempt.
7. When launch auth restoration fails due to invalid refresh token, the app shall clear stored credentials through the existing auth boundary and show login rather than a loaded shell.

### Requirement 7: Tests and verification

**Objective:** As a QA/Developer, I want 状態遷移が単体テストで固定される, so that 横断 polish の回帰を検出できる

#### Acceptance Criteria

1. When ViewModel tests are added or updated, they shall use mock repositories and shall not depend on real network, real Keychain, or real OAuth.
2. When loading state is tested, tests shall assert that slow repository operations expose an in-flight state before completion.
3. When empty state is tested, tests shall assert that empty responses are not treated as errors.
4. When recoverable error is tested, tests shall assert retry calls the correct operation and clears failure feedback on success.
5. When refresh / next-page failures are tested, tests shall assert existing visible content is preserved.
6. When mutation failures are tested, tests shall assert navigation/sheet state is preserved and actionable feedback is exposed.
7. When auth-required is tested, tests shall assert the auth-required boundary is invoked or exposed instead of producing misleading empty success.
8. When stale async response handling is tested, tests shall assert older responses do not overwrite newer feed/filter/query/route state.
9. When macOS/Xcode environment is available, the implementer shall run `xcodebuild -project Feedman.xcodeproj -scheme Feedman -destination 'platform=iOS Simulator,name=iPhone 16' test`.
10. While Xcode is unavailable, the implementer shall report the exact reason and run practical local checks such as `plutil -lint` and `git diff --check`.

## 非機能要件

### NFR 1: Architecture

1. The implementation shall follow MVVM + Repository.
2. View shall not directly access `URLSession`, Keychain, Bearer tokens, request encoding, or endpoint-specific error parsing.
3. ViewModel / UI state that mutates from async work shall be `@MainActor` where appropriate.
4. Swift type names, identifiers, and file names shall be English.
5. API date strings shall remain RFC3339 `String` values until formatted for display.

### NFR 2: UX / Accessibility

1. Loading, empty, error, retry, toast, banner, and sheet feedback shall remain readable with Dynamic Type and shall not overlap adjacent controls.
2. Error and warning states shall not rely on color alone.
3. Retry and destructive actions shall expose accessible labels and disabled/in-flight states.
4. Existing navigation state, selected route, active sheet, and search query shall be preserved when recoverable errors occur.
5. Toast, banner, and sheet-local messages shall not make underlying navigation or dismissal controls unusable.
6. User-facing errors, logs, and tests shall not expose access tokens, refresh tokens, `Authorization` headers, private search queries, private article content, or private subscription data.

### NFR 3: Scope control

1. The implementation shall remain within Issue #51 の横断 polish responsibility.
2. The implementation shall not introduce new v1+ features or server API requirements.
3. The implementation shall not rewrite completed specs under `docs/specs/*`.
4. If consistent polish requires more than a thin cross-screen pass, the implementer shall split follow-up child Issues instead of broadening this implementation PR.

## 確認事項

- 画面ごとの最終文言は既存実装にある日本語文言を優先し、欠落している箇所だけ追加する。
- Toast / banner のグローバル queue 化は必須ではない。既存 `FeedmanToast` / `FeedmanBannerView` / feature-local message のうち、最小変更で一貫性を満たせるものを使う。
- Auth-required の最終遷移は既存 AppShell / AppEnvironment の session-loss 方針に合わせる。Issue #51 では新しい認証フローを作らない。
