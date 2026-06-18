# Issue #45 実装ノート

## 実装概要

- `FeedRepository` に `loadStarredItemsFirstPage(limit:)` / `loadStarredItemsNextPage()` と `StarredItemPaginationSnapshot` を追加した。
- `APIClientFeedRepository` は `GET /api/feeds/starred/items` を shared `APIClient` 経由で呼び出し、初回は `limit` のみ、次ページは保存済み `cursor` と同じ `limit` を送る。
- starred pagination は既存の `CursorPaginationState<ItemSummary>` を利用し、`has_more == false`、`next_cursor == nil`、空文字 cursor を terminal として扱う。
- `MockFeedRepository` に starred list 用の deterministic pagination を追加し、preview / test が実ネットワークへ依存しないようにした。
- `Feedman/Features/Starred` に `StarredViewModel` / `StarredView` を追加し、loading / empty / error / content / refresh / next page / terminal state を扱う。
- AppShell drawer の「お気に入り」は placeholder から `StarredView` に接続した。

## UI / 状態同期

- Starred card は既存の `ArticleSourceRow`、`ArticleHatebuCountControl`、`ArticleStarControl`、`ArticleOpenLinkControl` を使う。
- source row は `feedTitle` と `feedFaviconURL` を表示し、favicon の `data:` URL / nil / invalid handling は既存 `FeedmanFaviconView` に委譲する。
- article detail sheet には既存 `ArticleDetailSheetInput` を渡し、detail 側の read / star synchronization は shared `ItemStateCoordinator` を使う。
- `ArticleDetail` から `isStarred == false` の `ItemStateChange` が返った場合、Starred list から該当 item を取り除く。

## Unstar policy

- Starred list の画面 policy は「スター解除された記事を一覧から取り除く」とした。
- card 上の star off は `ItemStateCoordinator.beginMutation` による optimistic boundary を通し、成功時は mutation を commit して item を非表示のままにする。
- mutation failure または access token / repository 不足時は rollback し、削除済み item を元の位置へ restore して非ブロッキング error banner を表示する。
- 同一 item の star mutation pending 中の重複 tap は既存 `ItemStateCoordinator` の pending guard に従って無視される。

## テスト

- `CrossFeedRepositoryTests` に starred endpoint の request construction、cursor pagination、terminal state、first page 前 next page failure の coverage を追加した。
- `StarredViewModelTests` を追加し、初回 success / empty / error retry、refresh replace / failure preserve、next page append / failure preserve、unstar success removal、unstar failure restore、ArticleDetail state change removal、descriptor action 分離を確認した。
- 検証コマンド:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Feedman.xcodeproj -scheme Feedman -destination 'platform=iOS Simulator,name=iPhone 16' test
```

- 結果: 成功。354 tests, 0 failures。
- 補足: `DEVELOPER_DIR` なしの `xcodebuild` は active developer directory が `/Library/Developer/CommandLineTools` のため失敗した。Xcode.app は存在したため、global な `xcode-select` は変更せず `DEVELOPER_DIR` 指定で検証した。

## 確認事項

- `requirements.md` は PM 作成の入力として扱い、内容は変更していない。
- Global search (#46/#47) と確定済み仕様 docs は変更していない。
- `SharedPrimitives.swift` の既存 warning（`await` 内に async operation がない）は Issue #45 の変更ではないため未対応。
