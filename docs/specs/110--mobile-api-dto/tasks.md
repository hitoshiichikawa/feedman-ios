# Implementation Plan

- [x] 1. Cross-feed pagination request contract を修正する
  - first page response の `since_time` を pagination baseline として保持する。
  - next page request では stored cursor / normalized limit とともに `since` を送り、`since_time` query を送らない。
  - baseline 未確立時の next page request を拒否し、欠落 baseline の network request を防ぐ。
  - cross-feed pagination regression test で `since` 送信、`since_time` 非送信、cursor / limit 継続、missing baseline guard を検証する。
  - _Requirements: 1.1, 1.2, 1.3, 1.4, 1.5, 5.1, 5.2_
  - _Boundary: CrossFeedRepository, CrossFeedPaginationTests_

- [x] 2. Search request / response DTO contract を修正する
  - global search request は `q` / `cursor` / normalized `limit` を送り、`scope` を送らない。
  - search response は `{ items, next_cursor, has_more }` wrapper を decode し、server order と terminal page 判定を保持する。
  - internal feed-scoped search capability は `scope=feed` ではなく `feed_id` query を使う。
  - feed-scoped search UI を追加せず、既存 global search flow のみを維持する。
  - repository / decode / ViewModel regression test で request query、wrapper metadata、server order、terminal page 判定、feed_id query を検証する。
  - _Requirements: 2.1, 2.2, 2.3, 2.4, 2.5, 2.6, 2.7, 2.8, 2.9, 2.10, 2.11, 5.3, 5.4_
  - _Boundary: SearchAPIModels, SearchRepository, GlobalSearchPresentation, SearchContractTests_

- [x] 3. Item list / detail の feed metadata 欠落許容と表示 fallback を実装する
  - feed-scoped item list DTO は `feed_title` / `feed_favicon_url` 欠落を malformed response として扱わない。
  - feed-scoped list presentation は route が保持する selected feed metadata を display fallback として使う。
  - item detail DTO は redundant feed metadata 欠落を許容し、detail が持つ metadata を優先して表示する。
  - detail metadata 欠落時は originating summary metadata を fallback にし、全 metadata 欠落時は neutral source state を表示する。
  - decode / FeedViewModel / ArticleDetailViewModel regression test で欠落 metadata、selected feed fallback、originating summary fallback、neutral state を検証する。
  - _Requirements: 3.1, 3.2, 3.3, 3.4, 3.5, 3.6, 3.7, 3.8, 3.9, 5.5, 5.6_
  - _Boundary: ItemAPIModels, FeedViewModel, FeedView, ArticleDetailViewModel, FeedMetadataFallbackTests_

- [x] 4. Feed registration response と subscription reload flow をサーバ契約へ合わせる
  - `POST /api/feeds` success は server feed response fields `id` / `feed_url` / `site_url` / `title` / `fetch_status` を登録 payload として decode する。
  - registration response では subscription-only fields を要求せず、successful no-body response も成功扱いにする。
  - 登録成功後は drawer subscription reload を正本とし、reload 成功時は reloaded subscription list を drawer source of truth にする。
  - reload 失敗時は registration success を保ち、recoverable subscription refresh failure を表示する。
  - registration repository / AppShell drawer state regression test で server feed response shape、no-body success、reload trigger、reload success / failure を検証する。
  - _Requirements: 4.1, 4.2, 4.3, 4.4, 4.5, 4.6, 4.7, 5.7, 5.8_
  - _Boundary: FeedRegistrationAPIModels, APIClient, FeedRegistrationRepository, AppShellRegistrationRefreshFlow, FeedRegistrationContractTests_

- [x] 5. Contract regression coverage と実装記録を更新する
  - Requirements 1-5 の AC Coverage Matrix を `impl-notes.md` に記録する。
  - NFR 1 / NFR 2 の scope control と secret logging 非追加を差分レビューで確認する。
  - macOS/Xcode 環境で canonical xcodebuild test を実行し、結果を `impl-notes.md` に記録する。
  - _Requirements: 1.1, 1.2, 1.3, 1.4, 1.5, 2.1, 2.2, 2.3, 2.4, 2.5, 2.6, 2.7, 2.8, 2.9, 2.10, 2.11, 3.1, 3.2, 3.3, 3.4, 3.5, 3.6, 3.7, 3.8, 3.9, 4.1, 4.2, 4.3, 4.4, 4.5, 4.6, 4.7, 5.1, 5.2, 5.3, 5.4, 5.5, 5.6, 5.7, 5.8_
  - _Boundary: MobileAPIContractDocumentation, ContractRegressionTests_
  - _Depends: 1, 2, 3, 4_

## Verify

本 spec の実装後、watcher が再実行すべき verify コマンドを構造化ブロックで宣言する。

<!-- stage-a-verify -->
```sh
git diff --check &&
xcodebuild -project Feedman.xcodeproj -scheme Feedman -destination 'platform=iOS Simulator,name=iPhone 16' test
```
