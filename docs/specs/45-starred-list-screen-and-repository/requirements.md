# Issue #45 Starred list screen and repository 要件定義

## 概要

Issue #45 は Parent: #10 の子 Issue として、スター済み記事一覧を `GET /api/feeds/starred/items` から取得し、共有 article card で表示する責務を扱う。

Issue 本文のゴールは「Starred items load from `/api/feeds/starred/items` and render with shared article cards.」である。受入候補として、スター画面を開いたときの fetch、unstar 時の一覧更新、空状態表示が提示されている。

`gh issue view 45 --comments` では、依存 Issue #23 / #26 / #37 がすべて `staged-for-release` として解消済みになり、`codex-blocked` が自動解除されたことが owner コメントで確認できた。追加の人間回答による画面仕様変更はない。

## 参照仕様

- Issue #45 本文と `gh issue view 45 --comments` の既存コメント。
- `design/SPEC-iOS.md` §4.2, §4.3, §4.4, §5.0, §5.3, §5.4, §6, §10。
- `design/SERVER.md` §1 の Bearer 認証前提と既存 API 後方互換要件。
- `design/Feedman iPhone.html` の starred route、header title「お気に入り」、API メモ `GET /api/feeds/starred/items`。
- `docs/specs/23-apiclient-401-refresh-retry-hook/requirements.md`。
- `docs/specs/26-shared-article-metadata-controls/requirements.md`。
- `docs/specs/37-optimistic-read-and-star-state-synchroni/requirements.md`。

## 依存判断

Issue 本文の依存は `Depends on: #23, #26, #37` である。

- #23 は PR #75 が develop へ merge 済みで、`codex-staged-for-release` として main 到達待ちである。これにより認証付き `APIClient` と 401 refresh retry hook を利用可能な前提でよい。
- #26 は PR #70 が develop へ merge 済みで、`codex-staged-for-release` として main 到達待ちである。これにより shared star、source row、hatebu、open-link controls を利用可能な前提でよい。
- #37 は Issue #45 コメントで `staged-for-release` と明記され、自動依存解除済みである。これにより read / star の in-memory optimistic synchronization と rollback 境界を利用可能な前提でよい。
- したがって、Issue #45 は develop 上では実装に進める状態と判断する。ただし production release として main 到達済みではないため、release notes / main 到達確認は別運用の残留事項である。

## 正本仕様

- `design/SPEC-iOS.md` はスター一覧を v1 スコープに含め、`GET /api/feeds/starred/items` をスター済み記事一覧 endpoint として定義している。
- スター一覧は複数フィードを横断するため、カードには `feed_title` を用いてソースを表示する。
- 一覧 API のページネーションは `{ items, next_cursor: string?, has_more }` であり、次ページは `cursor=<next_cursor>&limit=<n>` を送る。`has_more == false`、または `next_cursor` が `null` / 空文字の場合は終端とする。
- 認証必須 API は Bearer token を付与し、401 refresh / retry は shared `APIClient` に委譲する。
- 日付文字列は RFC3339 `String` として保持し、Repository 層で `Date` へ自動変換しない。
- Favicon の `data:` URL は `AsyncImage(url:)` に直接渡さず、既存の専用 favicon component / fallback を利用する。
- `design/SERVER.md` には `/api/feeds/starred/items` を上書きする追加契約は見当たらないため、本 Issue の API 契約は `design/SPEC-iOS.md` を正本とする。

## スコープ

- `Feedman/Core` に、スター済み記事一覧を取得する Repository protocol / real implementation / mock implementation を追加または既存 Repository 境界へ統合する。
- `GET /api/feeds/starred/items` を shared `APIClient` 経由で呼び、Bearer token と 401 refresh retry は #23 の既存挙動へ委譲する。
- response `items` はスター一覧で使う記事 summary として decode し、API order のまま表示する。
- 初回 page / refresh / next page の loading、success、empty、error、terminal state を ViewModel で扱う。
- AppShell の drawer「お気に入り」導線または既存 starred route を、placeholder からスター一覧 screen へ接続する。
- #26 の shared article metadata controls を使い、source row、star、open-link control を共有 article card として表示する。
- #37 の optimistic synchronization 境界を使い、スター解除時はスター一覧から当該記事を削除するか、現在の一覧 policy と一貫する表示更新を行う。
- 記事カード tap は既存 article detail flow へ委譲し、open-link control は既存 external article opening boundary へ委譲する。
- Repository / ViewModel / UI の focused XCTest coverage を定義する。

## スコープ外

- Global search implementation、`GET /api/items/search`、検索 screen、検索 result bridge。
- Feed-scoped search UI。
- キーワードプッシュ通知 UI、notification keyword 管理、drawer 導線。
- `/api/feeds/starred/items` 以外の新規 server API、server contract 変更。
- `design/SPEC-iOS.md`、`design/SERVER.md`、prototype files、他 Issue の確定済み `docs/specs/*` の変更。
- Shared article controls 自体の仕様変更。
- #37 の optimistic synchronization 境界自体の再設計。
- SFSafariViewController presenter、ArticleDetail sheet、ItemRepository state mutation API の新規実装。ただし既存境界への接続は含む。
- 実ネットワーク、実 OAuth、実 Keychain に依存する integration test。
- PR 作成、reviewer / project-manager サブエージェント起動、コミット。

## API 契約

- Endpoint: `GET /api/feeds/starred/items`
- 認証: v1 の認証必須 API として、`Authorization: Bearer <access_token>` を shared `APIClient` 契約に従って付与する。
- Query:
  - 初回 load / refresh は `limit=<n>` を送り、`cursor` は送らない。
  - next page は `cursor=<next_cursor>` と同じ `limit=<n>` を送る。
  - default page size は 50 とし、上限は一覧 API 共通の 200 を超えない。
- Response:
  - `{ items, next_cursor, has_more }` の cursor pagination response として扱う。
  - `items` は API order のまま表示し、Repository で独自に並び替えない。
  - `feed_title` を source row 表示に使う。favicon は `feed_favicon_url` / `favicon_url` 相当の既存 model field を利用し、`nil` / `data:` URL / invalid value に耐える。
  - `published_at` などの日付文字列は `String` のまま保持し、表示層で整形する。
- Error:
  - transport / decode / server error / auth-required error は typed error として ViewModel へ伝播し、成功した空一覧と区別する。
  - 401 refresh retry の詳細は endpoint-specific に再実装しない。

## 要件

### Requirement 1: Starred repository contract

**Objective:** As a Feedman user, I want スター済み記事を Repository 経由で取得できる, so that View が APIClient、Bearer token、pagination の詳細を知らずに一覧を表示できる

#### Acceptance Criteria

1. When the starred screen needs its first page, the repository shall call `GET /api/feeds/starred/items`.
2. When the repository returns a starred page, it shall expose accumulated article items, `nextCursor`, `canLoadMore`, and `limit`.
3. The repository shall keep View code isolated from `URLSession`, Keychain, Bearer token headers, and refresh retry details.
4. The repository shall use shared API model decoding and shall not treat prototype mock data shape as API contract.
5. The mock repository shall provide deterministic success、empty、paginated、transport error、auth error states.

### Requirement 2: Request construction and auth

**Objective:** As a Developer, I want スター一覧 request が既存 APIClient 契約に従う, so that 認証や retry の実装が endpoint ごとに重複しない

#### Acceptance Criteria

1. When first page is requested, the repository shall send method `GET` and path `/api/feeds/starred/items`.
2. When first page is requested, the repository shall include normalized `limit` and shall not include `cursor`.
3. When next page is requested, the repository shall include stored `cursor` and the same normalized `limit`.
4. When the request is sent, the repository shall use the shared authenticated `APIClient` behavior from #23.
5. When the APIClient refreshes an expired access token and retries successfully, the starred repository shall return decoded results without endpoint-specific retry logic.
6. When auth refresh fails, the repository shall surface the typed auth-required error and shall not display it as an empty starred list.
7. The repository shall not log access tokens, refresh tokens, `Authorization` header values, or private article content.

### Requirement 3: Cursor pagination and refresh

**Objective:** As a Feedman user, I want スター一覧を必要に応じて追加読み込みできる, so that 保存済み記事が多くても段階的に閲覧できる

#### Acceptance Criteria

1. When first page succeeds, the ViewModel shall replace current starred items with response `items`.
2. When refresh succeeds, the ViewModel shall replace current starred items with refreshed first page results and reset pagination state.
3. When next page succeeds, the ViewModel shall append response `items` after existing items.
4. When `has_more` is false, the ViewModel shall report that no more pages can be loaded.
5. When `next_cursor` is null or empty, the ViewModel shall report that no more pages can be loaded.
6. When next page is requested before a successful first page, the ViewModel or repository shall fail fast without issuing an invalid network request.
7. When next page fails, the ViewModel shall preserve previously loaded items and expose a retryable error for the next-page operation.
8. When pagination reaches terminal state, the screen may show the shared terminal affordance equivalent to「最後まで読みました」without issuing additional requests.

### Requirement 4: Starred screen states

**Objective:** As a Feedman user, I want お気に入り画面の loading / empty / error / content が区別される, so that 状態に応じて次の行動を取りやすい

#### Acceptance Criteria

1. When the starred route opens, the screen shall start loading the first starred page unless a valid current snapshot is intentionally reused.
2. When first-page loading is in progress and no items are visible, the screen shall show the shared loading state.
3. When first-page loading succeeds with one or more items, the screen shall render article cards in API order.
4. When first-page loading succeeds with zero items, the screen shall show the shared empty state for starred articles.
5. When first-page loading fails, the screen shall show the shared error state with a retry action.
6. When retry is activated from the first-page error state, the screen shall retry the first page request.
7. When a refresh is in progress over existing items, the screen shall keep existing items visible where practical and update them after success.
8. When auth-required error is surfaced, the screen shall use the app's existing auth-required handling boundary rather than showing stale success as current.

### Requirement 5: Shared article card rendering

**Objective:** As a Feedman user, I want スター一覧の記事カードが他の一覧と同じ見た目で表示される, so that Feedman の記事操作が一貫する

#### Acceptance Criteria

1. When a starred item is rendered, the card shall use #26 shared article metadata controls where practical.
2. When source metadata is available, the card shall show source row with feed title and favicon because starred list is cross-feed.
3. When feed title is long, the source row shall truncate without overlapping date, title, controls, or favicon.
4. When favicon is null, invalid, or a `data:` URL, the card shall use existing favicon fallback/decode behavior and shall not pass `data:` URL directly to `AsyncImage(url:)`.
5. When title, summary, or source metadata is long, the card shall preserve stable layout at supported narrow widths and Dynamic Type sizes.
6. When an item is read, the card shall reflect the existing read visual behavior from shared card / state synchronization without adding a new read policy.
7. When hatebu metadata is unavailable, the card shall use the shared neutral unavailable state rather than inventing a count.

### Requirement 6: Star toggle and removal policy

**Objective:** As a Feedman user, I want スター一覧でスター解除した記事が一覧と整合する, so that お気に入り画面がスター済みだけを表す

#### Acceptance Criteria

1. When the user toggles star off from a starred list card, the app shall route the mutation through the existing item state / optimistic synchronization boundary from #37.
2. When an item is successfully unstarred, the starred list shall remove that item from the visible list or update it according to one explicit screen policy.
3. The preferred screen policy for this Issue is removal from the starred list after the unstar action is confirmed or optimistically accepted by the #37 boundary.
4. If the unstar mutation fails, the starred list shall keep or restore the item as starred and surface a non-blocking error through existing feedback UI.
5. When the user toggles star from ArticleDetail for an item visible in the starred list, the starred list shall reflect the same effective star state through #37 synchronization.
6. When a star control is activated inside a tappable card, the action shall not also trigger card detail presentation.
7. While a star mutation for the same item is pending, repeated taps shall follow the deterministic policy established by #37 and shall not create duplicate contradictory requests.

### Requirement 7: Article detail and open-link integration

**Objective:** As a Feedman user, I want スター一覧から記事詳細や元記事へ進める, so that 保存した記事をすぐ読める

#### Acceptance Criteria

1. When the user taps a starred article card body, the app shall open the existing article detail flow for the selected item id.
2. When ArticleDetail opens from starred list, read marking and star state shall use existing #37 synchronization behavior.
3. When the user activates the open-link control, the app shall delegate to the existing external article opening boundary.
4. When the open-link control is activated inside a tappable card, the open-link action shall not also trigger card detail presentation.
5. When opening the original article marks the item read through an existing boundary, the starred list card shall reflect the synchronized read state.
6. The starred repository shall not present SFSafariViewController or call `PUT /api/items/{id}/state` directly for open-link side effects.

### Requirement 8: App shell integration

**Objective:** As a Feedman user, I want ドロワーの「お気に入り」からスター一覧へ到達できる, so that 保存済み記事を主要導線から再訪できる

#### Acceptance Criteria

1. When the drawer「お気に入り」entry is selected, the app shell shall navigate to or present the starred route.
2. When the starred route is active, the visible header title shall be equivalent to「お気に入り」and the context shall indicate starred articles.
3. When the current route is already starred, selecting the drawer entry again shall keep navigation deterministic and shall not create duplicate route state.
4. When leaving the starred screen, the app shell shall preserve existing drawer and route state conventions.
5. The starred screen shall not add global search, feed-scoped search, keyword notification, or search-history entry points.

### Requirement 9: Non-functional behavior and scope control

**Objective:** As a Developer, I want Issue #45 の変更範囲が明確である, so that スター一覧の縦切りだけを安全に実装できる

#### Acceptance Criteria

1. The implementation shall keep shared API / Repository code under `Feedman/Core` and feature UI under `Feedman/Features/Starred` or the existing AppShell feature boundary.
2. The implementation shall use Swift Concurrency and shall keep UI state changes on the main actor where required.
3. The implementation shall follow MVVM + Repository and shall keep Views away from direct `URLSession`、Keychain、Bearer token、and request body encoding.
4. The implementation shall not modify server contracts in `design/SPEC-iOS.md` or `design/SERVER.md`.
5. The implementation shall not implement global search or modify Issue #46 / #47 behavior.
6. The implementation shall not introduce persistence beyond existing repository / app session behavior.
7. Swift の型名、識別子、ファイル名は English にする。

## テスト観点

- When starred repository loads first page, the test suite shall verify method `GET`, path `/api/feeds/starred/items`, `limit`, bearer auth behavior, and no `cursor`.
- When next page loads, the test suite shall verify stored `cursor` is sent and items are appended.
- When `has_more` is false, `next_cursor` is null, or `next_cursor` is empty, the test suite shall verify terminal behavior.
- When first page succeeds with zero items, the ViewModel test shall verify empty state and shall not treat it as error.
- When repository returns transport / decode / auth error, the ViewModel test shall verify error state and retry behavior are distinct from empty state.
- When refresh succeeds, the ViewModel test shall verify existing items are replaced and pagination state resets.
- When next page fails, the ViewModel test shall verify previously loaded items remain visible.
- When a starred item is unstarred successfully, the ViewModel or integration test shall verify the item is removed from starred list or updated according to the explicit removal policy.
- When unstar mutation fails, the test shall verify rollback / restore and non-blocking error state.
- When star / open-link controls are activated inside a card, the test shall verify the intended action fires without also triggering card body detail action.
- When favicon is nil or `data:` URL, a view-level test shall verify the existing favicon component path is used and `AsyncImage(url:)` is not used directly for `data:` URL.
- When source title is long, a view-level or snapshot-style test should verify source row truncates without layout overlap.
- While macOS/Xcode test execution is available, the implementer shall run `xcodebuild -project Feedman.xcodeproj -scheme Feedman -destination 'platform=iOS Simulator,name=iPhone 16' test` or report why it could not be run.

## 実装境界

- Starred list 用 Repository は、既存 `FeedRepository` / `ItemRepository` に自然に収まる場合はそこへ統合してよい。無理な大規模 refactor は避ける。
- Starred pagination snapshot は、既存の cross-feed / feed-specific pagination snapshot と同じ規則を使う。
- Starred screen は article metadata controls と既存 card composition を再利用し、スター一覧専用の重複 control を作らない。
- `feed_title` は cross-feed source row の主要表示値として扱う。
- Starred list の item removal は「スター済みだけを表示する一覧」という screen policy を優先する。
- 日付文字列は RFC3339 `String` のまま保持し、表示層で整形する。
- Global search は #46 / #47 の責務であり、本 Issue では触らない。

## 確認事項

- #23 / #26 / #37 は develop merge 済みかつ `codex-staged-for-release` として扱えるため、Issue #45 の実装投入は可能と判断する。main 到達は release 運用上の別確認事項である。
- `/api/feeds/starred/items` の個別 `limit` 上限は仕様に明記がないため、一覧 API 共通の 200 を採用する。
- Unstar 時の画面 policy は「スター解除された記事をスター一覧から取り除く」を第一候補とする。実装時に既存 #37 の state synchronization 境界が別 policy を明確に持っている場合は、その policy と衝突しない範囲で合わせる。
