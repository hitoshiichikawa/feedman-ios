# Issue #32 Timeline card screen UI 要件定義

## 概要

Issue #32 は Parent: #6 の子 Issue として、横断タイムライン route に prototype-style のカード型記事一覧を表示する。
対象は Timeline screen UI、ViewModel 状態、cross-feed pagination repository との接続、既存 DesignSystem controls の組み合わせである。

`design/SPEC-iOS.md` では、新着横断タイムラインの採用案を **カード** と定義し、`GET /api/items/cross-feed` から取得した記事を、フィード名 + favicon、相対日時、タイトル、概要、はてブ数、スター、外部リンクアイコンを持つカードとして表示する。既読記事は opacity 0.55 で表示する。

`design/Feedman iPhone.html` と `design/mobile/fm-ui.jsx` には `FMTimelineCard` の `cards` / `list` / `magazine` Tweak が存在するが、正本仕様で採用されているのは `timeline=cards` のみである。そのため本 Issue は `cards` 相当の SwiftUI UI を対象とし、Tweak 用の別レイアウトは実装対象にしない。

## 参照仕様

- Issue #32 本文と `gh issue view 32 --comments` の既存コメント
- `design/SPEC-iOS.md` §4.2, §4.3, §4.4, §5.0, §5.1, §5.4, §6, §8, §9, §10
- `design/SERVER.md` §1 の Bearer 認証前提。横断タイムライン UI を上書きする追加契約は見当たらない。
- `design/Feedman iPhone.html` の timeline screen / card visual と actions `openDetail` / `toggleStar` / `openLink`
- `design/mobile/fm-screens.jsx` の `FMTimelineScreen`
- `design/mobile/fm-ui.jsx` の `FMTimelineCard`、`FMFavicon`、`FMHatebu`、`FMStar`、`FMOpenLink`
- 既存 `Feedman/Features/AppShell` の route state / authenticated shell
- 既存 `Feedman/Core/FeedRepository.swift` の `loadCrossFeedFirstPage` / `loadCrossFeedNextPage`
- 既存 `Feedman/DesignSystem/ArticleMetadataControls.swift` と shared loading / empty / error primitives

## 依存判断

Issue 本文の依存は `Depends on: #26, #28, #31` である。

- #26 により、記事カード内で再利用する source row、hatebu count、star control、open-link control が利用可能である。
- #28 により、横断タイムライン route を持つ AppShell / drawer route state が利用可能である。
- #31 により、`GET /api/items/cross-feed` を cursor pagination で取得する Repository method が利用可能である。
- Issue #32 のコメントで、人間により依存 Issue はすべて develop へ merge 済みであることが確認され、`codex-blocked` 除去と `codex-auto-dev` 付与が行われている。

したがって本 Issue は #26 / #28 / #31 の成果物を前提として要件を定義する。ただし、これらの確定済み `docs/specs/*`、`design/SPEC-iOS.md`、`design/SERVER.md` は本 Issue で書き換えない。

## スコープ

- 横断タイムライン route に、`ItemSummary` の配列をカード型一覧として表示する SwiftUI screen を追加または既存 placeholder から置き換える。
- Timeline screen / ViewModel は `FeedRepository.loadCrossFeedFirstPage` と `loadCrossFeedNextPage` を利用し、初回読み込み、空状態、エラー、追加読み込み、終端表示を扱う。
- カードは #26 の DesignSystem controls を利用し、フィード source row、相対日時、タイトル、概要、はてブ数、スター、外部リンクアイコンを表示する。
- 既読状態は API / Repository から受け取った `isRead` に基づいてカード opacity を下げる。
- AppShell の `.timeline` route から Timeline screen を表示し、drawer / toolbar の route state と矛盾しないようにする。
- `data:` favicon URL は #25 / #26 の既存 component 経由で扱い、Timeline screen から `AsyncImage(url:)` へ直接渡さない。
- ViewModel tests または小さな unit tests で loading / success / empty / error / next page の主要状態を検証する。

## スコープ外

- 記事詳細 sheet の実装、`.presentationDetents`、本文 rendering、詳細取得。
- カードタップ時に詳細 sheet を開く本実装、および詳細 sheet を開いた時点の既読化。
- `PUT /api/items/{id}/state` による real read / star mutation sync。
- 既読・スターの cross-screen optimistic update、失敗時 rollback、スター一覧や検索結果との状態同期。
- SFSafariViewController presenter の新規基盤実装、および外部リンクを開いた後の real read mutation sync。
- フィード別記事一覧、スター一覧、横断検索、購読設定、フィード登録、アカウント画面の本実装。
- `GET /api/items/cross-feed`、pagination helper、APIClient、認証 refresh hook の仕様変更。
- keyword push notification UI、keyword match tag、OGP thumbnail / magazine layout、feed-scoped search UI。
- PR 作成、reviewer / project-manager 起動、commit 作成。

## 要件

### Requirement 1: Timeline route integration

**Objective:** As a Feedman user, I want `すべての新着` route で横断タイムラインのカード一覧を見られる, so that 複数フィードの新着を 1 画面で消化できる

#### Acceptance Criteria

1. When the authenticated app shell route is `.timeline`, the app shall render the Timeline screen instead of the current simple placeholder row list.
2. When the Timeline screen is shown, the navigation title shall remain `すべての新着` according to the #28 route state.
3. When the drawer opens or closes, the Timeline screen shall preserve its loaded items and pagination state unless the screen is explicitly recreated by SwiftUI lifecycle.
4. When the user navigates away from `.timeline` and returns during the same shell session, the implementation should avoid unnecessary refetch if the existing ViewModel state is still available.
5. The Timeline screen shall not introduce a second navigation source of truth separate from `AppShellState`.
6. The Timeline screen shall not expose prototype-only keyword notification routes or Tweak layout controls.

### Requirement 2: Timeline ViewModel state

**Objective:** As a Developer, I want Timeline loading state を ViewModel で扱える, so that View が Repository や APIClient の詳細を直接知らずに状態表示できる

#### Acceptance Criteria

1. The Timeline ViewModel shall be `@MainActor` or otherwise ensure UI-facing state is updated on the main actor.
2. The Timeline ViewModel shall depend on `FeedRepository` protocol, not on `URLSession`, Keychain, or concrete APIClient implementation.
3. When the Timeline ViewModel starts initial load, it shall request the first cross-feed page through `loadCrossFeedFirstPage`.
4. When first page succeeds, the ViewModel shall expose loaded `ItemSummary` values, `canLoadMore`, and any state needed for next-page UI.
5. When first page returns an empty `items` array, the ViewModel shall expose an empty state rather than an error.
6. When first page fails, the ViewModel shall expose a recoverable error state with a retry action.
7. When next-page load fails after items already exist, the ViewModel shall preserve existing items and expose a retryable additional-load error or non-destructive error feedback.
8. While a page load is already in progress, the ViewModel shall avoid issuing duplicate first-page or next-page requests for the same visible session.
9. The ViewModel shall not decode RFC3339 date strings into API models as `Date`; date formatting remains display-layer transformation from the existing `String` values.

### Requirement 3: Initial load, refresh, pagination, and terminal display

**Objective:** As a Feedman user, I want 横断タイムラインが初回読み込み、更新、追加読み込みを自然に扱う, so that 新着記事を途切れず確認できる

#### Acceptance Criteria

1. When the Timeline screen first appears with no loaded content, it shall show the shared loading state while requesting the first page.
2. When first page succeeds with items, the Timeline screen shall show the card list.
3. When first page succeeds with no items, the Timeline screen shall show the shared empty state with copy equivalent to「新着記事はありません」.
4. When first page fails, the Timeline screen shall show the shared recoverable error state and provide retry.
5. When the user performs pull-to-refresh, the Timeline screen shall start a new first-page load through the repository and replace the old session after success.
6. When pull-to-refresh fails and older items exist, the Timeline screen should keep the older visible items and present non-destructive error feedback.
7. When the user scrolls near the end and `canLoadMore` is true, the Timeline screen shall request `loadCrossFeedNextPage`.
8. When next page succeeds, the Timeline screen shall append new items after existing items without reordering them in the UI layer.
9. When `canLoadMore` is false, the Timeline screen shall render a terminal row equivalent to「最後まで読みました」.
10. When an additional page is loading, the Timeline screen shall render the shared compact loading row or an equivalent stable bottom loading indicator.
11. The Timeline screen shall rely on #31 repository pagination semantics for `since_time`, cursor, and limit handling rather than constructing cross-feed query items in View code.

### Requirement 4: Timeline card content and visual structure

**Objective:** As a Feedman user, I want 各カードで出所・内容・反応・操作を短時間で把握できる, so that 横断フィードの記事を効率よく判断できる

#### Acceptance Criteria

1. When an item is rendered, the card shall display feed source using favicon and `feedTitle`.
2. When `feedFaviconURL` is a `data:` URL or nil, the card shall rely on the existing favicon component fallback and shall not pass the value directly to `AsyncImage(url:)`.
3. When an item is rendered, the card shall display relative published time derived from `publishedAt`.
4. When `isDateEstimated` is true, the card shall communicate the estimated date state in a compact way consistent with shared date-formatting rules.
5. When an item title is long, the card shall clamp title text to at most 3 lines.
6. When an item summary is present and non-empty, the card shall display summary text clamped to at most 2 lines.
7. When an item summary is nil or empty, the card shall omit the summary area without leaving unintended blank space.
8. When hatebu metadata is available, the card shall display hatebu count using the #26 hatebu control.
9. When hatebu metadata is unavailable, the card shall use the #26 unavailable hatebu state and shall not imply zero bookmarks.
10. When an item is starred, the card shall display the filled star state using the #26 star control.
11. When an item is not starred, the card shall display the unfilled star state using the #26 star control.
12. When an item has a valid `link`, the card shall display the #26 open-link control.
13. When an item is read, the card shall reduce opacity to 0.55.
14. When an item is unread, the card shall render at normal opacity.
15. The card shall use `FeedmanTheme` tokens and existing DesignSystem controls instead of duplicating raw color palette decisions in Timeline feature code.
16. The card shall visually align with the prototype `cards` layout: surface background, border, compact rounded rectangle, source row at top, title and optional summary in the middle, metadata/actions row at bottom.

### Requirement 5: Card interactions and scope boundary

**Objective:** As a Developer, I want card actions の UI intent を後続機能へ渡せる, so that 本 Issue が詳細 sheet や real mutation sync まで広がらない

#### Acceptance Criteria

1. When the user taps the card body, the Timeline screen shall expose an item-selection intent suitable for a future article detail sheet.
2. When the card body is tapped in this Issue, the implementation shall not be required to present the article detail sheet.
3. When the card body is tapped in this Issue, the implementation shall not mark the item as read through `PUT /api/items/{id}/state`.
4. When the user activates the star control, the action shall not trigger the card body tap action.
5. When the user activates the star control, the implementation may update local preview / in-memory UI state, but shall not implement real server mutation sync or cross-screen rollback in this Issue.
6. When the user activates the open-link control, the action shall not trigger the card body tap action.
7. When the user activates the open-link control, the implementation may route an open-link intent to existing app-shell URL opening if already available, but shall not add real read mutation sync in this Issue.
8. When an item link is malformed, the Timeline screen shall disable or hide the open-link control without crashing.
9. The card shall keep star and open-link controls at stable touch-target dimensions suitable for iOS.

### Requirement 6: Accessibility and Dynamic Type

**Objective:** As a VoiceOver or Dynamic Type user, I want タイムラインカードを理解し操作できる, so that visual-only cues に依存せず記事を読める

#### Acceptance Criteria

1. When a card is focused by VoiceOver, the card shall expose enough label content to identify the feed, title, and published time.
2. When the star control is focused, it shall use the #26 accessible label and selected state semantics.
3. When the open-link control is focused, it shall use the #26 accessible label equivalent to「元記事をブラウザで開く」.
4. When hatebu count is unavailable, VoiceOver shall not announce it as zero bookmarks.
5. When Dynamic Type is larger, source title, relative date, article title, summary, and action controls shall avoid overlapping.
6. When device width is narrow, feed title and title/summary text shall truncate or wrap according to their line limits, while favicon and action controls keep stable dimensions.
7. The reduced opacity for read items shall not be the only accessibility signal if the implementation adds a read/unread accessibility value.

### Requirement 7: Tests and verification

**Objective:** As a QA / Developer, I want Timeline card screen の主要状態を検証できる, so that Repository 結合と UI state の regressions を抑えられる

#### Acceptance Criteria

1. When first page succeeds with items, tests shall verify the ViewModel exposes success state and loaded items.
2. When first page succeeds with an empty page, tests shall verify the ViewModel exposes empty state.
3. When first page fails, tests shall verify the ViewModel exposes recoverable error state and retry can request first page again.
4. When next page succeeds, tests shall verify items are appended after existing items.
5. When next page fails, tests shall verify existing items are preserved.
6. When `canLoadMore` is false, tests shall verify the ViewModel does not request another next page.
7. When card display state is derived from `ItemSummary`, tests or previews should cover unread/read opacity, starred/unstarred star state, summary present/absent, and hatebu available/unavailable.
8. Unit tests shall use mock repository data and shall not depend on real network, real OAuth, real Keychain, real tokens, or personal data.
9. While macOS/Xcode is available, the implementer shall run `xcodebuild -project Feedman.xcodeproj -scheme Feedman -destination 'platform=iOS Simulator,name=iPhone 16' test` or document why it could not be run.

## 非機能要件

### NFR 1: Architecture and compatibility

1. The implementation shall target iOS 16+ and SwiftUI.
2. The implementation shall follow MVVM + Repository and keep Timeline View code away from direct `URLSession`、Keychain、Bearer token、or query construction.
3. Timeline feature code shall live under `Feedman/Features/Timeline` where practical, with only minimal AppShell wiring under `Feedman/Features/AppShell`.
4. Shared visual components shall remain under `Feedman/DesignSystem` only if a genuinely reusable gap is discovered.
5. Swift の型名、識別子、ファイル名は English にする。

### NFR 2: Visual consistency

1. The Timeline card shall use `FeedmanTheme` semantic tokens for background, surface, border, foreground, muted foreground, accent, and star roles.
2. The Timeline screen shall avoid one-off raw palette values and one-off duplicated article metadata controls.
3. The card layout shall remain stable during star state changes, additional loading, and Dynamic Type changes.
4. The implementation shall not add OGP thumbnail, magazine layout, or keyword match badge unless a later Issue scopes those features.

### NFR 3: Scope control

1. The implementation shall remain within Issue #32 の Timeline card screen UI responsibility.
2. The implementation shall not modify `design/SPEC-iOS.md`、`design/SERVER.md`、prototype files、または他 Issue の確定済み `docs/specs/*`。
3. The implementation shall not introduce new server API contracts or treat prototype mock JSON as API contract.
4. The implementation shall not implement article detail sheet, real read/star mutation sync, or cross-screen optimistic state orchestration.
5. The implementation shall not create PRs, invoke reviewer / project-manager agents, or perform commits as part of this Stage A requirements task.

## 実装境界

- 主な編集対象は、後続実装では `Feedman/Features/Timeline`、`Feedman/Features/AppShell` の route wiring、必要に応じて `FeedmanTests` を想定する。
- `FeedRepository.loadCrossFeedFirstPage` / `loadCrossFeedNextPage` を使い、Timeline View / ViewModel は `/api/items/cross-feed` の path、`cursor`、`limit`、`since_time` query を直接構築しない。
- `ItemSummary` の `feedTitle`、`feedFaviconURL`、`title`、`summary`、`link`、`publishedAt`、`isDateEstimated`、`isRead`、`isStarred`、`hatebuCount`、`hatebuFetchedAt` を表示入力として扱う。
- `publishedAt` の相対日時 formatting は既存 helper があれば利用し、なければ Timeline UI に必要な範囲の小さな formatter として追加する。API model 自体を `Date` decode へ変更しない。
- Star / open-link controls は #26 の shared controls を使い、gesture の二重発火を防ぐ。
- Card body tap は将来の detail sheet への接続点に留め、detail sheet 本体と read mutation は本 Issue に含めない。
- Open-link action は表示導線と intent 境界を主対象とし、SFSafariViewController presenter の新規抽象化や既読化 sync が必要になった場合は別 Issue として扱う。

## テスト観点

- 初回 loading → success / empty / error の ViewModel state 遷移。
- Retry action が first page load を再実行すること。
- Pull-to-refresh が新しい first-page session として扱われること。
- next page load が既存 items へ append すること。
- next page error が既存 items を消さないこと。
- terminal state で不要な next page request を出さないこと。
- `ItemSummary.isRead` に応じて card opacity が変わること。
- `summary == nil` または空文字で summary 領域を空けないこと。
- `hatebuFetchedAt == nil` のとき hatebu unavailable 表示になり、`0` と区別されること。
- Star / open-link activation が card body tap と二重発火しないこと。
- `feedFaviconURL` が `data:` URL または nil のとき既存 favicon component 経由で fallback できること。

## 確認事項

- `publishedAt` の相対日時 formatter をどの共有層に置くかは既存実装に明確な helper が見当たらないため、実装時に `DesignSystem` / `Features/Timeline` / `Core` のどこへ置くか確認する。
- カードタップ時の本 Issue 内挙動は、detail sheet がスコープ外であるため「選択 intent の保持」または「何もしない」のどちらにするか実装前に確認する。
- 外部リンクアイコン tap で本 Issue 内に既存 `openURL` を接続してよいか、SFSafariViewController presenter Issue まで intent のみに留めるか確認する。
- Star tap で local in-memory 表示だけを切り替えるか、real sync 実装 Issue まで表示状態も変えないか確認する。
- Pull-to-refresh 失敗時の user feedback は toast と inline error のどちらを優先するか、既存 shared primitive の使い方に合わせて実装時に決める。
