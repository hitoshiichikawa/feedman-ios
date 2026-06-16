# Issue #39 実装メモ

## 実装内容

- `FeedRepository` にフィード別記事一覧用の repository boundary を追加した。
  - `FeedItemFilter` (`all` / `unread` / `starred`)
  - `FeedItemPaginationSnapshot`
  - `loadFeedItemsFirstPage(feedID:filter:limit:)`
  - `loadFeedItemsNextPage()`
- `APIClientFeedRepository` で `GET /api/feeds/{id}/items` を実装した。
  - query は `filter`、`limit`、next page 時のみ `cursor` を送る。
  - limit は既存 cross-feed と同じく default `50`、maximum `200`、非正値は default に正規化する。
  - `CursorPaginationState<ItemSummary>` を使い、`has_more == false`、`next_cursor == nil`、`next_cursor == ""` を終端として扱う。
  - first page / filter change は state を reset して成功時に replace、next page は append する。
  - first page 成功前の next page は `FeedItemRepositoryError.nextPageRequestedBeforeFirstPage` を返し、network request を出さない。
  - next page 失敗時は既存の items / cursor を更新しない。
- `MockFeedRepository` も feed id / filter / limit に応じた deterministic な first / next page を返すようにした。

## テスト

- `FeedmanTests/CrossFeedRepositoryTests.swift` に feed-specific repository の focused tests を追加した。
  - first page の path / method / bearer auth / `filter` / `limit` / cursor なし。
  - `all` / `unread` / `starred` の query 値。
  - filter change による first-page replace。
  - next page の stored cursor 送信と append。
  - limit の `200` clamp と非正値の default `50` 正規化。
  - terminal page 後に追加 request を出さないこと。
  - first page 前 next page の typed error と request なし。
  - nil / empty cursor の終端判定。
  - next page transport error の伝播と cursor 保持。
  - feed-specific first page の auth-required error 伝播。
  - mock repository の filter / pagination。

## 検証結果

- 実行不可: `xcodebuild -project Feedman.xcodeproj -scheme Feedman -destination 'platform=iOS Simulator,name=iPhone 16' test`
  - 理由: `xcodebuild` が Xcode ではなく `/Library/Developer/CommandLineTools` を参照しており、`tool 'xcodebuild' requires Xcode` で失敗した。
  - `/Applications` 配下に `Xcode*.app` は見つからなかった。
- 実行不可: `xcrun swiftc -typecheck -parse-as-library ... FeedmanTests/CrossFeedRepositoryTests.swift`
  - 理由: Command Line Tools 環境で `XCTest` module が見つからず失敗した。
- 代替として以下を実行し、Core の typecheck は成功した。

```bash
xcrun swiftc -typecheck -parse-as-library Feedman/Core/APIModels.swift Feedman/Core/APIError.swift Feedman/Core/APIClient.swift Feedman/Core/Models.swift Feedman/Core/Pagination/CursorPaginationState.swift Feedman/Core/FeedRepository.swift
```
