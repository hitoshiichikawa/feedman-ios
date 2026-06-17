# Issue #42 実装ノート

## 実装概要

- `Feed` に `subscriptionID` と `fetchIntervalMinutes` を追加し、drawer route 用の `Feed.id` は従来どおり `feed_id` として維持した。
- `FeedRepository` に `updateSubscriptionSettings` / `resumeSubscription` / `unsubscribe` を追加し、real repository は以下の endpoint を Bearer auth 付きで呼ぶ。
  - `PUT /api/subscriptions/{id}/settings`
  - `POST /api/subscriptions/{id}/resume`
  - `DELETE /api/subscriptions/{id}`
- `Feedman/Features/Subscriptions/` に `SubscriptionSettingsViewModel` と `SubscriptionSettingsSheet` を追加した。
- current interval が `15/30/60/180/360` 以外の場合は picker を未選択にし、ユーザーが supported interval を選ぶまで保存しない。
- drawer row に設定ボタンを追加し、タップしても feed navigation が発火しないように分離した。
- 購読解除成功時は `Subscription.id` で drawer state からローカル削除し、選択中 feed が削除対象なら route を `すべての新着` に戻す。

## テスト追加

- Repository request:
  - settings PUT の path/header/body
  - resume POST の path/header/no body
  - unsubscribe DELETE の path/header/no body
- ViewModel:
  - unsupported interval の no-op
  - save success/failure/duplicate prevention
  - active feed の resume guard
  - stopped feed の resume success
  - unsubscribe cancel vs confirm
- AppShell/drawer state:
  - settings interval の local update
  - resume status の local update
  - unsubscribe local removal と selected route fallback

## 検証

- `xcodebuild -project Feedman.xcodeproj -scheme Feedman -destination 'platform=iOS Simulator,name=iPhone 16' test`
  - 実行不可。active developer directory が `/Library/Developer/CommandLineTools` で、`xcodebuild` が Xcode 本体を要求したため。
- 代替検証:
  - `swiftc -typecheck Feedman/Core/APIModels.swift Feedman/Core/APIError.swift Feedman/Core/APIClient.swift Feedman/Core/Models.swift Feedman/Core/Pagination/CursorPaginationState.swift Feedman/Core/FeedRepository.swift Feedman/Features/AppShell/AppShellState.swift Feedman/Features/AppShell/AppShellDrawerFeedState.swift Feedman/Features/Subscriptions/SubscriptionSettingsViewModel.swift`
  - `git diff --check`
  - `plutil -lint Feedman.xcodeproj/project.pbxproj`
- UI / XCTest を含む typecheck は CommandLineTools 環境に `UIKit` / `XCTest` module がなく実行不可。

## round=1 reject 是正

- Issue #42 と無関係に削除されていた `docs/specs/32-timeline-card-screen-ui/` と `docs/specs/39-feed-item-list-repository-with-filters-a/` の spec 成果物を `develop` と同等に復元した。
- `Feedman/Features/Timeline/TimelineView.swift`、`Feedman/Features/Timeline/TimelineViewModel.swift`、`FeedmanTests/TimelineViewModelTests.swift` を `develop` と同等に復元した。
- `Feedman.xcodeproj/project.pbxproj` は Subscription settings の追加参照を残しつつ、Timeline source/test の file reference、group、build phase 参照を追加した。
- 追加検証として `git diff --check` と `plutil -lint Feedman.xcodeproj/project.pbxproj` を実行した。`xcodebuild` は active developer directory が CommandLineTools のため引き続き実行不可。
- Timeline を含む UI 依存ファイルの `swiftc -typecheck` も試行したが、CommandLineTools 環境では SwiftUI preview macro plugin を解決できず検証として完了できなかった。

## Debugger 経由再実行 是正

- `Feedman/Core/FeedRepository.swift` を current `develop` の #39 feed-specific repository boundary に合わせて復元し、`FeedItemFilter` / `FeedItemPaginationSnapshot` / `FeedItemRepositoryError`、`APIClientFeedRepository` の `/api/feeds/{id}/items` pagination session、`MockFeedRepository` の deterministic filter/pagination を戻した。
- #42 の `updateSubscriptionSettings` / `resumeSubscription` / `unsubscribe` と、`Feed.subscriptionID` / `fetchIntervalMinutes` mapping は維持した。
- `RootView` は legacy `items` state と startup の `crossFeedItems()` 直接呼び出しを除去し、`TimelineViewModel` + `TimelineView` の route content に戻した。購読設定 sheet、drawer settings affordance、成功時の local update / route fallback は維持した。
- `CrossFeedRepositoryTests` に #39 の feed-specific repository tests/helper を復元し、`AppShellDrawerFeedStateTests` に startup regression test/helper を復元した。#42 の local update/removal/route fallback tests は維持した。
- 検証:
  - `git diff --check`: 成功。
  - `plutil -lint Feedman.xcodeproj/project.pbxproj`: 成功。
  - `swiftc -typecheck Feedman/Core/APIModels.swift Feedman/Core/APIError.swift Feedman/Core/APIClient.swift Feedman/Core/Models.swift Feedman/Core/Pagination/CursorPaginationState.swift Feedman/Core/FeedRepository.swift`: 成功。
  - `swiftc -typecheck Feedman/Core/APIModels.swift Feedman/Core/APIError.swift Feedman/Core/APIClient.swift Feedman/Core/Models.swift Feedman/Core/Pagination/CursorPaginationState.swift Feedman/Core/FeedRepository.swift Feedman/Features/AppShell/AppShellState.swift Feedman/Features/AppShell/AppShellDrawerFeedState.swift Feedman/Features/Subscriptions/SubscriptionSettingsViewModel.swift`: 成功。
  - `xcodebuild -project Feedman.xcodeproj -scheme Feedman -destination 'platform=iOS Simulator,name=iPhone 16' test`: 実行不可。active developer directory が `/Library/Developer/CommandLineTools` で、`xcodebuild` が Xcode 本体を要求したため。
- 残課題: この環境では XCTest / Simulator 実行ができないため、Xcode 本体が有効な macOS 環境で test を再実行する必要がある。
