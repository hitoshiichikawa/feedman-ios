# Issue #33 Timeline refresh and infinite scroll states 要件定義

## 概要

Issue #33 は Parent: #6 の子 Issue として、横断タイムラインの pull-to-refresh、last item sentinel による next page 読み込み、loading / error / end states を確定する。
対象は `Feedman/Features/Timeline` の Timeline screen / ViewModel の状態制御であり、Repository の cursor / `since_time` 契約は #31、カード表示の基本構造は #32、共有 loading / empty / error / toast/banner primitive は #27 を前提にする。

`design/SPEC-iOS.md` では、横断タイムラインは `GET /api/items/cross-feed` を使い、Pull-to-refresh は `.refreshable` による GET 再取得、無限スクロールは末尾センチネル + カーソル継ぎ足し、終端表示は「最後まで読みました」と定義されている。付録 A でも横断 Pull-to-refresh は GET 再取得のみであり、一括同期 API は設けないと確定している。

`design/SERVER.md` はトークン認証と次フェーズ通知が中心であり、Timeline refresh / infinite scroll の追加 API 契約は定義していない。そのため本 Issue は `design/SPEC-iOS.md` と #31 の `FeedRepository.loadCrossFeedFirstPage` / `loadCrossFeedNextPage` 契約を正本として扱う。

## Issue コメントの反映

`gh issue view 33 --comments` で確認できた人間コメントは Path Overlap Checker の edit path と Codex CLI 開始通知のみである。pull-to-refresh、sentinel、error 表示に関する追加決定コメントは見当たらない。

Path Overlap Checker は編集見込み path を以下としている。

- `Feedman/Features/Timeline/`
- `FeedmanTests/`

## 依存と現状確認

Issue 本文の依存は `Depends on: #27, #32` である。

- #27 により、Timeline が利用できる shared loading、empty、recoverable error、toast/banner primitive が定義されている。
- #31 により、横断タイムライン用 Repository は first page / next page、cursor、`since_time` 固定、終端判定、refresh session reset を扱う契約になっている。
- #32 により、Timeline card screen、ViewModel、カード表示、初回 loading / empty / error、pull-to-refresh、追加読み込み、終端表示の基礎が定義されている。

現状の `Feedman/Features/Timeline` には `TimelineView` と `TimelineViewModel` が存在し、`TimelineView.refreshable`、`TimelineViewModel.refresh()`、`loadNextPageIfNeeded(currentItemID:)`、bottom pagination content が実装済みである。本 Issue の要件は、これらの既存挙動を #33 の責務として明確化し、last item sentinel、重複 request 抑止、refresh / next page failure の非破壊表示、終端表示、テスト観点を固定する。

## スコープ

- 横断タイムラインの pull-to-refresh を `.refreshable` から起動し、cross-feed first page を新しい session として再取得する。
- Pull-to-refresh 成功時に Timeline items / `canLoadMore` / pagination state を refresh 後の snapshot へ置き換える。
- Pull-to-refresh 失敗時に既存 items がある場合は一覧を消さず、非破壊の error feedback を表示する。
- 初回読み込み、初回空状態、初回エラー、refresh 中、refresh エラー、next page loading、next page error、end-of-list を Timeline UI state として扱う。
- last rendered item の appear を sentinel として、`canLoadMore == true` のときだけ `loadCrossFeedNextPage` を要求する。
- next page 成功時に items を append し、next page 失敗時は既存 items と terminal state を破壊しない。
- `canLoadMore == false` のとき「最後まで読みました」に相当する終端表示を出し、追加 request を止める。
- ViewModel tests で refresh / sentinel / loading / error / end states の主要状態を検証する。

## スコープ外

- フィード別記事一覧の pull-to-refresh、および `POST /api/subscriptions/{id}/fetch` / `FEED_COOLDOWN` の扱い。
- 記事詳細 sheet、記事詳細取得、sheet 表示時の既読化。
- 外部リンク open 後の既読化、`SFSafariViewController` presenter の新規実装。
- real star / read mutation sync、楽観的更新、失敗時 rollback、スター一覧や検索結果との状態同期。
- `GET /api/items/cross-feed` の Repository / APIClient / cursor pagination helper の契約変更。
- `since_time`、`cursor`、`limit` query item の View 層での構築。
- フィード別一覧、スター一覧、横断検索、購読設定、フィード登録、アカウント画面。
- keyword push notification UI、drawer 導線、通知 deep link。
- `design/SPEC-iOS.md`、`design/SERVER.md`、prototype files、他 Issue の確定済み `docs/specs/*` の変更。
- PR 作成、reviewer / project-manager 起動、commit 作成。

## 要件

### Requirement 1: Pull-to-refresh session reset

**Objective:** As a Feedman user, I want 横断タイムラインを引っ張って更新できる, so that いま見ている一覧を明示的に最新の first page session へ更新できる

#### Acceptance Criteria

1. When the user performs pull-to-refresh on the Timeline screen, the Timeline View shall call the Timeline ViewModel refresh action from SwiftUI `.refreshable`.
2. When pull-to-refresh starts, the Timeline ViewModel shall request `FeedRepository.loadCrossFeedFirstPage` and shall not call feed-specific refresh endpoints.
3. When pull-to-refresh starts, the Timeline View / ViewModel shall not construct `/api/items/cross-feed` query items directly.
4. When pull-to-refresh succeeds, the Timeline ViewModel shall replace the current Timeline items with the refreshed first-page snapshot.
5. When pull-to-refresh succeeds, the Timeline ViewModel shall update `canLoadMore` from the refreshed snapshot.
6. When pull-to-refresh succeeds with an empty item list, the Timeline screen shall show the shared empty state equivalent to「新着記事はありません」.
7. When pull-to-refresh succeeds after a previous next-page error, the Timeline ViewModel shall clear the next-page error feedback.
8. When pull-to-refresh succeeds after a previous refresh error, the Timeline ViewModel shall clear the refresh error feedback.
9. The refresh behavior shall rely on #31 Repository session reset semantics for old `cursor` and old `since_time`.

### Requirement 2: Pull-to-refresh failure handling

**Objective:** As a Feedman user, I want 更新に失敗しても読んでいた記事一覧が消えない, so that network error が一時的でも作業文脈を失わない

#### Acceptance Criteria

1. When pull-to-refresh fails and existing Timeline items are visible, the Timeline ViewModel shall preserve the existing items.
2. When pull-to-refresh fails and existing Timeline items are visible, the Timeline screen shall remain in a loaded list state rather than switching to full-screen initial error.
3. When pull-to-refresh fails and existing Timeline items are visible, the Timeline screen shall show non-destructive feedback using a shared banner / toast or equivalent inline error surface.
4. When the refresh failure feedback includes retry, activating retry shall perform another refresh request rather than a next-page request.
5. When pull-to-refresh fails before any items have loaded, the Timeline screen shall show a recoverable initial error state with retry.
6. When the initial retry from an error state succeeds, the Timeline screen shall show the refreshed card list or empty state according to the response.
7. When pull-to-refresh is in progress, the Timeline ViewModel shall avoid starting a next-page load for the same Timeline session.
8. When another first-page load is already in progress, the Timeline ViewModel shall avoid issuing a duplicate refresh request.

### Requirement 3: Last item sentinel next page loading

**Objective:** As a Feedman user, I want 最後の表示記事までスクロールすると続きが読み込まれる, so that 横断タイムラインを手動操作なしで読み進められる

#### Acceptance Criteria

1. When the last rendered Timeline item appears and `canLoadMore` is true, the Timeline screen shall ask the ViewModel to load the next cross-feed page.
2. When a non-last Timeline item appears, the Timeline screen shall not require a next-page request solely because of that item appearance.
3. When `canLoadMore` is false, the Timeline screen shall not request `loadCrossFeedNextPage` from item appearance.
4. When a first-page load or refresh is in progress, the Timeline ViewModel shall not start a next-page load.
5. When a next-page load is already in progress, the Timeline ViewModel shall not issue a duplicate next-page request from repeated sentinel appearance.
6. When the next page request succeeds, the Timeline ViewModel shall expose the appended items in Repository snapshot order.
7. When the next page request succeeds, the Timeline screen shall keep the user's current list context and append cards below existing cards without replacing the visible list with initial loading.
8. The Timeline View / ViewModel shall call `FeedRepository.loadCrossFeedNextPage` and shall not construct `cursor` or `since_time` in Timeline feature code.
9. The sentinel behavior shall be deterministic enough for ViewModel tests by accepting the current item id or equivalent visible sentinel signal.

### Requirement 4: Additional-load loading and error states

**Objective:** As a Feedman user, I want 続きを読み込んでいる状態と失敗状態が一覧末尾で分かる, so that 初回読み込みエラーと追加読み込みエラーを区別できる

#### Acceptance Criteria

1. When a next-page load is in progress, the Timeline screen shall render a compact bottom loading row equivalent to「続きを読み込んでいます」.
2. While the compact bottom loading row is visible, already loaded cards shall remain visible.
3. When a next-page load fails, the Timeline ViewModel shall preserve already loaded items.
4. When a next-page load fails, the Timeline ViewModel shall not mark pagination as ended solely because of the failure.
5. When a next-page load fails, the Timeline screen shall show retryable additional-load feedback near the bottom of the list.
6. When additional-load retry is activated, the Timeline ViewModel shall call the next-page load path rather than resetting the whole Timeline session.
7. When additional-load retry succeeds, the Timeline ViewModel shall clear the next-page error feedback and expose the updated items.
8. When additional-load retry fails again, the Timeline screen shall keep the already loaded items and keep retryable feedback.
9. Additional-load error feedback shall not replace the full screen with the initial recoverable error view while items exist.

### Requirement 5: End-of-list state

**Objective:** As a Feedman user, I want これ以上記事がないことを一覧末尾で確認できる, so that 無限スクロールが止まった理由を理解できる

#### Acceptance Criteria

1. When the Timeline has one or more items and `canLoadMore` is false, the Timeline screen shall render a terminal row equivalent to「最後まで読みました」.
2. When the Timeline is empty, the Timeline screen shall show the empty state rather than a terminal row.
3. When the Timeline is in initial loading or initial error, the Timeline screen shall not show the terminal row.
4. When `canLoadMore` becomes false after a next-page success, the terminal row shall replace the bottom loading row.
5. When `canLoadMore` is false, repeated last item appearance shall not trigger additional next-page requests.
6. The terminal row shall use shared theme tokens and stable dimensions so it does not overlap cards or bottom safe area.
7. The terminal row shall expose an accessibility label equivalent to「最後まで読みました」.

### Requirement 6: Initial loading, empty, and recoverable error

**Objective:** As a Feedman user, I want 初回読み込みの状態が明確に表示される, so that 空・失敗・読み込み中を区別できる

#### Acceptance Criteria

1. When the Timeline first appears with no loaded content, the Timeline screen shall show the shared loading state while the first page is being requested.
2. When the first page succeeds with items, the Timeline screen shall show the card list.
3. When the first page succeeds with no items, the Timeline screen shall show the shared empty state with copy equivalent to「新着記事はありません」.
4. When the first page fails with no existing items, the Timeline screen shall show the shared recoverable error state.
5. When the recoverable error retry is activated, the Timeline ViewModel shall request the first page again.
6. When the user leaves and returns to the Timeline route in the same shell session after a successful load, the Timeline ViewModel should not refetch unless refresh or retry is explicitly requested.
7. When the user leaves and returns to the Timeline route in the same shell session after an empty result, the Timeline ViewModel should not refetch unless refresh or retry is explicitly requested.
8. The initial loading / empty / error states shall use #27 shared primitives or equivalent existing DesignSystem surfaces instead of feature-local duplicate layouts.

### Requirement 7: ViewModel state integrity and concurrency

**Objective:** As a Developer, I want Timeline ViewModel の状態遷移が重複 request に強い, so that refresh と infinite scroll が同時に起きても UI state が壊れない

#### Acceptance Criteria

1. The Timeline ViewModel shall be `@MainActor` or otherwise ensure UI-facing state changes happen on the main actor.
2. The Timeline ViewModel shall expose enough state for the View to distinguish initial loading, loaded, empty, initial error, refreshing feedback, next-page loading, next-page error, and terminal state.
3. While a first-page load is in progress, the ViewModel shall reject or ignore another first-page load for the same visible session.
4. While a first-page load is in progress, the ViewModel shall reject or ignore next-page loads.
5. While a next-page load is in progress, the ViewModel shall reject or ignore another next-page load.
6. If a next-page load fails, the ViewModel shall keep `canLoadMore` true when the previous successful snapshot indicated more pages.
7. If refresh fails while old items exist, the ViewModel shall not clear `items` or set `canLoadMore` to false solely due to that failure.
8. If refresh succeeds after local UI-only star overrides from #32, the implementation shall define deterministic behavior for those overrides and cover it with tests if retained.
9. The Timeline ViewModel shall depend on the `FeedRepository` protocol and shall not depend directly on `URLSession`、Keychain、Bearer token、or concrete `APIClient` implementation.

### Requirement 8: Tests and verification

**Objective:** As a QA / Developer, I want refresh と infinite scroll states を focused XCTest で固定できる, so that 後続の detail / mutation 実装で Timeline pagination が退行しにくい

#### Acceptance Criteria

1. When pull-to-refresh succeeds after items exist, tests shall verify the ViewModel replaces items with the refreshed first-page snapshot.
2. When pull-to-refresh succeeds with an empty page after items exist, tests shall verify the ViewModel exposes empty state and clears old items.
3. When pull-to-refresh fails after items exist, tests shall verify existing items are preserved and refresh error feedback is exposed.
4. When pull-to-refresh fails before items exist, tests shall verify the ViewModel exposes initial recoverable error state.
5. When the last item sentinel appears and `canLoadMore` is true, tests shall verify `loadCrossFeedNextPage` is requested.
6. When a non-last item appears, tests shall verify next page is not requested.
7. When `canLoadMore` is false, tests shall verify sentinel appearance does not request next page.
8. When next-page loading succeeds, tests shall verify items are appended according to the Repository snapshot.
9. When next-page loading fails, tests shall verify existing items are preserved, `canLoadMore` is not forced false, and retry feedback is exposed.
10. When next-page retry succeeds, tests shall verify the next-page error feedback is cleared.
11. When a load is already in progress, tests should verify duplicate refresh / next-page calls are ignored or otherwise deterministically handled.
12. Unit tests shall use mock repository data and shall not depend on real network, real OAuth, real Keychain, real tokens, or personal data.
13. While macOS/Xcode is available, the implementer shall run `xcodebuild -project Feedman.xcodeproj -scheme Feedman -destination 'platform=iOS Simulator,name=iPhone 16' test` or document why it could not be run.

## 非機能要件

### NFR 1: Architecture and compatibility

1. The implementation shall target iOS 16+ and SwiftUI.
2. The implementation shall follow MVVM + Repository.
3. Timeline feature code shall live under `Feedman/Features/Timeline` where practical.
4. Tests for this Issue shall live under `FeedmanTests` where practical.
5. Swift の型名、識別子、ファイル名は English にする。
6. API model の RFC3339 date strings shall remain `String`; this Issue shall not introduce automatic `Date` decoding.

### NFR 2: UX and accessibility

1. Loading, error, and terminal rows shall avoid layout overlap on narrow devices and Dynamic Type sizes.
2. Pull-to-refresh failure and next-page failure shall not rely on color alone to communicate error state.
3. Retry controls shall have iOS-appropriate touch targets and accessible labels.
4. The terminal row and loading row shall be readable with VoiceOver.
5. Refresh and pagination state changes shall avoid replacing visible cards with full-screen loading when existing items are available.

### NFR 3: Scope control

1. The implementation shall remain within Issue #33 の Timeline refresh and infinite scroll states responsibility.
2. The implementation shall not change server API contracts or add new endpoints.
3. The implementation shall not modify `design/SPEC-iOS.md`、`design/SERVER.md`、prototype files、or finalized specs for other Issues.
4. The implementation shall not implement feed-specific refresh, item detail behavior, read/star real mutation sync, or SFSafariViewController behavior.
5. The implementation shall not create PRs, invoke reviewer / project-manager agents, or perform commits as part of this Stage A requirements task.

## 実装境界

- 主な編集対象は、後続実装では `Feedman/Features/Timeline/TimelineView.swift`、`Feedman/Features/Timeline/TimelineViewModel.swift`、`FeedmanTests/TimelineViewModelTests.swift` を想定する。
- Timeline View は `FeedRepository.loadCrossFeedFirstPage` / `loadCrossFeedNextPage` を使い、`/api/items/cross-feed` path や query item を直接知らない。
- Pull-to-refresh は cross-feed の GET 再取得であり、feed-specific manual fetch ではない。
- Last item sentinel は「最後に描画されている item の appear」を基準にする。prefetch margin を導入する場合は、last item sentinel 要件を満たした上で、重複 request を出さない実装にする。
- 既存 items がある状態での refresh / next page loading は、全画面 loading ではなく既存 list 上の控えめな状態表示を優先する。
- Error message の具体文言は既存 DesignSystem / Timeline の日本語文言に合わせてよいが、初回エラー、refresh エラー、next-page エラーが区別できることを必須とする。

## 確認事項

- Issue #33 の GitHub コメントには、本文以外の追加仕様決定は見当たらない。
- 横断 Pull-to-refresh は `design/SPEC-iOS.md` 付録 A の決定事項に従い、GET 再取得のみとする。
- Feed-specific refresh と item detail behavior は Issue 本文と今回の指示に従い、明示的にスコープ外とする。
- 既存 #32 実装には refresh / infinite scroll の一部が含まれるため、後続実装では重複実装ではなく、#33 の受入基準に対する不足分の補強とテスト追加を優先する。
