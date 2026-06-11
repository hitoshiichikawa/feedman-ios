# Issue #29 Drawer feed list with mock repository 要件定義

## 背景

Issue #29 は Parent: #5 の子 Issue として、Issue #28 で導入された app shell / custom drawer に、repository 形の mock data から取得したフィード一覧を表示する。
`design/SPEC-iOS.md` では v1 の採用ナビゲーションを左ドロワー + 記事ビューとしており、ドロワー内には「すべての新着」「お気に入り」、フィード一覧、アカウント導線を表示する。一方でキーワードプッシュ通知は v1 スコープ外であり、プロトタイプに UI 案があっても drawer 導線を表示しない。

Issue コメントでは、依存 `Depends on: #28, #25` が PR #71 / PR #68 として `develop` へ merge 済みであり、`codex-blocked` が除去され、`codex-auto-dev` が付与されたことが人間により確認されている。Path Overlap Checker の edit path は `Feedman/` とされている。

現行コードでは `Feedman/Core/FeedRepository.swift` に `FeedRepository.subscriptions()` と `MockFeedRepository` があり、`Feedman/Core/Models.swift` に `Feed` / `FeedStatus` が定義されている。`Feedman/Features/AppShell/RootView.swift` の drawer は route selection、未読数、停止 / エラー status 表示の骨格を持つが、フィード一覧は `AppShellPreviewData.drawerFeeds` 固定であり、repository から取得した mock subscriptions を source of truth としていない。

## スコープ

- `Feedman/Features/AppShell` を中心に、drawer のフィード一覧を `FeedRepository.subscriptions()` から取得した mock repository data で表示する。
- app shell の初期表示時または drawer 表示に必要なタイミングで subscriptions を読み込み、成功時は drawer のフィード項目を更新する。
- drawer feed row は feed title、unread count、feed status indicator を表示できるようにする。
- feed row の favicon / avatar は Issue #25 の `FeedmanFaviconView` または同等の DesignSystem component を利用できる場合は利用し、`data:` URL を `AsyncImage` に渡さない方針を維持する。
- repository から返る mock data は、将来の real subscriptions API integration に合わせた repository-shaped data として扱い、prototype 固有の JSON 形を正本にしない。
- repository loading / success / empty / error の最小 UI state を扱い、drawer が壊れず primary route navigation を継続できるようにする。
- 既存の `AppShellRoute.feed(id:title:)` と drawer selection の契約を使い、feed 選択時は stable feed identifier を route に渡す。

## 非スコープ

- Real subscriptions API integration。
- `GET /api/subscriptions` を呼ぶ real repository、APIClient endpoint、auth refresh、pagination の追加。
- 購読設定 sheet、購読解除、再開、間隔変更、手動 fetch などの subscription actions。
- フィード別記事一覧の本実装、フィルタ、警告バナー、pull-to-refresh。
- 記事詳細 sheet、既読、スター、SFSafariViewController、検索、スター一覧、アカウント処理の本実装。
- キーワードプッシュ通知 UI と drawer 導線。
- `docs/specs/*` の既存確定仕様、`design/SPEC-iOS.md`、`design/SERVER.md`、prototype files の変更。
- prototype mock data の JSON 形や `favicon_letter` / `favicon_color` のような iOS API 契約外 field の導入。

## 受入基準

### Requirement 1: Repository-shaped drawer feed loading

**Objective:** As a Feedman user, I want the drawer feed list to come from the app repository shape, so that the app shell can later switch from mock data to real subscriptions without changing drawer navigation semantics

1. When the app shell needs drawer feed entries, it shall request subscriptions through `FeedRepository.subscriptions()` rather than using `AppShellPreviewData.drawerFeeds` as the primary source of truth.
2. When `MockFeedRepository.subscriptions()` returns feeds, the drawer shall show those feed titles.
3. When a subscription has a stable `id`, selecting the feed row shall update route state to `AppShellRoute.feed(id:title:)` using that `id` and display title.
4. When repository data changes between loads, the drawer shall render from the latest loaded feed list without requiring hardcoded preview entries.
5. If the repository returns duplicate feed identifiers, the implementation shall avoid crashing and shall keep route selection deterministic for the rendered rows.

### Requirement 2: Feed unread counts

**Objective:** As a Feedman user, I want feed rows to show unread counts, so that I can choose feeds with new articles from the drawer

1. When a feed has `unreadCount` greater than zero, the drawer shall show an unread count badge for that feed.
2. When a feed has `unreadCount` equal to zero, the drawer shall not show a misleading positive unread badge.
3. When unread count is displayed, the accessibility representation shall include the unread count in Japanese.
4. When unread counts are large, the row layout shall remain stable and shall not overlap feed title, favicon / avatar, or status indicator.
5. While Dynamic Type is larger, unread count and feed title shall remain readable or truncate according to iOS conventions without breaking drawer layout.

### Requirement 3: Feed status indicators

**Objective:** As a Feedman user, I want stopped and error feeds to be distinguishable, so that I understand why a feed may not be updating

1. When a feed status is `active`, the drawer shall not show an error or stopped warning for that feed.
2. When a feed status is `stopped`, the drawer shall show a stopped indicator or label such as `停止中`.
3. When a feed status is `error`, the drawer shall show an error indicator or label such as `取得エラー`.
4. When a status includes a message, the implementation may keep the message for future UI use, but this Issue shall not require a settings sheet or recovery action.
5. When a stopped or error feed is selected, route selection shall still navigate to the feed route unless a later Issue explicitly changes that behavior.

### Requirement 4: Loading, empty, and error state

**Objective:** As a Feedman user, I want the drawer to stay usable while feed data is loading or unavailable, so that global navigation does not break

1. When subscriptions are loading, the drawer shall keep global route entries such as `すべての新着`, `お気に入り`, and `アカウント` usable.
2. When subscriptions are loading, the feed section shall show a lightweight loading state or keep an already loaded feed list until the new load completes.
3. When the repository returns an empty feed list, the feed section shall show an empty state that does not imply real API failure.
4. When `FeedRepository.subscriptions()` throws an error, the drawer shall show a recoverable or non-blocking error state for the feed section and shall not crash the app shell.
5. When subscription loading fails, existing global route selection shall continue to work.
6. If a feed-specific route references a feed that is absent from the current loaded feed list, the shell shall keep the safe fallback behavior defined by Issue #28.

### Requirement 5: Favicon / avatar handling

**Objective:** As a Feedman user, I want feed rows to use the shared favicon behavior, so that drawer visuals match later article and feed screens

1. When feed data contains a valid favicon data URL in the repository model used by the drawer, the row shall render it through the dedicated favicon component rather than `AsyncImage(url:)`.
2. When favicon source is missing, invalid, or not yet present in the domain model, the row shall render a stable letter avatar derived from the feed title.
3. When the same feed title appears across renders, the fallback avatar shall remain visually deterministic.
4. When drawer rows use avatars, the avatar dimensions shall remain stable across image and fallback states.
5. If the current `Feed` model has no favicon field, this Issue may limit the UI to title-derived avatar behavior without expanding API contracts beyond repository-shaped mock requirements.

### Requirement 6: Drawer content boundary

**Objective:** As a Product Manager, I want the drawer to expose only v1 in-scope navigation, so that prototype-only future features do not leak into this implementation

1. When the drawer renders repository-shaped mock feeds, it shall still include the primary v1 drawer entries `すべての新着`, `お気に入り`, and `アカウント`.
2. When the drawer renders v1 navigation, it shall not show keyword notification settings or keyword notification drawer entries.
3. When the user taps a feed settings affordance, this Issue shall not require any subscription settings action; the affordance may be omitted.
4. When prototype mock data conflicts with `design/SPEC-iOS.md` or `design/SERVER.md`, the implementation shall follow the canonical specs.
5. When implementing mock data, the code shall avoid treating prototype JSON or visual-only mock fields as API contracts.

### Requirement 7: Verification

**Objective:** As a Developer / QA, I want the drawer feed list behavior to be testable without real network dependencies, so that later API integration can reuse the contract

1. When unit tests are added, they shall use mock repository behavior and shall not depend on real network or Keychain.
2. When testing successful subscription loading, tests shall verify that feed titles, unread counts, and status values from the repository are preserved for drawer rendering state.
3. When testing empty subscription loading, tests shall verify that the feed section can represent an empty state without changing the current route.
4. When testing subscription loading failure, tests shall verify that global route navigation remains available and the error is surfaced as UI state.
5. When testing feed selection, tests shall verify that selecting a loaded feed passes the stable feed identifier and title into route state.
6. When Xcode test is available, the implementation shall be validated with `xcodebuild -project Feedman.xcodeproj -scheme Feedman -destination 'platform=iOS Simulator,name=iPhone 16' test`.
7. While Linux or Command Line Tools only環境で作業している, the implementer shall Xcode build/test を実行できない制約を結果報告に明記する。

## UI / 状態要件

- Drawer feed section は global route entries と独立した loading / success / empty / error state を持つ。
- Loading / error / empty state は drawer 全体を塞がず、`すべての新着`、`お気に入り`、`アカウント` の route selection を妨げない。
- Feed row は左に favicon / avatar、中央に feed title と必要に応じた status text、右に unread count badge を配置する。
- 選択中 feed row は Issue #28 の drawer selected state と整合し、視覚的にも accessibility value でも選択状態が分かるようにする。
- Status 表示は `active` では出さず、`stopped` / `error` のみ短い日本語 label で表示する。
- Drawer は light / dark appearance で `FeedmanTheme` semantic tokens または既存 DesignSystem styles を使う。
- Feed title が長い場合や Dynamic Type が大きい場合も、行内の title、status、unread badge、avatar が重ならないようにする。
- Repository load の retry UI は必須ではないが、error を握りつぶして空状態として見せない。

## Repository-shaped mock data 要件

- Drawer feed list の入力は `FeedRepository.subscriptions()` の戻り値である `Feed` または将来 real `Subscription` へ接続しやすい domain model に揃える。
- Mock repository は少なくとも active feed、unread count を持つ feed、`stopped` または `error` status を持つ feed を含む。
- Mock data の `id` は route selection 用の stable identifier として扱い、display title と混同しない。
- Mock data の unread count は UI badge 表示の入力として扱い、記事一覧の実 unread 更新や server state と同期しない。
- Mock data の status は drawer indicator の入力として扱い、再開や設定変更 action は本 Issue では呼ばない。
- Favicon が repository model に追加される場合は `feed_favicon_url` / `favicon_url` 相当の `String?` として扱い、data URL または `nil` の仕様に合わせる。
- Prototype の `favicon_letter`、`favicon_color`、Web 固有 mock field は repository-shaped mock data に持ち込まない。
- API の日付文字列や pagination contract は本 Issue の drawer feed list には不要であり、scope を広げて追加しない。

## テスト観点

- `MockFeedRepository.subscriptions()` が drawer 表示に必要な feed title、unread count、status を返すこと。
- Subscription loading success 時に drawer feed section の state が loaded feeds を保持すること。
- Empty subscriptions 時に empty state を表現し、current route と drawer open / close state を壊さないこと。
- Repository error 時に feed section error state を表現し、global route selection が継続できること。
- Feed row selection が `AppShellRoute.feed(id:title:)` に stable id と title を渡すこと。
- `stopped` / `error` status が表示用 label または indicator へ変換されること。
- `unreadCount == 0` と `unreadCount > 0` の badge 表示差分。
- Favicon / avatar fallback を使う場合、data URL を `AsyncImage` に渡さず、nil / invalid source で title-derived avatar へ fallback すること。
- Xcode が利用可能な環境では指定の `xcodebuild` test を実行すること。

## 確認事項

- 現時点で Issue #29 を実装前に追加確認すべき未決事項はない。
- `Feed` domain model に favicon field を追加するか、現行の title-derived avatar に留めるかは実装時に既存 model との整合で判断してよい。ただし `design/SPEC-iOS.md` の data URL 方針と Issue #25 の専用 component 利用方針から逸脱しないこと。
- Repository loading state を `RootView` 内に閉じるか、小さな drawer / shell ViewModel として分離するかは実装時判断でよい。ただし View が直接 `URLSession` や Keychain を触らず、repository protocol 経由にすること。
