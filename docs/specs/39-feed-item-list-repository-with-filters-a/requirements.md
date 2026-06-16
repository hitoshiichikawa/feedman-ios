# Issue #39 Feed item list repository with filters and pagination 要件定義

## 概要

Issue #39 は Parent: #8 の子 Issue として、フィード別記事一覧を `GET /api/feeds/{id}/items` から取得する Repository 境界を実装する。
対象は Core Repository / API model / mock / unit test の薄い縦切りであり、フィード画面の status banner、manual fetch、Pull-to-refresh、記事詳細 sheet、既読・スター更新 UI は含めない。

Issue コメントは 2026-06-12 時点で triage edit paths と処理開始通知のみで、人間コメントによる追加決定事項はなかった。

## 依存判断

Issue 本文の依存は `Depends on: #17, #23, #38` である。

- #17 により `CursorPaginationState` が利用可能である。
- #23 により `APIClient` の Bearer token / 401 refresh retry hook が利用可能である。
- #38 により `GET /api/subscriptions` 由来の real drawer feed state が利用可能であり、フィード選択元の feed id は server response の `feed_id` を使う前提でよい。

したがって本 Issue は既存 Core の pagination helper、APIClient、FeedRepository 実装にフィード別一覧の endpoint support を追加する方針で進める。

## 正本仕様

- `design/SPEC-iOS.md` は `GET /api/feeds/{id}/items?filter=all|unread|starred` をフィード別一覧のデータ取得 endpoint として定義している。
- 一覧 API のページネーションは `{ items, next_cursor: string?, has_more }` であり、次ページは `cursor=<next_cursor>&limit=<n>` を送る。
- `has_more == false`、または `next_cursor` が `null` / 空文字の場合は終端とする。
- 日付文字列は RFC3339 `String` として保持し、Repository 層で `Date` へ自動変換しない。
- `design/SERVER.md` には本 endpoint を上書きする追加契約は見当たらない。

## スコープ

- `FeedRepository` へフィード別記事一覧の初回 page / next page を取得できる API boundary を追加する。
- filter は `all` / `unread` / `starred` の型安全な値として扱い、query item `filter` に反映する。
- `GET /api/feeds/{id}/items` を shared `APIClient` 経由で呼び、Bearer token と 401 refresh retry は既存 Core に委譲する。
- response `items` は `ItemSummary` として decode し、pagination state で蓄積する。
- next page は同一 feed id / filter / limit の session として、保存済み cursor を送って append する。
- mock repository も filter と pagination の代表状態を表現できるようにする。
- XCTest で request path、query、filter 切替、append、終端、error propagation を検証する。

## スコープ外

- Feed screen status banner と manual fetch。
- `POST /api/subscriptions/{id}/fetch`、`POST /api/subscriptions/{id}/resume`、購読設定 UI。
- Feed route の SwiftUI 本実装、filter Picker / chip UI、無限スクロール sentinel。
- 記事詳細 sheet、SFSafariViewController、既読化、スター更新、楽観的更新。
- スター一覧 `GET /api/feeds/starred/items` と横断検索。
- APIClient、CursorPaginationState、既存 docs/specs の仕様変更。
- サーバー API、`design/SPEC-iOS.md`、`design/SERVER.md` の変更。
- 実ネットワーク、実 OAuth、実 Keychain に依存する integration test。
- PR 作成、reviewer / project-manager サブエージェント起動。

## 要件

### Requirement 1: Feed item repository contract

**Objective:** As a Feedman user, I want selected feed items to load through the repository, so that the feed-specific list can use server data without knowing APIClient details

#### Acceptance Criteria

1. When a feed is selected, the repository shall provide a method to load the first page for that feed id.
2. When a feed-specific first page is loaded, the repository shall call `GET /api/feeds/{id}/items`.
3. When the repository returns a feed-specific page, it shall expose accumulated `ItemSummary` values, `nextCursor`, `canLoadMore`, `feedID`, `filter`, and `limit`.
4. The repository shall keep View code isolated from `URLSession`, Keychain, Bearer token headers, and refresh retry details.

### Requirement 2: Filter query

**Objective:** As a Feedman user, I want all/unread/starred filters to request matching server data, so that the feed list reflects the selected filter

#### Acceptance Criteria

1. When filter is `all`, the repository shall send `filter=all`.
2. When filter is `unread`, the repository shall send `filter=unread`.
3. When filter is `starred`, the repository shall send `filter=starred`.
4. When filter changes, the repository shall start a new first-page pagination session and shall not append items from the previous filter.
5. The filter values shall be represented by a Swift type rather than free-form strings at call sites.

### Requirement 3: First page and refresh semantics

**Objective:** As a ViewModel implementer, I want first-page loading to reset feed-specific pagination state, so that stale cursor and items do not leak between sessions

#### Acceptance Criteria

1. When first page loads, the repository shall request without a `cursor` query item.
2. When first page loads, the repository shall include `limit` using the normalized page size.
3. When first page succeeds, the repository shall replace accumulated items with response `items`.
4. When first page succeeds, the repository shall store response `next_cursor` and terminal state using the shared pagination behavior.
5. When first page fails, the repository shall surface the Core error and shall not silently return an empty successful page.

### Requirement 4: Cursor pagination

**Objective:** As a ViewModel implementer, I want next-page loading to append server items, so that infinite scroll can be implemented later

#### Acceptance Criteria

1. When next page is needed, the repository shall send `cursor=<stored_next_cursor>`.
2. When next page is needed, the repository shall keep the same feed id, filter, and limit from the current session.
3. When next page succeeds, the repository shall append response `items` after existing items.
4. When next page is requested before a successful first page, the repository shall fail fast with a typed state error and shall not send a network request.
5. When pagination has ended, the repository shall return the current snapshot without issuing another next-page request.
6. When next page fails, the repository shall preserve the previous successful items and cursor.

### Requirement 5: Terminal handling and limits

**Objective:** As a Developer, I want feed-specific pagination to share the same terminal and limit policy as other item lists, so that behavior stays consistent

#### Acceptance Criteria

1. When `has_more` is false, the repository shall report no more pages.
2. When `next_cursor` is null, the repository shall report no more pages.
3. When `next_cursor` is empty, the repository shall report no more pages.
4. When `has_more` is true and `next_cursor` is non-empty, the repository shall report that another page can be loaded.
5. The repository shall use 50 as the default page size.
6. The repository shall not send a `limit` greater than 200.
7. If a supplied limit is non-positive, the repository shall use the default 50.

### Requirement 6: Mock repository

**Objective:** As a Developer, I want mock feed-specific pagination to behave deterministically, so that future Feed ViewModel tests can exercise filter and page states without networking

#### Acceptance Criteria

1. The mock repository shall provide deterministic first-page feed items.
2. The mock repository shall represent `all`, `unread`, and `starred` filters by filtering mock item state.
3. When mock next page loads, it shall append deterministic next-page items for the active feed/filter session when available.
4. When mock pagination reaches terminal state, it shall preserve loaded items and report no more pages.

### Requirement 7: Unit tests

**Objective:** As a QA/Developer, I want focused XCTest coverage, so that the Repository contract can be independently reviewed before UI integration

#### Acceptance Criteria

1. When first page loads, the test suite shall verify path `/api/feeds/{id}/items`, method `GET`, bearer auth, `filter`, `limit`, and no `cursor`.
2. When filter changes, the test suite shall verify the new first-page request sends the new filter and replaces old accumulated items.
3. When next page loads, the test suite shall verify stored `cursor` is sent and items are appended.
4. When pagination is terminal, the test suite shall verify another next-page call does not issue a network request.
5. When next page is requested before first page, the test suite shall verify a typed error and no network request.
6. When `next_cursor` is null or empty, the test suite shall verify terminal behavior.
7. When APIClient surfaces auth or transport error, the test suite shall verify the repository propagates the error without converting it to an empty success.
8. While macOS/Xcode is available, the implementer shall run `xcodebuild -project Feedman.xcodeproj -scheme Feedman -destination 'platform=iOS Simulator,name=iPhone 16' test` or document why it could not be run.

## 実装境界

- 主な編集対象は `Feedman/Core/FeedRepository.swift`、必要な API model extension、`FeedmanTests` の repository tests を想定する。
- 既存 `CrossFeedPaginationSnapshot` と同様の snapshot 型を追加するか、意味が明確な共通型へ拡張する。ただし不要な大規模 refactor は避ける。
- Query item 名は `filter`、`limit`、`cursor` とする。
- `feedID` は path component として `/api/feeds/{id}/items` に埋め込む。既存 `APIClient` の path composition を利用する。
- Repository は item の重複排除、並び替え、相対日時 formatting、favicon rendering、empty/loading/error UI を担当しない。

## 確認事項

- フィード別一覧 endpoint の `limit` 上限は `design/SPEC-iOS.md` の一覧 pagination 共通扱いとして 200 を採用する。feed-specific endpoint 個別の別上限は仕様に記載がない。
- `feedID` の URL path escaping は既存 `APIClient` path contract に従う。feed id が `/` 等を含む場合の server contract は本 Issue では追加定義しない。
