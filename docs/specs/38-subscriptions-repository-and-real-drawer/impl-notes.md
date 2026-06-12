# Issue #38 実装ノート

## 実装概要

- `APIClientFeedRepository.subscriptions()` を `GET /api/subscriptions` へ接続し、`Authorization: Bearer <access token>` 付きで `[Subscription]` を取得するようにした。
- `Subscription.feed_id`、`feed_title`、`unread_count`、`feed_status`、`error_message`、`favicon_url` を drawer 用 `Feed` / `FeedStatus` に map するようにした。負数の `unread_count` は server contract 外の異常値として `0` に clamp する。
- `Feed` に `faviconURL` を追加し、drawer row は `AsyncImage` ではなく既存の `FeedmanFaviconView` へ渡すようにした。
- `AppEnvironment.production()` は mock repository ではなく `APIClientFeedRepository` を組み立てるようにした。access token は `AppAccessTokenStore` で保持し、login 完了時と refresh hook 成功時に更新する。
- drawer feed section の failed state に「再試行」ボタンを追加し、既存の `AppShellDrawerFeedViewModel.loadSubscriptions(repository:)` を再実行できるようにした。

## テスト追加

- `/api/subscriptions` の path、method、Authorization header、`[Subscription]` から `[Feed]` への mapping を mock transport で検証するテストを追加した。
- empty response、負数 unread count の clamp、401 後の refresh retry 成功を repository test に追加した。
- drawer ViewModel の failure 後 retry と unread count 更新を検証するテストを追加した。
- `AppEnvironment.production()` が `APIClientFeedRepository` を持つことを検証するテストを追加した。

## 検証

- 実行: `git diff --check`
  - 結果: 成功。
- 実行: `swiftc -parse Feedman/Core/Models.swift Feedman/Core/APIModels.swift Feedman/Core/APIError.swift Feedman/Core/APIClient.swift Feedman/Core/Auth/TokenStore.swift Feedman/Core/Auth/AuthRepository.swift Feedman/Core/Pagination/CursorPaginationState.swift Feedman/Core/FeedRepository.swift Feedman/Core/AppEnvironment.swift`
  - 結果: 成功。
- 実行: `swiftc -typecheck Feedman/Core/Models.swift Feedman/Core/APIModels.swift Feedman/Core/APIError.swift Feedman/Core/APIClient.swift Feedman/Core/Auth/TokenStore.swift Feedman/Core/Auth/AuthRepository.swift Feedman/Core/Pagination/CursorPaginationState.swift Feedman/Core/FeedRepository.swift Feedman/Core/AppEnvironment.swift`
  - 結果: 成功。
- 実行: `xcodebuild -project Feedman.xcodeproj -scheme Feedman -destination 'platform=iOS Simulator,name=iPhone 16' test`
  - 結果: 未実行。現在の環境は active developer directory が `/Library/Developer/CommandLineTools` で、`xcodebuild` が `tool 'xcodebuild' requires Xcode` として失敗した。また iOS Simulator SDK も取得できないため、この環境では XCTest 実行不可。
