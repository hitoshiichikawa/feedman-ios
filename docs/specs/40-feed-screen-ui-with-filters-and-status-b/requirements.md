# Issue #40 Feed screen UI with filters and status banner 要件定義

## 概要

Issue #40 は Parent: #8 の子 Issue として、フィード別記事一覧 route に segmented filters、標準 article card、stopped/error status banner を表示する。
対象は Feed screen UI、Feed screen ViewModel 状態、#39 のフィード別 item pagination repository との接続、#27 の shared loading / empty / error / banner primitive の利用である。

`design/SPEC-iOS.md` では、フィード別記事一覧を `GET /api/feeds/{id}/items?filter=...` で取得し、上部に `すべて` / `未読` / `スター` の filter UI を置き、フィード状態が `stopped` / `error` のとき警告バナーと「再開」導線を表示すると定義している。
ただし本 Issue は Issue 本文の制約により、manual fetch cooldown と settings mutation を含めない。したがって status banner は stopped/error の状態表示と action affordance の境界までを扱い、`POST /api/subscriptions/{id}/resume` や購読設定変更の実行は本 Issue の責務にしない。

`design/Feedman iPhone.html` と `design/mobile/fm-screens.jsx` / `design/mobile/fm-ui.jsx` には `FMFeedScreen`、`FMFilterTabs`、`FMArticleCard` の視覚例があるが、React Web の mock 実装であり、API 契約や SwiftUI 実装形の正本ではない。本 Issue では正本 API 契約は `design/SPEC-iOS.md` と #39 の repository contract を優先し、prototype は余白、階層、状態表示の参考に留める。

## 参照仕様

- Issue #40 本文と `gh issue view 40 --comments` の既存コメント
- `design/SPEC-iOS.md` §4.2, §4.3, §4.4, §5.0, §5.2, §5.4, §5.6, §6, §9, §10
- `design/SERVER.md` §1 の Bearer 認証と error response 形式。Feed screen UI を上書きする追加契約は見当たらない。
- `design/Feedman iPhone.html` の feed screen visual
- `design/mobile/fm-screens.jsx` の `FMFeedScreen` / `FMFilterTabs`
- `design/mobile/fm-ui.jsx` の `FMArticleCard`、`FMFavicon`、`FMHatebu`、`FMStar`、`FMOpenLink`
- #27 `docs/specs/27-reusable-loading-empty-error-toast-and-s/requirements.md` と実装済み `FeedmanLoadingView`、`FeedmanEmptyStateView`、`FeedmanRecoverableErrorView`、`FeedmanBannerView`、`FeedmanCompactLoadingRow`
- #39 `docs/specs/39-feed-item-list-repository-with-filters-a/requirements.md` と実装済み `FeedItemFilter`、`FeedItemPaginationSnapshot`、`FeedRepository.loadFeedItemsFirstPage`、`FeedRepository.loadFeedItemsNextPage`
- 既存 `Feedman/Core/Models.swift` の `Feed` / `FeedStatus`
- 既存 Timeline screen の card / loading / empty / error / pagination 表示パターン

## 依存判断

Issue 本文の依存は `Depends on: #27, #39` である。

- #27 により、Feed screen が使う loading、empty、recoverable error、inline banner、compact loading row が利用可能である。
- #39 により、`FeedItemFilter.all` / `.unread` / `.starred` と `GET /api/feeds/{id}/items` の first page / next page repository boundary が利用可能である。
- Issue #40 のコメントでは、依存先 #27 / #39 は staged-for-release となり、`codex-blocked` が自動解除されたことが確認できる。

したがって本 Issue は #27 / #39 の成果物を前提として要件を定義する。ただし、これらの確定済み `docs/specs/*`、`design/SPEC-iOS.md`、`design/SERVER.md` は本 Issue で書き換えない。

## スコープ

- 選択中の feed route に、フィード別記事一覧 SwiftUI screen を追加または既存 placeholder から置き換える。
- Feed screen / ViewModel は `FeedRepository.loadFeedItemsFirstPage(feedID:filter:limit:)` と `loadFeedItemsNextPage()` を利用し、初回読み込み、filter 切替、空状態、エラー、追加読み込み、終端表示を扱う。
- Filter UI は `すべて` / `未読` / `スター` を `FeedItemFilter.all` / `.unread` / `.starred` に対応させ、選択状態を明示する。
- Feed screen は選択中 feed の `FeedStatus.stopped` / `.error` に応じて、上部に status banner を表示する。
- Status banner は状態 message と action affordance を表示できる。ただし action は後続の settings/resume flow へ渡せる intent に留め、mutation 実行を本 Issue の必須要件にしない。
- Article card はフィード別標準カードとして、タイトル、概要、相対日時、はてブ数、スター、外部リンクアイコン、既読 opacity を表示する。
- `data:` favicon URL は既存 favicon component 経由で扱い、Feed screen から `AsyncImage(url:)` へ直接渡さない。
- ViewModel tests または小さな unit tests で loading / success / empty / error / filter change / next page の主要状態を検証する。

## スコープ外

- Manual fetch、Pull-to-refresh の `POST /api/subscriptions/{id}/fetch` 実行、`FEED_COOLDOWN` / `retry_after_seconds` 表示。
- `POST /api/subscriptions/{id}/resume` の real mutation、購読設定 sheet の表示、fetch interval 変更、購読解除。
- 記事詳細 sheet、詳細取得、`.presentationDetents`、本文 rendering、詳細表示時の既読化。
- `PUT /api/items/{id}/state` による real read / star mutation sync、cross-screen optimistic update、失敗時 rollback。
- SFSafariViewController presenter の新規基盤実装、および外部リンクを開いた後の real read mutation sync。
- スター一覧、横断検索、フィード登録、アカウント画面、keyword push notification UI、feed-scoped search UI。
- `GET /api/feeds/{id}/items` の API contract、#39 repository pagination semantics、APIClient、認証 refresh hook の仕様変更。
- `design/SPEC-iOS.md`、`design/SERVER.md`、prototype files、確定済み `docs/specs/*` の変更。
- PR 作成、reviewer / project-manager 起動。

## 要件

### Requirement 1: Feed route integration

**Objective:** As a Feedman user, I want 選択したフィードの一覧画面を見られる, so that そのフィードの記事だけを確認できる

#### Acceptance Criteria

1. When the authenticated app shell route represents a selected feed, the app shall render the Feed screen for that feed instead of a placeholder.
2. When the Feed screen is shown, the navigation title shall use the selected feed title already held by route or drawer state.
3. When the selected feed changes, the Feed screen shall load a new first page for the new feed id and shall not show stale items from the previous feed as loaded success.
4. When the user navigates away from a feed and returns during the same shell session, the implementation should avoid unnecessary refetch if the existing ViewModel state still matches the same feed id and filter.
5. The Feed screen shall not introduce a second navigation source of truth separate from the existing AppShell route state.
6. The Feed screen shall not expose keyword notification routes, prototype Tweak controls, or feed-scoped search UI.

### Requirement 2: Filter control and repository reload

**Objective:** As a Feedman user, I want `すべて` / `未読` / `スター` を切り替えられる, so that 表示する記事を目的に合わせて絞り込める

#### Acceptance Criteria

1. When the Feed screen renders filters, it shall show exactly three user-facing options: `すべて`、`未読`、`スター`。
2. When `すべて` is selected, the ViewModel shall request first page with `FeedItemFilter.all`.
3. When `未読` is selected, the ViewModel shall request first page with `FeedItemFilter.unread`.
4. When `スター` is selected, the ViewModel shall request first page with `FeedItemFilter.starred`.
5. When filter tab changes, visible list shall reload for selected filter.
6. When filter tab changes, the Feed screen shall reset first-page UI state for the selected feed/filter session and shall not append previous filter items.
7. When the same filter is selected again, the ViewModel should avoid issuing a duplicate first-page request unless the implementation explicitly treats it as retry or refresh.
8. The filter control shall expose selected state to accessibility users and shall keep stable dimensions when labels or Dynamic Type size change.
9. The filter control shall use SwiftUI `Picker` segmented style or a custom chip/segmented control consistent with `FeedmanTheme`; it shall not depend on prototype-only DOM styling.

### Requirement 3: Feed item ViewModel state

**Objective:** As a Developer, I want Feed item loading state を ViewModel で扱える, so that View が Repository や APIClient の詳細を直接知らずに状態表示できる

#### Acceptance Criteria

1. The Feed screen ViewModel shall be `@MainActor` or otherwise ensure UI-facing state is updated on the main actor.
2. The Feed screen ViewModel shall depend on `FeedRepository` protocol, not on `URLSession`, Keychain, Bearer token, or concrete APIClient implementation.
3. When the Feed screen starts initial load, it shall request `loadFeedItemsFirstPage(feedID:filter:limit:)`.
4. When first page succeeds, the ViewModel shall expose loaded `ItemSummary` values, `canLoadMore`, current `feedID`, current `filter`, and any state needed for next-page UI.
5. When first page returns an empty `items` array, the ViewModel shall expose an empty state rather than an error.
6. When first page fails, the ViewModel shall expose a recoverable error state with a retry action.
7. When next-page load fails after items already exist, the ViewModel shall preserve existing items and expose a retryable additional-load error or non-destructive error feedback.
8. While a page load is already in progress, the ViewModel shall avoid issuing duplicate first-page or next-page requests for the same visible session.
9. When an error is shown to the user, debug details, token values, and raw transport internals shall not be displayed.
10. The ViewModel shall not decode RFC3339 date strings into API models as `Date`; date formatting remains display-layer transformation from existing `String` values.

### Requirement 4: Initial load, empty, error, pagination, and terminal display

**Objective:** As a Feedman user, I want フィード別一覧が読み込み、空状態、失敗、追加読み込みを自然に扱う, so that 記事一覧を途切れず確認できる

#### Acceptance Criteria

1. When the Feed screen first appears with no loaded content, it shall show the shared loading state while requesting the first page.
2. When first page succeeds with items, the Feed screen shall show the item card list.
3. When first page succeeds with no items for the selected filter, empty state shall render.
4. When the selected filter has no items, the empty state copy shall make the filter context understandable, for example `記事がありません` with supporting copy that suggests changing filter.
5. When first page fails, the Feed screen shall show the shared recoverable error state and provide retry.
6. When retry is activated after initial failure, the ViewModel shall request the first page again for the current feed id and filter.
7. When the user scrolls near the end and `canLoadMore` is true, the Feed screen shall request `loadFeedItemsNextPage()`.
8. When next page succeeds, the Feed screen shall append new items after existing items without reordering them in the UI layer.
9. When an additional page is loading, the Feed screen shall render the shared compact loading row or an equivalent stable bottom loading indicator.
10. When next page fails, the Feed screen shall keep existing items visible and show retryable non-destructive feedback.
11. When `canLoadMore` is false and items are not empty, the Feed screen shall render a terminal row equivalent to `最後まで読みました`.
12. The Feed screen shall rely on #39 repository pagination semantics for cursor, limit, filter query, and terminal handling rather than constructing feed-items query items in View code.

### Requirement 5: Stopped/error status banner

**Objective:** As a Feedman user, I want 停止中または取得エラーのフィード状態を一覧上部で分かる, so that 記事一覧の状態を誤解しない

#### Acceptance Criteria

1. When feed status is `active`, the Feed screen shall not show a stopped/error status banner.
2. When feed is stopped/error, banner shall show message and action affordance.
3. When feed status is `stopped`, the banner shall use warning-style visual emphasis and a short Japanese message derived from `FeedStatus.stopped(message:)`.
4. When feed status is `error`, the banner shall use error/warning-style visual emphasis and a short Japanese message derived from `FeedStatus.error(message:)`.
5. If the stopped/error message is blank or unavailable, the banner shall show a safe fallback such as `フィードの取得が停止しています` or `フィードの取得に失敗しています` rather than an empty banner.
6. When the banner action affordance is rendered, it shall be labeled `再開` or an equivalent short Japanese action label.
7. When the banner action affordance is activated in this Issue, the implementation shall emit an intent suitable for a later settings/resume flow and shall not be required to call `POST /api/subscriptions/{id}/resume`.
8. The banner shall use #27 `FeedmanBannerView` or an equivalent shared primitive and shall not duplicate endpoint-specific mutation behavior in the View.
9. The banner shall remain above the filter control or otherwise be visible before the list content so users see the feed status before interacting with article cards.
10. When banner text is long, it shall wrap without overlapping the action affordance, filter control, or list content.

### Requirement 6: Feed item card content and visual structure

**Objective:** As a Feedman user, I want フィード内の記事カードで内容と操作を短時間で把握できる, so that 記事を効率よく選べる

#### Acceptance Criteria

1. When an item is rendered, the card shall display the item title.
2. When item title is long, the card shall clamp title text to at most 2 lines for the standard feed-list card.
3. When item summary is present and non-empty, the card shall display summary text clamped to at most 2 lines.
4. When item summary is nil or empty, the card shall omit the summary area without leaving unintended blank space.
5. When an item is rendered, the card shall display relative published time derived from `publishedAt`.
6. When `isDateEstimated` is true, the card shall communicate the estimated date state in a compact way consistent with shared date-formatting rules.
7. When hatebu metadata is available, the card shall display hatebu count using the #26 hatebu control if available.
8. When hatebu metadata is unavailable, the card shall use the #26 unavailable hatebu state or equivalent and shall not imply zero bookmarks.
9. When an item is starred, the card shall display the filled star state using the existing star control.
10. When an item is not starred, the card shall display the unfilled star state using the existing star control.
11. When an item has a valid `link`, the card shall display the existing open-link control.
12. When an item link is malformed, the Feed screen shall disable or hide the open-link control without crashing.
13. When an item is read, the card shall reduce opacity to 0.55.
14. When an item is unread, the card shall render at normal opacity.
15. The card shall use `FeedmanTheme` tokens and existing DesignSystem controls instead of duplicating raw color palette decisions in Feed feature code.
16. The card shall visually align with the prototype standard feed-list layout: compact surface row/card, title and optional summary in the main area, metadata/actions row at bottom, stable star and open-link controls.

### Requirement 7: Card interactions and scope boundary

**Objective:** As a Developer, I want article card actions の UI intent を後続機能へ渡せる, so that 本 Issue が詳細 sheet や real mutation sync まで広がらない

#### Acceptance Criteria

1. When the user taps the card body, the Feed screen shall expose an item-selection intent suitable for a future article detail sheet.
2. When the card body is tapped in this Issue, the implementation shall not be required to present the article detail sheet.
3. When the card body is tapped in this Issue, the implementation shall not mark the item as read through `PUT /api/items/{id}/state`.
4. When the user activates the star control, the action shall not trigger the card body tap action.
5. When the user activates the star control, the implementation may update local preview / in-memory UI state, but shall not implement real server mutation sync or cross-screen rollback in this Issue.
6. When the user activates the open-link control, the action shall not trigger the card body tap action.
7. When the user activates the open-link control, the implementation may route an open-link intent to existing app-shell URL opening if already available, but shall not add real read mutation sync in this Issue.
8. The card shall keep star and open-link controls at stable touch-target dimensions suitable for iOS.

### Requirement 8: Accessibility and Dynamic Type

**Objective:** As a VoiceOver or Dynamic Type user, I want フィード別一覧を理解し操作できる, so that visual-only cues に依存せず記事を読める

#### Acceptance Criteria

1. When the filter control is focused by VoiceOver, it shall communicate the filter label and selected state.
2. When the status banner is focused by VoiceOver, it shall communicate the stopped/error message and the action affordance if present.
3. When a card is focused by VoiceOver, the card shall expose enough label content to identify the title and published time.
4. When the star control is focused, it shall expose accessible label and selected state semantics.
5. When the open-link control is focused, it shall expose an accessible label equivalent to `元記事をブラウザで開く`.
6. When hatebu count is unavailable, VoiceOver shall not announce it as zero bookmarks.
7. When Dynamic Type is larger, filter labels, banner message/action, article title, summary, metadata, and action controls shall avoid overlapping.
8. When device width is narrow, title/summary text shall truncate or wrap according to their line limits, while action controls keep stable dimensions.
9. The reduced opacity for read items shall not be the only accessibility signal if the implementation adds a read/unread accessibility value.

### Requirement 9: Tests and verification

**Objective:** As a QA / Developer, I want Feed screen の主要状態を検証できる, so that filter と status banner の regressions を抑えられる

#### Acceptance Criteria

1. When first page succeeds with items, tests shall verify the ViewModel exposes success state and loaded items for the selected feed/filter.
2. When first page succeeds with an empty page, tests shall verify the ViewModel exposes empty state.
3. When first page fails, tests shall verify the ViewModel exposes recoverable error state and retry can request first page again.
4. When filter changes, tests shall verify the ViewModel requests the new filter and replaces visible items rather than appending previous filter items.
5. When selected feed changes, tests shall verify the ViewModel starts a new feed-specific first-page session.
6. When next page succeeds, tests shall verify items are appended after existing items.
7. When next page fails, tests shall verify existing items are preserved and a non-destructive error is exposed.
8. When `canLoadMore` is false, tests shall verify the ViewModel does not request another next page.
9. When feed status is `active`, tests or previews should cover that no status banner is rendered.
10. When feed status is `stopped` or `error`, tests or previews should cover banner message and action affordance.
11. When card display state is derived from `ItemSummary`, tests or previews should cover unread/read opacity, starred/unstarred star state, summary present/absent, and hatebu available/unavailable.
12. Unit tests shall use mock repository data and shall not depend on real network, real OAuth, real Keychain, real tokens, or personal data.
13. While macOS/Xcode is available, the implementer shall run `xcodebuild -project Feedman.xcodeproj -scheme Feedman -destination 'platform=iOS Simulator,name=iPhone 16' test` or document why it could not be run.

## 非機能要件

### NFR 1: Architecture and compatibility

1. The implementation shall target iOS 16+ and SwiftUI.
2. The implementation shall follow MVVM + Repository and keep Feed screen View code away from direct `URLSession`、Keychain、Bearer token、or query construction.
3. Feed screen feature code shall live under `Feedman/Features/Feeds` or the existing feed feature directory chosen by the codebase, with only minimal AppShell wiring under `Feedman/Features/AppShell`.
4. Shared visual components shall remain under `Feedman/DesignSystem` only if a genuinely reusable gap is discovered.
5. Swift の型名、識別子、ファイル名は English にする。

### NFR 2: Visual consistency

1. The Feed screen shall use `FeedmanTheme` semantic tokens for background, surface, border, foreground, muted foreground, accent, danger/warning, and star roles.
2. The Feed screen shall avoid one-off raw palette values and one-off duplicated article metadata controls.
3. Filter control, status banner, item cards, additional loading row, and terminal row shall maintain stable layout during filter changes, star state changes, additional loading, and Dynamic Type changes.
4. The implementation shall not add OGP thumbnail, magazine layout, keyword match badge, or prototype Tweak alternatives unless a later Issue scopes those features.

### NFR 3: Scope control

1. The implementation shall remain within Issue #40 の Feed screen UI with filters and status banner responsibility.
2. The implementation shall not modify `design/SPEC-iOS.md`、`design/SERVER.md`、prototype files、または他 Issue の確定済み `docs/specs/*`。
3. The implementation shall not introduce new server API contracts or treat prototype mock JSON as API contract.
4. The implementation shall not implement manual fetch cooldown, settings mutation, resume mutation, article detail sheet, real read/star mutation sync, or cross-screen optimistic state orchestration.
5. The implementation shall not create PRs, invoke reviewer / project-manager agents, or perform commits as part of this Stage A requirements task.

## 実装境界

- 主な編集対象は、後続実装では `Feedman/Features/Feeds` または既存命名に沿う Feed feature directory、`Feedman/Features/AppShell` の route wiring、必要に応じて `FeedmanTests` を想定する。
- `FeedRepository.loadFeedItemsFirstPage(feedID:filter:limit:)` / `loadFeedItemsNextPage()` を使い、Feed View / ViewModel は `/api/feeds/{id}/items` の path、`filter`、`cursor`、`limit` query を直接構築しない。
- Filter values は #39 の `FeedItemFilter` を使い、View / ViewModel call site で free-form string を使わない。
- Feed status banner は `FeedStatus.active` / `.stopped(message:)` / `.error(message:)` を表示入力として扱う。`Subscription.id` が必要な resume/settings mutation は本 Issue では要求しない。
- `ItemSummary` の `title`、`summary`、`link`、`publishedAt`、`isDateEstimated`、`isRead`、`isStarred`、`hatebuCount`、`hatebuFetchedAt` を表示入力として扱う。フィード別一覧なので card 上で feed source row を必須表示にはしない。
- `publishedAt` の相対日時 formatting は既存 helper があれば利用し、なければ Feed UI に必要な範囲の小さな formatter として追加する。API model 自体を `Date` decode へ変更しない。
- Star / open-link controls は既存 shared controls を使い、gesture の二重発火を防ぐ。
- Card body tap は将来の detail sheet への接続点に留め、detail sheet 本体と read mutation は本 Issue に含めない。
- Open-link action は表示導線と intent 境界を主対象とし、SFSafariViewController presenter の新規抽象化や既読化 sync が必要になった場合は別 Issue として扱う。

## テスト観点

- 初回 loading → success / empty / error の ViewModel state 遷移。
- Retry action が current feed id / filter の first page load を再実行すること。
- Filter change が new first-page session として扱われ、旧 filter items を append しないこと。
- Selected feed change が new feed-specific first-page session として扱われること。
- next page load が既存 items へ append すること。
- next page error が既存 items を消さないこと。
- terminal state で不要な next page request を出さないこと。
- `FeedStatus.active` では banner が出ず、`.stopped` / `.error` では message と action affordance が出ること。
- `ItemSummary.isRead` に応じて card opacity が変わること。
- `summary == nil` または空文字で summary 領域を空けないこと。
- `hatebuFetchedAt == nil` のとき hatebu unavailable 表示になり、`0` と区別されること。
- Star / open-link activation が card body tap と二重発火しないこと。
- Filter / banner / card が Dynamic Type と narrow width で重ならないこと。

## 確認事項

- Status banner の action affordance は本 Issue では intent 境界に留める。実装時に既存 AppShell/Settings flow が利用可能であっても、`POST /api/subscriptions/{id}/resume` や settings mutation を本 Issue に広げない。
- Feed route が保持する feed state が `FeedStatus` だけで足りるか、banner action intent のために subscription id も必要かは未確定。ただし mutation 実行は本 Issue のスコープ外である。
- Card tap 時の本 Issue 内挙動は、detail sheet がスコープ外であるため「選択 intent の保持」または「何もしない」のどちらにするか実装前に確認する。
- 外部リンクアイコン tap で本 Issue 内に既存 URL opening を接続してよいか、SFSafariViewController presenter Issue まで intent のみに留めるか確認する。
- Star tap で local in-memory 表示だけを切り替えるか、real sync 実装 Issue まで表示状態も変えないか確認する。
- Feed-specific Pull-to-refresh と cooldown 表示は `design/SPEC-iOS.md` §5.2 / §10 にあるが、Issue #40 本文のスコープ外指定に従い本 requirements から除外した。
