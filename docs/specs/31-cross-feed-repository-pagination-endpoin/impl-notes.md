# Issue #31 実装メモ

## 実装内容

- `FeedRepository` に横断タイムライン用の pagination API を追加した。
  - `loadCrossFeedFirstPage(limit:)`
  - `loadCrossFeedNextPage()`
- `APIClientFeedRepository` を追加し、`GET /api/items/cross-feed` を `APIClient` 経由で取得する real repository とした。
- `CrossFeedPaginationSnapshot` で蓄積済み `ItemSummary`、`nextCursor`、`canLoadMore`、session 固定 `sinceTime`、session `limit` を返すようにした。
- `CursorPaginationState<ItemSummary>` を使い、`has_more == false`、`next_cursor == nil`、`next_cursor == ""` の終端判定を既存 helper に揃えた。
- 互換 API の `crossFeedItems() async throws -> [FeedItem]` は維持し、内部で first page を取得して既存 UI model へ変換する。
- `MockFeedRepository` も同じ pagination API を実装し、first page / next page / terminal の deterministic な session を返す。

## session と request 方針

- first page / refresh は新しい session として扱う。
  - query は `limit` のみ送る。
  - 旧 `cursor` と旧 `since_time` は送らない。
  - 成功 response の `since_time` を current session の固定値として保存する。
- next page は current session の `nextCursor`、first page で固定した `sinceTime`、同じ `limit` を送る。
- next page response の `since_time` が first page と異なっても、current session の固定 `sinceTime` は上書きしない。
- terminal 到達後の `loadCrossFeedNextPage()` は network request を出さず、現在の snapshot を返す。
- first page 成功前の `loadCrossFeedNextPage()` は `CrossFeedRepositoryError.nextPageRequestedBeforeFirstPage` を返し、network request を出さない。

## limit 方針

- default は仕様通り `50`。
- server max は仕様通り `200`。
- caller supplied limit が `200` を超える場合は `200` に clamp する。
- caller supplied limit が `0` 以下の場合は default `50` に正規化する。
- 正規化後の limit は session limit として保存し、first page と next page で同じ値を使う。

## error / concurrency 方針

- transport / decode / server / auth error は `APIClient` からの typed error をそのまま caller に伝播する。
- next page 失敗時は既存の pagination state を更新しないため、既存 items と cursor は維持される。
- `APIClientFeedRepository` は actor と `isLoadingCrossFeedPage` で cross-feed page load を制御する。
- load 中に同じ repository session へ別 load が入った場合は `CrossFeedRepositoryError.loadInProgress` を返し、重複 request による state 破壊を避ける。
- refresh / first page は request 開始時に old session を reset する。refresh 失敗時は古い session data と新しい partial data を混ぜない。

## テスト

- `FeedmanTests/CrossFeedRepositoryTests.swift` を追加した。
- 実 network / OAuth / Keychain を使わず、test 内の小さい `APITransport` mock で `APIClient` 境界を検証している。
- 主な検証観点:
  - first page の path / method / `limit` / `cursor` absence / `since_time` absence。
  - `has_more == true` かつ non-empty `next_cursor` の `canLoadMore`。
  - next page の `cursor` / first-page fixed `since_time` / same `limit`。
  - next page append と fixed `since_time` 維持。
  - `has_more == false`、`next_cursor == nil`、`next_cursor == ""` の terminal。
  - terminal 後 next page no-op。
  - refresh が old `cursor` / old `since_time` を送らないこと。
  - invalid limit の clamp / default 正規化。
  - next page before first page の fail-fast。
  - transport error と auth-required error の伝播。

## 検証結果

- `xcodebuild -project Feedman.xcodeproj -scheme Feedman -destination 'platform=iOS Simulator,name=iPhone 16' test`
  - 実行不可。active developer directory が `/Library/Developer/CommandLineTools` で、Xcode が選択されていないため `xcodebuild` が使用できなかった。
- `xcrun swiftc -typecheck -parse-as-library Feedman/Core/APIClient.swift Feedman/Core/APIError.swift Feedman/Core/APIModels.swift Feedman/Core/Models.swift Feedman/Core/Pagination/CursorPaginationState.swift Feedman/Core/FeedRepository.swift`
  - 成功。
- XCTest file の direct typecheck は不可。この環境では `XCTest` module が見つからなかった。
