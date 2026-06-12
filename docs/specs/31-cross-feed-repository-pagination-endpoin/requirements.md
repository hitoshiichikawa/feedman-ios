# Issue #31 Cross-feed repository pagination endpoint 要件定義

## 概要

Issue #31 は Parent: #6 の子 Issue として、横断タイムライン向け Repository が `GET /api/items/cross-feed` を cursor pagination で取得できるようにする。
対象は Repository / Core API 境界の要件定義であり、Timeline UI、記事詳細、既読・スター更新、SFSafariViewController 連携は含めない。

`design/SPEC-iOS.md` では、一覧 API のページネーションを `{ items, next_cursor: string?, has_more }` と定義し、次ページは `cursor` と `limit` を指定する。横断新着のみ response に `since_time` を含み、セッション初回値を固定する。`GET /api/items/cross-feed` は 50件/回、上限200、`since_time` 付きの endpoint として定義されている。

`design/SERVER.md` はトークン認証と次フェーズ通知が中心であり、`/api/items/cross-feed`、cursor pagination、`since_time` について `design/SPEC-iOS.md` を上書きする追加契約は見当たらない。そのため本 Issue の API 契約は `design/SPEC-iOS.md` を正本とする。

## 依存判断

Issue 本文の依存は `Depends on: #17, #23` である。

- #17 `Cursor pagination helper` は PR #67 として `develop` へ merge 済みである。merge 時刻は 2026-06-11T20:39:41Z。
- #23 `APIClient 401 refresh retry hook` は PR #75 として `develop` へ merge 済みである。merge 時刻は 2026-06-12T07:03:44Z。
- Issue #31 のコメントでも owner により #17 / #23 の依存解消が確認され、`codex-blocked` 除去と `codex-auto-dev` 付与が行われている。

したがって本 Issue は #17 の `CursorPaginationState` / `CursorPaginatedPage` と #23 の認証付き `APIClient` retry behavior が存在する前提で実装へ進めてよい。

## スコープ

- `GET /api/items/cross-feed` を呼ぶ Repository protocol / real implementation / mock implementation の要件定義。
- 初回取得、次ページ取得、refresh / session reset における `limit`、`cursor`、`since_time` query item の扱い。
- `CrossFeedItemsResponse` の `items`、`next_cursor`、`has_more`、`since_time` を使った pagination state 更新。
- #17 の cursor pagination helper を利用した終端判定と item accumulation。
- #23 の `APIClient` 認証付き request を通じた Bearer token / 401 refresh retry との接続境界。
- Repository 単体テストで検証すべき query construction、session-fixed `since_time`、終端判定、error propagation の観点。

## スコープ外

- Timeline SwiftUI 画面、無限スクロール sentinel、Pull-to-refresh UI、終端表示文言の実装。
- 記事詳細 sheet、既読化、スター更新、楽観的更新、SFSafariViewController 起動。
- フィード別記事一覧、スター一覧、検索、購読設定、フィード登録。
- APIClient の 401 refresh retry hook 自体の変更。
- Cursor pagination helper 自体の仕様変更。
- サーバー API、`design/SPEC-iOS.md`、`design/SERVER.md` の変更。
- 実ネットワークや実 Keychain に依存する integration test。
- コミット、PR 作成、reviewer / project-manager 起動。

## API 契約から読み取れる前提

- Endpoint は認証必須の `GET /api/items/cross-feed` である。
- Response は `items`、`next_cursor`、`has_more`、`since_time` を持つ。
- `items` は `ItemSummary` の配列として扱う。
- `since_time` は RFC3339 文字列であり、`Date` へ自動 decode しない。
- 初回 page response の `since_time` を、同じ Repository pagination session の固定値として保持する。
- 次ページ request は `cursor=<next_cursor>`、`limit=<n>`、固定済み `since_time=<stored_since_time>` を送信する。
- `has_more == false`、または `next_cursor` が `null` / 空文字の場合、pagination は終端である。
- 1回あたりの取得件数は標準 50 件であり、サーバー上限は 200 件である。
- `design/SERVER.md` には本 endpoint の追加 request / response field は定義されていない。

## 要件

### Requirement 1: Cross-feed repository contract

**Objective:** As a Timeline ViewModel 実装者, I want 横断新着を Repository 経由で取得できる, so that View が APIClient や pagination query の詳細を知らずに一覧状態を扱える

#### Acceptance Criteria

1. The cross-feed repository shall `GET /api/items/cross-feed` を取得するための protocol または既存 repository protocol の method を提供する。
2. The cross-feed repository shall 初回 page 取得と次 page 取得を呼び出し側が区別できる API boundary を持つ。
3. The cross-feed repository shall 成功時に蓄積済み items、次 page 取得可否、次 cursor、固定済み `since_time` を呼び出し側が参照できる状態として返す、または保持する。
4. The cross-feed repository shall `ItemSummary` / `CrossFeedItemsResponse` の API model を使い、prototype mock data の JSON 形を API 契約として扱わない。
5. The cross-feed repository shall View から `URLSession`、Keychain、Bearer token refresh の詳細を隠蔽する。

### Requirement 2: First page session initialization

**Objective:** As an app user, I want 横断タイムラインの初回取得時点を session の基準に固定できる, so that pagination 中に新着が追加されても一覧の境界がずれない

#### Acceptance Criteria

1. When first page loads, the cross-feed repository shall request `/api/items/cross-feed` without a `cursor` query item.
2. When first page loads, the cross-feed repository shall include a `limit` query item using the configured page size.
3. When first page loads, the cross-feed repository shall not generate its own `since_time` value.
4. When first page response succeeds, the cross-feed repository shall store the returned `since_time` as the fixed value for the current pagination session.
5. When first page response succeeds, the cross-feed repository shall apply the response as the first page of pagination state rather than appending it to old items.
6. When first page response has `items`, the cross-feed repository shall expose those items in API order without re-sorting them in the Repository layer.
7. If first page response omits `since_time` or contains an undecodable shape, the cross-feed repository shall surface the existing API decode / transport error rather than silently starting an unstable session.

### Requirement 3: Next page request construction

**Objective:** As a Timeline ViewModel 実装者, I want 次ページ取得が cursor と固定済み `since_time` を正しく送る, so that 横断タイムラインの無限スクロールが重複や境界ずれを起こしにくい

#### Acceptance Criteria

1. When loading next page, the cross-feed repository shall include `cursor=<stored_next_cursor>` in the request.
2. When loading next page, the cross-feed repository shall include the same `limit` policy used for the session unless the caller explicitly starts a new session with a different valid limit.
3. When loading next page, the cross-feed repository shall include `since_time=<stored_since_time>` from the first successful page of the current session.
4. When loading next page succeeds, the cross-feed repository shall append response `items` after existing session items.
5. When loading next page succeeds, the cross-feed repository shall not replace the stored session `since_time` with a later response value.
6. If a later page response contains a different `since_time`, the cross-feed repository shall keep the first page `since_time` as authoritative for the current session.
7. If next page is requested before a successful first page has established `since_time`, the cross-feed repository shall fail fast or no-op with a typed state error; it shall not send a next-page request with missing session context.

### Requirement 4: Pagination terminal handling

**Objective:** As a Timeline ViewModel 実装者, I want pagination の終端を Repository から判断できる, so that UI が余分な network request を発行しない

#### Acceptance Criteria

1. When `has_more` is false, the cross-feed repository shall report no more pages.
2. When `next_cursor` is null, the cross-feed repository shall report no more pages.
3. When `next_cursor` is empty, the cross-feed repository shall report no more pages.
4. When `has_more` is true and `next_cursor` is present, the cross-feed repository shall report that another page can be loaded.
5. When pagination has ended, the cross-feed repository shall not issue another `/api/items/cross-feed` request for next page unless a refresh / new session is explicitly started.
6. When pagination has ended, the cross-feed repository shall preserve already loaded items for display by the caller.
7. The cross-feed repository shall use #17 の pagination helper or equivalent existing Core pagination contract instead of duplicating inconsistent terminal logic.

### Requirement 5: Limit policy

**Objective:** As a Developer, I want page size の扱いが仕様上限に収まる, so that client が server contract を超える query を送らない

#### Acceptance Criteria

1. The cross-feed repository shall use 50 as the default page size for `/api/items/cross-feed`.
2. The cross-feed repository shall not send a `limit` greater than 200.
3. If a caller supplies a page size greater than 200, the cross-feed repository shall clamp it to 200 or reject it with a deterministic client-side error.
4. If a caller supplies a non-positive page size, the cross-feed repository shall use the default 50 or reject it with a deterministic client-side error.
5. The chosen behavior for invalid page size shall be covered by unit tests and documented in implementation notes.
6. The limit policy shall be applied consistently to first page and next page requests within the same session.

### Requirement 6: Refresh and session reset

**Objective:** As a Timeline ViewModel 実装者, I want refresh が新しい pagination session として扱われる, so that 古い cursor と `since_time` が新しい取得に混ざらない

#### Acceptance Criteria

1. When refresh starts, the cross-feed repository shall reset stored items, next cursor, terminal state, and fixed `since_time` for the old session.
2. When refresh starts, the cross-feed repository shall request a first page without the old `cursor`.
3. When refresh starts, the cross-feed repository shall not send the old `since_time` unless a future server contract explicitly requires it.
4. When refreshed first page response succeeds, the cross-feed repository shall store the refreshed response `since_time` as the fixed value for the new session.
5. If refresh fails, the cross-feed repository shall not mix partially refreshed data into the previous successful session unless the implementation intentionally keeps stale data as a UI-facing state and documents that distinction.
6. While refresh is in progress, the cross-feed repository shall avoid corrupting the active pagination state if another next-page request is triggered concurrently.

### Requirement 7: APIClient and auth boundary

**Objective:** As a Repository 実装者, I want cross-feed networking to reuse the shared APIClient auth behavior, so that Bearer token and 401 refresh retry are not reimplemented per endpoint

#### Acceptance Criteria

1. The cross-feed repository shall call `/api/items/cross-feed` through the shared `APIClient` or equivalent Core API abstraction.
2. The cross-feed repository shall pass access token context according to the existing #23 APIClient contract for authenticated requests.
3. When the APIClient refreshes an expired access token and retries successfully, the cross-feed repository shall receive the decoded cross-feed response without endpoint-specific retry logic.
4. When auth refresh fails, the cross-feed repository shall surface the typed auth-required error from Core without converting it to an empty timeline.
5. The cross-feed repository shall not read or write Keychain directly.
6. The cross-feed repository shall not log access tokens, refresh tokens, `Authorization` header values, or personal data.

### Requirement 8: Mock repository behavior

**Objective:** As a Developer, I want mock cross-feed repository behavior to match pagination semantics, so that ViewModel tests can exercise first page, next page, empty, and terminal states without real network

#### Acceptance Criteria

1. The mock cross-feed repository shall provide deterministic first page data for cross-feed items.
2. The mock cross-feed repository shall be able to represent a next page with a non-empty cursor and `has_more == true`.
3. The mock cross-feed repository shall be able to represent terminal pagination with `has_more == false` or missing / empty `next_cursor`.
4. The mock cross-feed repository shall return a stable RFC3339 `since_time` for a pagination session.
5. When mock next page is loaded, the mock behavior shall preserve the session-fixed `since_time` expectation.
6. The mock repository shall avoid treating prototype-only fields as API contract fields.

### Requirement 9: Error and concurrency behavior

**Objective:** As a Timeline ViewModel 実装者, I want repository failures and overlapping loads to be deterministic, so that UI state can distinguish loading, retryable failure, auth-required failure, and end-of-list

#### Acceptance Criteria

1. When transport, decoding, or server error occurs, the cross-feed repository shall surface the typed Core error to the caller.
2. When an error occurs during next page loading, the cross-feed repository shall not mark pagination as ended solely because of the error.
3. When an error occurs during next page loading, the cross-feed repository shall preserve previously loaded successful items unless the caller explicitly resets the session.
4. While a page load is already in progress, the cross-feed repository shall avoid issuing duplicate requests that mutate the same pagination session unpredictably.
5. If overlapping first-page / refresh / next-page calls are possible, the implementation shall serialize them, reject the later call, or otherwise document deterministic state behavior.
6. The cross-feed repository shall not swallow errors and return an empty item list unless the API response itself is a successful empty page.

### Requirement 10: Unit test coverage

**Objective:** As a QA/Developer, I want cross-feed pagination behavior fixed by focused XCTest coverage, so that later Timeline UI work can rely on the Repository contract

#### Acceptance Criteria

1. When first page loads successfully, the test suite shall verify the request path is `/api/items/cross-feed`, `limit` is sent, `cursor` is absent, and returned `since_time` is stored.
2. When first page has `has_more == true` and non-empty `next_cursor`, the test suite shall verify the repository reports that more pages can be loaded.
3. When loading next page, the test suite shall verify `cursor` and first-page `since_time` are sent as query items.
4. When loading next page succeeds, the test suite shall verify new items are appended after first-page items.
5. When next page response contains a different `since_time`, the test suite shall verify the first-page `since_time` remains fixed for the session.
6. When `has_more == false`, the test suite shall verify the repository reports no more pages and does not request another next page.
7. When `next_cursor` is null or empty, the test suite shall verify the repository reports no more pages.
8. When refresh starts, the test suite shall verify old cursor and old `since_time` are not sent and the new response establishes a new fixed `since_time`.
9. When a configured limit exceeds 200 or is non-positive, the test suite shall verify the chosen clamp / reject behavior.
10. When APIClient surfaces auth-required or transport / decode errors, the test suite shall verify the repository propagates the error without converting it to empty or terminal state.
11. Unit tests shall use mock transport / mock APIClient boundary and shall not depend on real network, real OAuth, real Keychain, real tokens, or personal data.
12. While macOS/Xcode test execution is available, the implementer shall run `xcodebuild -project Feedman.xcodeproj -scheme Feedman -destination 'platform=iOS Simulator,name=iPhone 16' test` or report why it could not be run.

## 非機能要件

### NFR 1: Compatibility

1. The implementation shall target iOS 16+ and Swift Concurrency.
2. The implementation shall keep API models' RFC3339 date strings as `String` and shall not introduce automatic `Date` decoding for `since_time`.
3. The implementation shall use `struct` と限定的な可変状態を優先し、session state の変化を追いやすくする。
4. The implementation shall place shared API / Repository code under `Feedman/Core` according to the project architecture.
5. The implementation shall preserve #17 pagination helper behavior and #23 APIClient 401 refresh retry behavior.

### NFR 2: Scope control

1. The implementation shall be limited to cross-feed repository endpoint support, pagination session state, mock behavior, and focused unit tests.
2. The implementation shall not add Timeline UI, article state mutation, article detail sheet, or SFSafariViewController behavior.
3. The implementation shall not modify server contracts in `design/SPEC-iOS.md` or `design/SERVER.md`.
4. The implementation shall not modify finalized `docs/specs/*` for other Issues unless a dependency mismatch is discovered and explicitly documented.
5. The implementation shall not create commits, PRs, or invoke reviewer / project-manager agents as part of this PM requirements task.

## 実装境界

- 主な編集対象は `Feedman/Core` と `FeedmanTests` を想定する。
- 既存 `FeedRepository.crossFeedItems()` が配列のみを返す mock 形の場合、実装時は pagination state を表現できる repository boundary へ拡張する。
- `CrossFeedItemsResponse` は #17 の `CursorPaginatedPage` に準拠しているため、pagination state 更新には既存 helper を利用できる。
- Query item 名は `limit`、`cursor`、`since_time` とする。
- Repository は item の既読・スター状態を変更しない。`ItemSummary.is_read` / `is_starred` は response の表示用状態として保持するだけにする。
- Repository は重複 item の排除を必須責務にしない。重複排除が必要な場合は API contract または ViewModel 側の別 Issue として扱う。
- Repository は相対日時 formatting、favicon rendering、empty / loading / error view rendering を担当しない。

## 確認事項

- `design/SERVER.md` に `/api/items/cross-feed` の追加契約は見当たらないため、`design/SPEC-iOS.md` の契約を正本として採用する。
- `since_time` は初回 response の値を固定し、次ページ response に異なる値が含まれても current session では更新しない。
- Refresh は新しい session として扱い、旧 `cursor` / 旧 `since_time` を送らない。
- Invalid limit の扱いは clamp と reject のどちらも実装可能とするが、選択した方針を unit test と implementation notes に残す。
- 本 Issue では Timeline UI と item state mutation は明示的に非スコープである。
