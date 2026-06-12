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
