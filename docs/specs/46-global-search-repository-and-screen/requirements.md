# Issue #46 Global search repository and screen 要件定義

## 概要

Issue #46 は Parent: #10 の子 Issue として、v1 スコープである横断検索を Repository と SwiftUI screen から利用可能にする。
検索ボタンから到達する検索画面で query を入力し、空ではない query の送信時だけ `GET /api/items/search?q=&scope=global` を呼び、結果を `ItemSearchHit` として表示する。

Issue 本文の依存 `Depends on: #23, #26` は、Issue コメントで owner により develop merge 済みとして扱う決定がある。そのため、本 Issue は #23 の認証付き `APIClient` refresh retry behavior と #26 の shared article metadata controls が利用可能な前提で進める。

`design/SPEC-iOS.md` では、検索は v1 スコープに含まれ、`GET /api/items/search?q=&scope=global|feed`、空状態でサジェストチップ、結果は `ItemSearchHit` と定義されている。`ItemSearchHit` は `ItemSummary` とは別 struct であり、`published_at: String?`、`favicon_url: String?` を持ち、`hatebu_fetched_at` を含まない。`design/SERVER.md` には `/api/items/search` を上書きする追加契約は見当たらないため、本 Issue の API 契約は `design/SPEC-iOS.md` を正本とする。

## スコープ

- `Feedman/Core` に、横断検索用 Repository protocol / real implementation / mock implementation を追加または既存 Repository 境界へ統合する。
- `GET /api/items/search` を認証付き `APIClient` 経由で呼び出し、query item として `q=<query>` と `scope=global` を送る。
- 空文字または空白のみの query では search endpoint を呼ばず、検索画面はサジェストまたは空状態を表示する。
- `ItemSearchHit` を `ItemSummary` と混同せず、nullable な `published_at` / `favicon_url` を許容して表示する。
- 既存 AppShell の search route または同等の明示的 search surface を、placeholder から実検索画面へ置き換える。
- 検索結果から記事詳細と元記事 open へ進める UI event 境界を用意する。実際の記事詳細取得、既読化、スター更新、Safari presentation は既存の該当 Repository / coordinator がある場合に委譲する。
- #26 の shared article metadata controls を検索結果カードで利用し、source row、star、open-link control の見た目と tap 境界を既存一覧と揃える。
- Repository / ViewModel / UI の loading、success、empty、error state と focused XCTest coverage を定義する。

## スコープ外

- Feed-scoped search UI と `scope=feed` を使う画面導線。
- Search history sync、検索履歴の永続化、サーバー同期。
- キーワードプッシュ通知 UI、notification keyword 管理、drawer 導線。
- `/api/items/search` の server contract 変更、`design/SPEC-iOS.md` / `design/SERVER.md` の変更。
- 検索結果の cursor pagination、無限スクロール、検索候補の server-side API 化。
- `ItemSearchHit` を `ItemSummary` へ無理に変換するための API model 変更。
- `APIClient` の 401 refresh retry hook 自体の変更。
- #26 shared controls 自体の仕様変更。
- PR 作成、reviewer / project-manager 起動、コミット。

## API 契約

- Endpoint: `GET /api/items/search`
- 認証: v1 の認証必須 API として、`Authorization: Bearer <access_token>` を #23 の共有 `APIClient` 契約に従って付与する。
- Query:
  - `q`: ユーザーが送信した検索語。空文字または空白のみの場合は request を送らない。
  - `scope`: 本 Issue では常に `global` を送る。`feed` scope は API 契約上存在するが、Feed-scoped search UI は v1 スコープ外である。
- Response:
  - 検索結果 item は `ItemSearchHit` として decode / 表示する。
  - `ItemSearchHit.published_at` は `String?` であり、`nil` でも decode と表示が失敗してはならない。
  - `ItemSearchHit.favicon_url` は `String?` であり、`nil` または `data:` URL でも #25 / #26 の favicon 表示規則に従って安全に扱う。
  - `ItemSearchHit` は `hatebu_fetched_at` を含まない。検索結果カードで hatebu fetched state が必要な場合は unavailable として扱い、存在しない timestamp を合成しない。
  - 日付文字列は `String` のまま保持し、`Date` への自動 decode を追加しない。
- Error:
  - transport / decode / server error / auth-required error は Core の typed error として ViewModel へ伝播し、成功した空結果と区別する。
  - 401 refresh retry の詳細は endpoint-specific に再実装しない。

## 受入基準（EARS）

### Requirement 1: Search repository contract

**Objective:** As a Search ViewModel 実装者, I want 横断検索を Repository 経由で実行できる, so that View が `APIClient`、Bearer token、query construction の詳細を知らずに検索 state を扱える

1. The search repository shall `GET /api/items/search` を呼び出す async API を提供する。
2. The search repository shall 検索語と検索 scope を Repository 境界で表現し、本 Issue の screen からは `scope=global` を指定できる。
3. The search repository shall 成功時に `ItemSearchHit` の配列を返す。
4. The search repository shall `ItemSearchHit` を `ItemSummary` へ変換せず、別 struct として扱う。
5. The search repository shall View から `URLSession`、Keychain、Bearer token refresh の詳細を隠蔽する。
6. The mock search repository shall success、empty、transport error、decode/auth error 相当の状態を deterministic に返せる。

### Requirement 2: Request construction and auth

**Objective:** As a Feedman user, I want 検索語が正しく API に送られる, so that 購読中フィードを横断して目的の記事を探せる

1. When the user submits a non-empty search query, the app shall call `/api/items/search` with `q=<query>` and `scope=global`.
2. When the query contains spaces, Japanese text, or reserved URL characters, the app shall rely on shared URL encoding behavior and shall not build an invalid URL.
3. When search request is sent, the repository shall use the shared authenticated `APIClient` behavior from #23.
4. When the APIClient refreshes an expired access token and retries successfully, the search repository shall return decoded search results without endpoint-specific retry logic.
5. When auth refresh fails, the search repository shall surface the typed auth-required error and shall not display it as an empty result.
6. The search repository shall not log access tokens, refresh tokens, `Authorization` header values, search query personal data beyond normal debug-safe diagnostics, or response content containing personal data.

### Requirement 3: Empty query behavior

**Objective:** As a Feedman user, I want 空の検索画面で無駄な通信が発生しない, so that 入力前は候補または空状態だけを確認できる

1. When query is empty, the app shall not call the search endpoint.
2. When query contains only whitespace, the app shall not call the search endpoint.
3. When search screen opens before any query is submitted, the screen shall show suggestion chips or an empty/suggestion state.
4. When the user clears the query, the screen shall clear previous result presentation or mark it as no active query without issuing a new search request.
5. When a suggestion chip is selected, the app shall treat the suggestion text as the active non-empty query and may submit global search according to the same request rules.

### Requirement 4: Search screen states

**Objective:** As a Feedman user, I want 検索の loading / result / empty / error が区別される, so that 状態に応じて次の行動を取りやすい

1. When a non-empty query is submitted, the search screen shall show a loading state until the repository completes.
2. When search succeeds with one or more hits, the search screen shall render those hits in API order.
3. When search succeeds with zero hits, the search screen shall show an empty result state for the submitted query.
4. When search fails with a retryable transport or server error, the search screen shall show an error state that allows retrying the same query.
5. When search fails with auth-required error, the search screen shall surface the app's existing auth-required handling path rather than showing stale successful results as current.
6. While a search request is in progress, the ViewModel shall avoid applying stale results over a newer submitted query.
7. If multiple submissions happen quickly, the ViewModel shall cancel, ignore, or serialize older in-flight work so that the visible result corresponds to the latest submitted query.

### Requirement 5: Nullable search hit rendering

**Objective:** As a Feedman user, I want 検索結果に欠損 metadata が含まれていても一覧を読める, so that API の null 値で画面が壊れない

1. When results contain nullable `published_at`, the UI shall render without crash.
2. When `published_at` is null, the UI shall omit the date, show an unavailable date state, or use an existing neutral metadata placeholder without inventing a timestamp.
3. When results contain nullable `favicon_url`, the UI shall render without crash.
4. When `favicon_url` is null or invalid, the UI shall use the existing favicon fallback behavior rather than passing an invalid URL to `AsyncImage`.
5. When `favicon_url` is a `data:` URL, the UI shall use the dedicated favicon component behavior and shall not pass it directly to `AsyncImage(url:)`.
6. When `ItemSearchHit` lacks `hatebu_fetched_at`, the UI shall not require that field and shall treat hatebu fetched state as unavailable if displayed.
7. The UI shall keep source row, title, summary, metadata controls, and action controls from overlapping at narrow widths and Dynamic Type sizes supported by the app.

### Requirement 6: Result actions

**Objective:** As a Feedman user, I want 検索結果から記事詳細と元記事へ進める, so that 見つけた記事をその場で読める

1. When the user taps a search result card, the app shall open the article detail flow for the selected item id using the existing article detail boundary where available.
2. When the user activates the open-link control on a search result, the app shall request opening the hit's `link` through the existing external article opening boundary where available.
3. When the open-link control is activated inside a tappable result card, the open-link action shall not also trigger the card detail action.
4. When the search hit exposes starred state, the star control shall render that state through #26 shared controls.
5. When the search hit does not provide enough state to perform a mutation safely, the screen shall avoid direct mutation and shall delegate to existing item state Repository behavior rather than inventing a search-specific mutation API.
6. When result action integration depends on another finalized feature, the implementation shall use that existing boundary and shall not duplicate SFSafariViewController presentation, item detail networking, or item state mutation logic inside the search repository.

### Requirement 7: App shell integration

**Objective:** As a Feedman user, I want toolbar の検索導線から本検索画面へ到達できる, so that どの画面からでも横断検索を開始できる

1. When the search toolbar button is tapped, the app shell shall present the global search screen or navigate to the explicit search route.
2. When the current route is already search, tapping the search toolbar button shall keep behavior deterministic and shall not push duplicate navigation state.
3. When the search screen is shown, the visible title or search field context shall make it clear that this is global search across subscribed feeds.
4. When leaving the search screen, the app shell shall preserve existing drawer and route state conventions from #28 / #30.
5. The search screen shall not add keyword notification, feed-scoped search, or search-history entry points.

### Requirement 8: Scope control and non-functional behavior

**Objective:** As a Developer, I want 本 Issue の変更範囲が明確である, so that 横断検索の縦切りだけを安全に実装できる

1. The implementation shall keep shared API / Repository code under `Feedman/Core` and feature UI under `Feedman/Features/Search` or the existing AppShell feature boundary.
2. The implementation shall use Swift Concurrency and shall keep UI state changes on the main actor where required.
3. The implementation shall use #26 shared article metadata controls where practical instead of duplicating star, source row, favicon, hatebu unavailable, or open-link controls.
4. The implementation shall not modify server contracts in `design/SPEC-iOS.md` or `design/SERVER.md`.
5. The implementation shall not add feed-scoped search UI or search history sync.
6. The implementation shall not treat prototype mock data shape as API contract.

## テスト観点

- When search repository submits a non-empty query, the test suite shall verify path `/api/items/search` and query items `q=<query>` / `scope=global`.
- When query is empty or whitespace-only, the ViewModel test shall verify no repository / transport request is issued.
- When query contains Japanese text, spaces, or reserved characters, the repository/APIClient boundary test shall verify URL encoding does not corrupt the query.
- When search succeeds with results, the ViewModel test shall verify loadingからsuccessへ遷移し、`ItemSearchHit` の配列を API order のまま公開する。
- When search succeeds with zero results, the ViewModel test shall verify empty result state と active query が区別される。
- When repository returns transport / decode / auth error, the ViewModel test shall verify error state と retry behavior が empty result と区別される。
- When two queries are submitted quickly, the ViewModel test shall verify older response does not overwrite the latest query result.
- When `published_at` is null, a decode or view-level test shall verify date rendering does not crash and bogus date is not synthesized.
- When `favicon_url` is null or `data:` URL, a view-level test shall verify the existing favicon fallback/decode path is used and `AsyncImage(url:)` に直接渡さない。
- When search hit lacks `hatebu_fetched_at`, the test shall verify search result card does not require that field and renders hatebu state as unavailable or hidden according to shared control input.
- When open-link or star controls are activated inside a result card, the test shall verify the intended action fires without also triggering the card open action.
- While macOS/Xcode test execution is available, the implementer shall run `xcodebuild -project Feedman.xcodeproj -scheme Feedman -destination 'platform=iOS Simulator,name=iPhone 16' test` or report why it could not be run.

## 未確認事項

なし
