# Issue #41 Manual feed fetch and cooldown handling 要件定義

## 概要

Issue #41 は Parent: #8 の子 Issue として、フィード別記事一覧の Pull-to-refresh から購読単位の手動 fetch endpoint を呼び、成功後に表示中フィードの記事一覧を再読み込みし、`FEED_COOLDOWN` をユーザーに案内する。

`design/SPEC-iOS.md` では、フィード別記事一覧の Pull-to-refresh は `.refreshable` で `POST /api/subscriptions/{id}/fetch` を呼び、`FEED_COOLDOWN` 時に `retry_after_seconds` をトーストまたはバナーで案内すると定義している。API エラー形式は `{ error: { code, message, category, action, details? } }` であり、`429 / FEED_COOLDOWN` は `details.retry_after_seconds` と `Retry-After` header を返す。

本 Issue は feed-specific refresh に限定する。`design/SPEC-iOS.md` 付録 A の決定事項どおり、横断 Pull-to-refresh は `GET /api/items/cross-feed` の再取得のみであり、本 Issue では Cross-feed refresh behavior を変更しない。

## 参照仕様

- Issue #41 本文と `gh issue view 41 --comments` の既存コメント
- `design/SPEC-iOS.md` §4.1, §4.2, §5.2, §6, §10, §11, 付録 A
- `design/SERVER.md` §1 の Bearer 認証、error response 形式、後方互換方針
- #15 `docs/specs/15-feedman-error-response-decoding/requirements.md`
- #16 / #23 の APIClient error decode / 401 refresh retry contract
- #39 `docs/specs/39-feed-item-list-repository-with-filters-a/requirements.md`
- #40 `docs/specs/40-feed-screen-ui-with-filters-and-status-b/requirements.md`
- 既存 `Feedman/Core/FeedRepository.swift` の `FeedRepository`、`Feed`、`FeedItemPaginationSnapshot`
- 既存 `Feedman/Features/Feeds/FeedViewModel.swift` と `Feedman/Features/Feeds/FeedView.swift`

## 依存判断

Issue 本文の依存は `Depends on: #15, #40` である。

- #15 により、`FEED_COOLDOWN` の `details.retry_after_seconds` と `Retry-After` header を typed app error から参照できる。
- #40 により、フィード別記事一覧 screen、ViewModel、filter、status banner、first page reload、pagination 表示が利用可能である。
- Issue #41 のコメントでは、依存先 #15 / #40 は staged-for-release となり、`codex-blocked` が自動解除されたことを確認した。

したがって本 Issue は #15 と #40 の成果物を前提とする。ただし、確定済み `docs/specs/*`、`design/SPEC-iOS.md`、`design/SERVER.md` は本 Issue で書き換えない。

## スコープ

- `FeedRepository` に購読単位の手動 fetch を実行する boundary を追加する。
- Real repository は `POST /api/subscriptions/{id}/fetch` を shared `APIClient` 経由で呼ぶ。
- Feed screen は SwiftUI `.refreshable` で手動 fetch を起動する。
- 手動 fetch 成功後、表示中の feed id と現在選択中 filter の first page を再読み込みする。
- `FEED_COOLDOWN` を typed error から判定し、`retry_after_seconds` または `Retry-After` 由来の秒数を含めた retry-after guidance を表示する。
- Pull-to-refresh 中の重複実行、既存 first-page / next-page load との競合、失敗時の既存一覧保持を ViewModel で制御する。
- Mock repository と ViewModel / repository unit tests を更新し、success、cooldown、generic error、duplicate refresh の主要状態を検証する。

## スコープ外

- Cross-feed refresh behavior、横断タイムラインの Pull-to-refresh、`GET /api/items/cross-feed` の仕様変更。
- `POST /api/subscriptions/{id}/resume`、購読設定 sheet、fetch interval 変更、購読解除。
- サーバー API、`design/SPEC-iOS.md`、`design/SERVER.md`、prototype files の変更。
- Article detail sheet、SFSafariViewController、既読化、スター同期、cross-screen optimistic update。
- Drawer subscription list の自動再取得、未読数再集計、feed status の再取得。ただし既存の app-shell 状態更新機構が既にある場合の非破壊的な連携は妨げない。
- Push notification、OPML、feed URL 変更 UI、feed-scoped search UI。
- PR 作成、reviewer / project-manager 起動。

## 要件

### Requirement 1: Manual fetch repository contract

**Objective:** As a Feedman user, I want フィード別一覧を手動で取得更新できる, so that 定期取得を待たずに最新記事を確認できる

#### Acceptance Criteria

1. When a feed refresh is requested for a subscription, the repository shall provide a method that accepts a `subscriptionID`.
2. When the manual fetch repository method is called, the real repository shall send `POST /api/subscriptions/{id}/fetch`.
3. When composing the fetch endpoint path, the repository shall use `subscriptionID` from the selected `Feed`, not `feedID`.
4. When the fetch endpoint returns any successful 2xx response, the repository shall treat the manual fetch request as successful without requiring a response body that is not defined in `design/SPEC-iOS.md`.
5. When the fetch endpoint returns a Feedman standard error response, the repository shall surface the existing typed API error without parsing response JSON in View or ViewModel code.
6. When the fetch endpoint returns `401`, the APIClient shall use the existing Bearer refresh retry behavior and the repository shall not implement its own token refresh logic.
7. The repository shall keep View code isolated from `URLSession`, Keychain, Bearer token headers, and raw HTTP response parsing.

### Requirement 2: Pull-to-refresh integration on feed screen

**Objective:** As a Feedman user, I want フィード別画面で下へ引いて更新できる, so that iOS 標準の操作で手動 fetch を実行できる

#### Acceptance Criteria

1. When the user performs Pull-to-refresh on a feed-specific screen, the app shall call the manual subscription fetch repository method.
2. When the selected feed has a non-empty `subscriptionID`, the app shall pass that value to the manual fetch repository method.
3. If the selected feed lacks `subscriptionID`, the app shall not call `/api/subscriptions/{id}/fetch` with `feedID` as a fallback and shall show recoverable failure guidance.
4. When Pull-to-refresh starts, the Feed screen shall use SwiftUI `.refreshable` or an equivalent iOS 16+ refresh affordance.
5. When Pull-to-refresh is active, the ViewModel shall expose refresh-in-progress state if needed for duplicate suppression and user feedback.
6. While a manual refresh is already in progress for the same visible feed/filter session, additional refresh gestures shall not issue duplicate fetch requests.
7. While a first-page load or next-page load is in progress, a manual refresh shall avoid corrupting pagination state; the implementation shall serialize, cancel, or queue work in a deterministic way.
8. The Pull-to-refresh implementation shall be attached only to feed-specific article lists and shall not change Timeline refresh behavior.

### Requirement 3: Reload after successful fetch

**Objective:** As a Feedman user, I want 手動取得後に記事一覧が更新される, so that 取得結果が画面に反映されたことを確認できる

#### Acceptance Criteria

1. When manual fetch succeeds, the app shall reload the first page for the currently visible feed id.
2. When manual fetch succeeds, the app shall preserve the currently selected `FeedItemFilter` and request the first page with that filter.
3. When the post-fetch first-page reload succeeds, the visible list shall replace previous items with the reloaded first-page snapshot.
4. When the post-fetch first-page reload succeeds with no items, the Feed screen shall show the existing empty state for the current filter.
5. When the post-fetch first-page reload succeeds, pagination state shall reset to the returned first-page cursor and terminal state.
6. When manual fetch succeeds but the subsequent first-page reload fails, the app shall keep a recoverable user-facing failure state and shall not silently imply that visible items are current.
7. When the user changes feed or filter while refresh work is in flight, completion from the stale feed/filter session shall not replace the currently visible session.
8. The reload shall use the existing `loadFeedItemsFirstPage(feedID:filter:limit:)` repository contract rather than constructing feed-items query items in View code.

### Requirement 4: FEED_COOLDOWN guidance

**Objective:** As a Feedman user, I want クールダウン中である理由と再試行目安を知れる, so that 無駄な再試行を避けられる

#### Acceptance Criteria

1. When the manual fetch endpoint returns `429` with error code `FEED_COOLDOWN`, the app shall show retry-after guidance.
2. When `details.retry_after_seconds` is available, the guidance shall include that number of seconds or a human-readable equivalent.
3. If `details.retry_after_seconds` is unavailable but `Retry-After` header contains a valid integer number of seconds, the guidance shall include that number of seconds or a human-readable equivalent.
4. If neither retry seconds source is available, the guidance shall show a fallback message such as `しばらく待ってからもう一度お試しください。`
5. When `FEED_COOLDOWN` is shown, the app shall preserve the existing visible item list instead of clearing it.
6. When `FEED_COOLDOWN` is shown, the app shall not run the post-fetch first-page reload because the fetch request did not succeed.
7. When cooldown guidance is displayed, it shall use an existing shared toast, banner, or recoverable feedback primitive and shall not introduce a duplicate notification system.
8. The guidance shall not display raw JSON, token values, debug-only HTTP metadata, or untranslated server internals.
9. The implementation shall not add automatic retry timers or background retry scheduling in this Issue.

### Requirement 5: Non-cooldown errors

**Objective:** As a Feedman user, I want 手動更新に失敗しても一覧を失わない, so that 読んでいた記事を継続して確認できる

#### Acceptance Criteria

1. When manual fetch fails with a non-cooldown Feedman error, the app shall show a generic refresh failure message or the existing safe user-facing error presentation.
2. When manual fetch fails due to network or transport failure, the app shall show communication failure guidance.
3. When manual fetch fails due to auth-required failure, the app shall show login/session guidance consistent with existing authenticated feature behavior.
4. When manual fetch fails before post-fetch reload starts, the visible items, current filter, and pagination snapshot shall be preserved.
5. When manual fetch failure guidance is shown, retry controls may allow the user to invoke Pull-to-refresh again, but the app shall not auto-loop retries.
6. When failure is shown, technical details shall remain available only through developer diagnostics or tests, not in user-facing copy.

### Requirement 6: ViewModel state and architecture

**Objective:** As a Developer, I want 手動 fetch の状態を FeedViewModel で調停できる, so that View は endpoint や error decode の詳細を知らずに済む

#### Acceptance Criteria

1. The Feed screen ViewModel shall remain `@MainActor` or otherwise ensure UI-facing refresh state is updated on the main actor.
2. The Feed screen ViewModel shall depend on `FeedRepository` protocol, not on concrete `FeedmanFeedRepository`, `URLSession`, Keychain, or `APIClient`.
3. When refresh starts, the ViewModel shall clear stale refresh feedback from a previous refresh attempt for the same visible session.
4. When refresh finishes successfully, the ViewModel shall clear refresh-specific error feedback.
5. When refresh fails, the ViewModel shall expose refresh-specific feedback without overwriting initial-load errors unless no content is available.
6. When the feed screen has no loaded content and manual refresh is triggered, the resulting first-page reload behavior shall remain consistent with existing initial-load state handling.
7. The ViewModel shall not decode RFC3339 date strings into `Date` as part of refresh handling.
8. The ViewModel shall not mutate article read/star state as part of manual fetch handling.

### Requirement 7: Mock and previews

**Objective:** As a Developer, I want manual fetch を mock で再現できる, so that UI previews と ViewModel tests が実ネットワークなしで確認できる

#### Acceptance Criteria

1. When mock repository manual fetch succeeds, it shall record the requested `subscriptionID`.
2. When mock repository manual fetch is configured to fail with cooldown, it shall surface an error shape that ViewModel cooldown handling can inspect.
3. When mock repository manual fetch succeeds, subsequent feed item first-page loading shall use existing mock pagination behavior.
4. Preview or sample state should include a refreshable feed with `subscriptionID` so the `.refreshable` path can be exercised manually.
5. Mock data shall not contain real tokens, secrets, or personal information.

### Requirement 8: Tests and verification

**Objective:** As a QA / Developer, I want 手動 fetch と cooldown の契約を単体テストで固定できる, so that Pull-to-refresh の regressions を抑えられる

#### Acceptance Criteria

1. When the repository manual fetch method is called, tests shall verify method `POST`, path `/api/subscriptions/{id}/fetch`, Bearer auth, and no unintended request body requirement.
2. When manual fetch returns 2xx, tests shall verify the repository reports success.
3. When manual fetch returns `429 / FEED_COOLDOWN`, tests shall verify `retry_after_seconds` and `Retry-After` metadata remain inspectable from the surfaced error.
4. When Pull-to-refresh succeeds, ViewModel tests shall verify fetch is called before first-page reload.
5. When Pull-to-refresh succeeds, ViewModel tests shall verify reload uses the current feed id and current filter.
6. When Pull-to-refresh succeeds, ViewModel tests shall verify previous items are replaced by the reloaded first-page items.
7. When Pull-to-refresh receives `FEED_COOLDOWN`, ViewModel tests shall verify cooldown guidance and existing item preservation.
8. When Pull-to-refresh receives a generic error, ViewModel tests shall verify generic refresh failure feedback and existing item preservation.
9. When selected feed lacks `subscriptionID`, ViewModel or View integration tests shall verify no fetch endpoint call is issued.
10. When duplicate refresh is attempted while refresh is in progress, tests shall verify duplicate fetch requests are suppressed.
11. Unit tests shall use mock repository / mock transport and shall not depend on real network, real OAuth, real Keychain, real tokens, or personal data.
12. While macOS/Xcode is available, the implementer shall run `xcodebuild -project Feedman.xcodeproj -scheme Feedman -destination 'platform=iOS Simulator,name=iPhone 16' test` or document why it could not be run.

## 非機能要件

### NFR 1: API contract fidelity

1. The implementation shall treat `design/SPEC-iOS.md` and `design/SERVER.md` as the source of truth for endpoint path, Bearer authentication, and Feedman error format.
2. The implementation shall not infer response body fields for `POST /api/subscriptions/{id}/fetch` from prototype mock data.
3. The implementation shall preserve existing APIClient success decode, Feedman error decode, and 401 refresh retry behavior.

### NFR 2: Scope control

1. The implementation shall keep changes scoped to feed-specific manual fetch and cooldown handling.
2. The implementation shall not modify Cross-feed repository, Timeline ViewModel, or Timeline screen refresh behavior for this Issue.
3. The implementation shall not rewrite #39 feed item pagination semantics or #40 feed screen layout beyond the minimum needed to attach Pull-to-refresh and feedback.
4. The implementation shall not change `docs/specs/*` other than this Issue #41 requirements during implementation PR work.

### NFR 3: User experience

1. Refresh feedback shall be concise Japanese copy suitable for an in-app toast, banner, or recoverable message.
2. Retry-after seconds shall be presented in a way users can understand without reading API field names.
3. Refresh failure feedback shall not overlap filter controls, status banners, list content, or bottom pagination feedback.
4. Dynamic Type and VoiceOver users shall be able to perceive refresh failure or cooldown guidance through the selected shared primitive's accessibility semantics.

## 実装境界

- 主な編集対象は `Feedman/Core/FeedRepository.swift`、`Feedman/Features/Feeds/FeedViewModel.swift`、`Feedman/Features/Feeds/FeedView.swift`、および対応する `FeedmanTests` を想定する。
- Repository method 名は実装時に既存命名へ合わせてよいが、引数は subscription id を明示する。
- Fetch success response body は仕様未定義として扱い、2xx/no-content のどちらにも耐える実装境界にする。
- Cooldown message は `FeedmanErrorContext.retryAfterSeconds` を優先し、必要に応じて `retryAfter` header の整数値を fallback として使う。
- `Feed.subscriptionID` が optional である既存モデルに合わせ、nil の場合のユーザー向け失敗を ViewModel で扱う。

## 確認事項

- `POST /api/subscriptions/{id}/fetch` の成功 status code と response body は `design/SPEC-iOS.md` に明記がない。要件上は任意の 2xx を成功とし、body を要求しない。
- クールダウン guidance はトーストと inline banner のどちらでもよい。実装時は既存 `FeedmanToast` / `FeedmanBannerView` の利用箇所と Feed screen の状態管理に合わせて選ぶ。
- 手動 fetch 成功後に drawer の未読数や feed status を再取得するかは本 Issue の必須要件にしない。必要なら別 Issue で扱う。
