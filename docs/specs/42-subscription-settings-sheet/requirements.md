# Issue #42 Subscription settings sheet 要件定義

## 背景

Issue #42 は Parent: #8 の子 Issue として、購読フィードの設定 sheet からフェッチ間隔更新、停止/エラー状態からの再開、購読解除確認を行う薄い縦切りを定義する。
`design/SPEC-iOS.md` §5.6 は購読設定を `.sheet` + `.presentationDetents` のボトムシートとして表示し、フェッチ間隔セグメント（15/30/60/180/360分）を `PUT /api/subscriptions/{id}/settings`、再開を `POST /api/subscriptions/{id}/resume`、購読解除を確認 `.alert` 付きの `DELETE /api/subscriptions/{id}` へ接続すると定義している。
API 契約は `design/SPEC-iOS.md` と `design/SERVER.md` を優先し、prototype や mock data の JSON 形を API 契約として扱わない。

Issue #42 の本文では、期待する挙動として "Subscription settings sheet supports interval update, resume, and unsubscribe confirmation." が示され、受入基準候補として interval 保存時の settings endpoint 呼び出し、stopped/error feed の resume endpoint 呼び出し、unsubscribe 確認後の subscription 削除とローカル除去が挙げられている。
Issue コメントは 2026-06-12 時点で Path Overlap Checker の edit paths `Feedman/`、`FeedmanTests/` と処理開始通知のみで、追加の仕様決定はない。

依存 Issue は `Depends on: #27, #38` である。
`gh issue view 27 --json number,state,title,labels` と `gh issue view 38 --json number,state,title,labels` の確認では、どちらも GitHub Issue state は `OPEN` だが `codex-staged-for-release` ラベル付きであり、develop には入ったが main には未到達の扱いとする。
#27 の共有 loading/empty/error/toast/sheet primitives と #38 の real subscriptions drawer data は実装前提として扱い、追加 blocker にはしない。

## 現行コンテキスト

- #38 では settings sheet、購読解除、fetch interval 変更、再開、手動 fetch は明示的にスコープ外とされ、#42 の境界として残されている。
- #38 の要件と実装ノートでは、drawer route には `feed_id` を使い、settings / unsubscribe actions には `Subscription.id` を使う方針が示されている。
- 現行 Core には `Subscription` と `SubscriptionSettingsRequest` があり、`SubscriptionSettingsRequest` は `fetch_interval_minutes` を JSON body として表現できる。
- `Feed` domain model の `id` は #38 の方針により feed route 用の `feed_id` として扱われるため、#42 では settings sheet を開くための view state / domain state に `Subscription.id` を保持する必要がある。
- `Feedman/Features/Subscriptions/` は現時点で存在しないため、実装時は同 feature directory を新設するか、既存 AppShell との境界を保てる最小構成を選ぶ。

## スコープ

- 購読設定 sheet を SwiftUI `.sheet` と iOS 16+ compatible detents で表示する。
- 対象 subscription の現在の feed title、fetch interval、feed status、error message、subscription id、feed id を sheet に渡せる状態にする。
- Fetch interval を 15/30/60/180/360 分の選択肢から変更し、保存時に `PUT /api/subscriptions/{id}/settings` を呼ぶ。
- 対象 feed が `stopped` または `error` のとき、sheet から再開操作を行い、`POST /api/subscriptions/{id}/resume` を呼ぶ。
- 購読解除は destructive action とし、確認 alert で明示確認された場合のみ `DELETE /api/subscriptions/{id}` を呼ぶ。
- Settings / resume / unsubscribe の loading、success、recoverable error state を ViewModel で扱い、View は Repository abstraction 経由で操作する。
- 成功後、drawer/feed list のローカル状態を更新または subscriptions を再読み込みし、アプリ再起動なしに画面へ反映する。
- Unit test は repository request、ViewModel state、確認 alert 後の削除、ローカル反映を中心に実ネットワークや実 Keychain に依存せず検証する。

## スコープ外

- Feed registration と OPML import/export。
- Manual fetch / Pull-to-refresh 用 `POST /api/subscriptions/{id}/fetch`。
- Feed-scoped search UI。
- Keyword notifications、keyword settings sheet、drawer 導線。
- フィード URL 変更 UI、manual feed metadata editing。
- フィード別記事一覧の本実装、横断タイムライン、スター一覧、検索、記事詳細 sheet、既読/スター更新の本実装。
- サーバー API 契約の変更、endpoint 追加、`design/SPEC-iOS.md`、`design/SERVER.md`、確定済み `docs/specs/*` の変更。
- `feed_id` を settings / delete endpoint の path id として流用する実装。

## 要件

### Requirement 1: Subscription action repository contract

**Objective:** As a Subscriptions feature ViewModel 実装者, I want settings / resume / unsubscribe を mockable repository 経由で呼べる, so that View が `URLSession` や token storage に直接依存しない

#### Acceptance Criteria

1. When the app needs to update a subscription interval, it shall expose a repository method that accepts a `subscriptionID` and `SubscriptionSettingsRequest` or equivalent typed request.
2. When the app needs to resume a subscription, it shall expose a repository method that accepts a `subscriptionID`.
3. When the app needs to unsubscribe, it shall expose a repository method that accepts a `subscriptionID`.
4. When the real repository sends settings update, it shall call `PUT /api/subscriptions/{id}/settings` with Bearer authentication.
5. When the real repository sends resume, it shall call `POST /api/subscriptions/{id}/resume` with Bearer authentication.
6. When the real repository sends unsubscribe, it shall call `DELETE /api/subscriptions/{id}` with Bearer authentication.
7. When these endpoints return no content, the repository shall treat successful 2xx no-content responses as success.
8. If an endpoint returns an updated subscription body, the implementation may decode and use it, but shall not require a response body unless `design/SPEC-iOS.md` / `design/SERVER.md` is updated.
9. The sheet and ViewModel shall not read or write Keychain, construct raw `URLSession` requests, or implement token refresh directly.

### Requirement 2: Subscription id and feed id separation

**Objective:** As a Developer, I want action ids to be unambiguous, so that drawer navigation and subscription mutation do not accidentally use the wrong identifier

#### Acceptance Criteria

1. When a drawer feed row opens settings, the app shall pass the stable `Subscription.id` as the endpoint path id for settings, resume, and delete actions.
2. When a drawer feed row navigates to feed articles, the app shall continue to use `feed_id` for route state as defined by #38.
3. When `Feed.id` currently represents `feed_id`, the implementation shall add the minimum view state, domain field, or action context needed to retain `Subscription.id`.
4. When a subscription is deleted, local removal shall match by `Subscription.id` where available and shall not remove an unrelated row solely because a display title matches.
5. When a later subscriptions reload returns rows, the latest server response shall remain the source of truth for both `Subscription.id` and `feed_id`.
6. If a row lacks `Subscription.id` due to unexpected data or migration state, the settings action shall be disabled or fail safely rather than calling mutation endpoints with `feed_id`.

### Requirement 3: Settings sheet presentation and initial state

**Objective:** As a Feedman user, I want to open a compact settings sheet for a subscription, so that I can adjust or remove the subscription without leaving the main flow

#### Acceptance Criteria

1. When the user activates a feed row settings affordance, the app shall present a subscription settings sheet for that specific subscription.
2. When the sheet appears, it shall show the feed title and current fetch interval from the subscription state.
3. When the current interval is one of 15, 30, 60, 180, or 360 minutes, the matching segment shall be selected.
4. If the current interval is not one of 15, 30, 60, 180, or 360 minutes, the sheet shall preserve the value in state and avoid silently saving a different interval until the user selects a supported interval.
5. When the sheet appears for an `active` feed, resume shall not be shown as the primary available action.
6. When the sheet appears for a `stopped` or `error` feed, resume shall be available with short Japanese status guidance.
7. When `error_message` is present for a stopped/error feed, the sheet may show it as supporting text after converting it into a user-safe display string.
8. The sheet shall use SwiftUI `.sheet` and `.presentationDetents`; `.medium` and `.large` are acceptable.
9. The sheet shall use #27 sheet/error/toast primitives and `FeedmanTheme` where they fit the existing DesignSystem.
10. The sheet shall not show feed registration, OPML, manual fetch, feed-scoped search, or keyword notification controls.

### Requirement 4: Fetch interval update

**Objective:** As a Feedman user, I want to change the fetch interval from predefined choices, so that the feed updates at the cadence I choose

#### Acceptance Criteria

1. When the user selects a fetch interval, the sheet shall update local selection without immediately calling the settings endpoint.
2. When interval is saved, the app shall call `PUT /api/subscriptions/{id}/settings`.
3. When interval is saved, the request body shall include `fetch_interval_minutes` with one of 15, 30, 60, 180, or 360.
4. When the selected interval equals the current persisted interval, the app may disable save or treat save as a no-op without calling the endpoint.
5. While interval save is in progress, the save control shall prevent duplicate concurrent saves for the same sheet instance.
6. When interval save succeeds, the sheet shall update persisted interval state locally or trigger a subscriptions reload.
7. When interval save succeeds, the user shall receive visible success feedback such as a toast/banner or in-sheet saved state.
8. When interval save fails, the sheet shall keep the selected value editable and show a recoverable error.
9. If the failure is auth-required after refresh retry fails, the ViewModel shall surface an auth-required/recoverable state without clearing credentials directly.

### Requirement 5: Resume stopped or error feed

**Objective:** As a Feedman user, I want to resume a stopped or error subscription from the settings sheet, so that the feed can be fetched again

#### Acceptance Criteria

1. When resume is tapped for stopped/error feed, the app shall call `POST /api/subscriptions/{id}/resume`.
2. When the feed status is `active`, the sheet shall not call resume from a visible action.
3. While resume is in progress, the resume control shall prevent duplicate concurrent resume calls.
4. When resume succeeds, the local feed status shall be updated to active or the subscriptions list shall be reloaded.
5. When resume succeeds, stopped/error guidance for that sheet shall be cleared or replaced by success feedback.
6. When resume fails, the sheet shall keep the subscription visible and show a recoverable error.
7. If the server returns a typed API error, the ViewModel shall preserve enough context to map it to user-facing Japanese guidance.
8. Resume shall use `Subscription.id` in the endpoint path and shall not use `feed_id`.

### Requirement 6: Unsubscribe confirmation and local removal

**Objective:** As a Feedman user, I want unsubscribe to require confirmation, so that I do not accidentally remove a feed

#### Acceptance Criteria

1. When the user taps unsubscribe, the app shall present a destructive confirmation alert before any delete request is sent.
2. When the user cancels the confirmation alert, the app shall not call `DELETE /api/subscriptions/{id}`.
3. When unsubscribe is confirmed, the app shall call `DELETE /api/subscriptions/{id}`.
4. When unsubscribe is confirmed, the delete request shall use `Subscription.id` and Bearer authentication.
5. While unsubscribe is in progress, destructive controls shall prevent duplicate delete calls.
6. When unsubscribe succeeds, the app shall delete subscription and remove it locally.
7. When unsubscribe succeeds, if the removed subscription is currently selected in route state, the app shall route to a safe fallback such as `すべての新着` instead of leaving a stale selected feed.
8. When unsubscribe succeeds, the settings sheet shall dismiss or show a completion state that cannot trigger duplicate delete.
9. When unsubscribe fails, the subscription shall remain in local UI state and the user shall see a recoverable error.
10. The confirmation alert shall use clear Japanese wording that includes the feed title where available and communicates that this removes the subscription.

### Requirement 7: AppShell and drawer integration

**Objective:** As a Feedman user, I want settings changes to be reflected in the drawer, so that the visible feed list stays consistent after actions

#### Acceptance Criteria

1. When the drawer renders subscription rows, each row shall expose a settings affordance consistent with `design/SPEC-iOS.md` §5.0.
2. When the settings affordance is activated, it shall not trigger feed navigation as a side effect.
3. When settings save succeeds, drawer state shall reflect the updated fetch interval if that value is displayed or stored locally.
4. When resume succeeds, drawer status indicator shall no longer show stopped/error after local update or reload completes.
5. When unsubscribe succeeds, drawer feed list shall remove the subscription without requiring app relaunch.
6. When any action succeeds and a reload is chosen, global drawer routes such as `すべての新着`、`お気に入り`、`アカウント` shall remain usable during reload.
7. When local update and server reload conflict, the latest successful server response shall replace optimistic/local state.
8. The implementation shall not introduce keyword notification drawer entries.

### Requirement 8: Error handling and feedback

**Objective:** As a Feedman user, I want failed settings actions to be clear and recoverable, so that I know whether to retry or leave the sheet

#### Acceptance Criteria

1. When settings, resume, or unsubscribe fails with a recoverable API or transport error, the sheet shall show a short Japanese error and allow retry where retry is meaningful.
2. When the API error body contains `{ error: { code, message, category, action, details? } }`, the repository shall preserve typed context for ViewModel mapping.
3. When a `401` occurs, the shared #23 APIClient refresh retry hook shall run before the ViewModel receives failure.
4. When refresh and retry succeed, the action shall complete as normal without exposing a transient auth error.
5. When refresh fails, the ViewModel shall surface auth-required or recoverable app-level error without reading or clearing Keychain directly.
6. When an action is loading, the sheet shall keep stable layout and avoid overlapping buttons, progress indicators, and messages.
7. Error text shall not expose token values, raw debug details, or personally sensitive data.
8. A failure in one action shall not corrupt unrelated sheet state; for example, failed resume shall not change the selected interval.

### Requirement 9: Mock behavior, previews, and tests

**Objective:** As a QA/Developer, I want subscription settings behavior to be testable without the real server, so that action state and local updates are deterministic

#### Acceptance Criteria

1. When using a mock repository, interval update shall record the requested `subscriptionID` and `fetch_interval_minutes`.
2. When using a mock repository, resume shall record the requested `subscriptionID` and allow deterministic success or failure.
3. When using a mock repository, unsubscribe shall record the requested `subscriptionID` and allow deterministic success or failure.
4. When repository tests cover settings save, they shall verify `PUT /api/subscriptions/{id}/settings`, JSON body, and Bearer authorization using mock transport.
5. When repository tests cover resume, they shall verify `POST /api/subscriptions/{id}/resume` and Bearer authorization.
6. When repository tests cover unsubscribe, they shall verify `DELETE /api/subscriptions/{id}` and Bearer authorization.
7. When ViewModel tests cover interval save, they shall verify selection, loading, success feedback state, duplicate-save prevention, and failure recovery.
8. When ViewModel tests cover resume, they shall verify that resume is available for stopped/error state and not called for active state.
9. When ViewModel tests cover unsubscribe, they shall verify cancel does not call repository and confirm calls repository once.
10. When AppShell/drawer integration tests are practical, they shall verify settings affordance presentation, local removal after delete, and route fallback when deleting the selected feed.
11. Unit tests shall not depend on real network, real OAuth, real Keychain, real tokens, or personal data.
12. When macOS/Xcode test execution is available, the implementer shall run `xcodebuild -project Feedman.xcodeproj -scheme Feedman -destination 'platform=iOS Simulator,name=iPhone 16' test` or report why it could not be run.

## 非機能要件

### NFR 1: Compatibility

1. The implementation shall target iOS 16+ and SwiftUI.
2. The implementation shall follow MVVM + Repository and Swift Concurrency (`async` / `await`).
3. Views shall not directly touch `URLSession`, Keychain, raw token storage, or raw endpoint URL construction.
4. Swift type names, identifiers, and file names shall be English.
5. API date string handling shall remain unchanged; this Issue shall not introduce automatic `Date` decoding.

### NFR 2: Accessibility and layout

1. The sheet shall provide accessible labels for dismiss, interval picker, save, resume, unsubscribe, loading, error, and confirmation controls.
2. The destructive unsubscribe action shall not rely on color alone.
3. Dynamic Type shall not cause feed title, status text, interval segments, buttons, or error text to overlap.
4. The sheet shall keep iOS-appropriate touch targets for primary and destructive actions.
5. Long feed titles and long error messages shall wrap or truncate predictably without hiding primary actions.

### NFR 3: Scope control

1. The implementation shall remain within Issue #42 の subscription settings sheet responsibility.
2. The implementation shall not implement Feed registration, OPML, manual fetch, feed-scoped search, keyword notifications, or feed URL editing.
3. The implementation shall not rewrite finalized specs for other Issues.
4. The implementation shall not create PRs, invoke Reviewer/PjM agents, commit changes, or perform release operations as part of this PM requirements task.

## API / データ契約

- `PUT /api/subscriptions/{id}/settings`
  - 認証: `Authorization: Bearer <access_token>`。
  - Request: `SubscriptionSettingsRequest`。本 Issue の最小対象は `{"fetch_interval_minutes": 15|30|60|180|360}`。
  - Success: 2xx を成功として扱う。レスポンス body の有無は要求しない。
- `POST /api/subscriptions/{id}/resume`
  - 認証: `Authorization: Bearer <access_token>`。
  - Request body: `design/SPEC-iOS.md` / `design/SERVER.md` に追加指定がないため、本 Issue では body なしを基本とする。
  - Success: 2xx を成功として扱う。成功後は local status update または subscriptions reload で反映する。
- `DELETE /api/subscriptions/{id}`
  - 認証: `Authorization: Bearer <access_token>`。
  - Request body: なし。
  - Success: 2xx を成功として扱う。成功後は対象 subscription をローカルから除去する。
- `id` は `Subscription.id` を指す。`feed_id` は feed route / article list 用の identifier として保持する。
- Error: 既存形式 `{ error: { code, message, category, action, details? } }` を typed error として保持し、UI 表示文は短い日本語へ変換する。
- 401: #23 の APIClient refresh retry hook に従う。Feature ViewModel は refresh endpoint を直接呼ばない。

## 実装境界

- Core:
  - `FeedRepository` を拡張するか、subscription action 用の小さな repository protocol を追加する。
  - Real repository は `APIClient` と access token provider / auth boundary を利用する。
  - `SubscriptionSettingsRequest` を再利用し、prototype-only field を追加しない。
- Subscriptions feature:
  - `Feedman/Features/Subscriptions/` または同等の feature 境界に settings sheet と ViewModel を置く。
  - ViewModel は selected interval、loading/error/success、confirmation state、action event を調停する。
  - View は repository や AppShell から渡された state/action closure を使い、transport detail を持たない。
- AppShell:
  - Drawer row の settings affordance、sheet presentation、成功後の local update/reload、選択 feed 削除時の route fallback を担当する。
  - Feed route selection は #38 の `feed_id` 方針を維持する。
- Scope control:
  - 実装 PR ではこの要件定義を根拠に `design/SPEC-iOS.md`、`design/SERVER.md`、他 Issue の確定 specs を変更しない。
  - PR 作成、reviewer/project-manager 起動、コミットは本 PM 作業の範囲外。

## 確認事項

- #27 / #38 は Issue state が `OPEN` でも、`codex-staged-for-release` ラベルにより develop 済み・main 未到達として扱う。
- `PUT /api/subscriptions/{id}/settings`、`POST /api/subscriptions/{id}/resume`、`DELETE /api/subscriptions/{id}` の成功 response body は `design/SPEC-iOS.md` / `design/SERVER.md` に明記されていないため、実装では 2xx no-content 成功を扱えるようにする。body が返る場合の decode 利用は任意とする。
- Current interval が 15/30/60/180/360 以外の場合の最終 UX は未確定である。要件上は値を勝手に変更せず、ユーザーが supported interval を選ぶまで保存しない方針を固定する。
- Unsubscribe 成功後に drawer を「ローカル除去」するか「subscriptions reload」するかは実装時に既存 AppShell state と整合する方法を選んでよい。ただしアプリ再起動なしに除去が反映されることは必須とする。
- Resume 成功後の server-side fetch 開始タイミングや unread count 更新は本 Issue では要求しない。status 反映または subscriptions reload までを範囲とする。
