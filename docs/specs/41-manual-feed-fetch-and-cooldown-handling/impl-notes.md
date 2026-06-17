# Issue #41 実装メモ

## 実装概要

- `FeedRepository` に `manualFetchSubscription(subscriptionID:)` を追加し、real repository では `POST /api/subscriptions/{id}/fetch` を body なしの `sendNoContent` で呼ぶようにした。
- `MockFeedRepository` に手動 fetch の記録と失敗注入を追加した。
- `FeedViewModel` に feed-specific refresh action、重複抑止、refresh feedback、cooldown guidance を追加した。
- 手動 fetch 成功後は、表示中 feed id と現在の `FeedItemFilter` で first page を再読み込みする。cooldown、generic error、reload failure では既存 items を保持する。
- `FeedView` に `.refreshable` を追加し、`feed.id` と `feed.subscriptionID` を ViewModel に渡すようにした。
- Timeline / cross-feed refresh behavior は変更していない。

## 変更ファイル

- `Feedman/Core/FeedRepository.swift`
- `Feedman/Features/Feeds/FeedViewModel.swift`
- `Feedman/Features/Feeds/FeedView.swift`
- `FeedmanTests/SubscriptionActionRepositoryTests.swift`
- `FeedmanTests/CrossFeedRepositoryTests.swift`
- `FeedmanTests/FeedViewModelTests.swift`
- `docs/specs/41-manual-feed-fetch-and-cooldown-handling/requirements.md`
- `docs/specs/41-manual-feed-fetch-and-cooldown-handling/impl-notes.md`

## テスト結果

- `git diff --check`: 成功
- `xcodebuild -project Feedman.xcodeproj -scheme Feedman -destination 'platform=iOS Simulator,name=iPhone 16' test`: active developer directory が `/Library/Developer/CommandLineTools` のため失敗
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Feedman.xcodeproj -scheme Feedman -destination 'platform=iOS Simulator,name=iPhone 16' test`: 成功
  - 301 tests
  - 0 failures

## 確認事項

なし

## PR

PR は作成していない。
