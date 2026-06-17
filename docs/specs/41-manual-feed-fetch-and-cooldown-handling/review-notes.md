# Review Notes - Issue #41 - Round 1

## Summary
- `git diff --stat develop..HEAD` と `git log --oneline develop..HEAD` は取得できた。対象は `4b0b684 feat: add manual feed fetch handling` の 1 commit。
- `tasks.md` と `design.md` は指定パスに存在しなかったため、`tasks.md` の `_Requirements:_` / `_Boundary:_` annotation との直接照合は実施できなかった。
- リポジトリ内に `reviewer.md` は見つからなかったため、既存 `review-notes.md` の形式を踏襲した。
- Repository contract、feed-specific `.refreshable`、success reload、cooldown/non-cooldown feedback、mock、主要 unit test は Issue #41 の要件範囲内で実装されていると判断した。

## Diff / Verification
- `git diff --stat develop..HEAD`: 8 files changed, 779 insertions(+), 7 deletions(-)。
- `git log --oneline develop..HEAD`: `4b0b684 feat: add manual feed fetch handling`。
- `git diff --check develop..HEAD`: 成功。
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Feedman.xcodeproj -scheme Feedman -destination 'platform=iOS Simulator,name=iPhone 16' test`: 成功。301 tests, 0 failures。

## Findings
### AC 未カバー
- [なし]

### missing test
- [なし]

### boundary 逸脱
- [なし]

## AC Coverage
- R-1: covered - `FeedRepository.manualFetchSubscription(subscriptionID:)` が追加され、real repository は `POST /api/subscriptions/{id}/fetch` を `APIClient.sendNoContent` 経由で Bearer auth 付き・body なし・2xx body 非依存として扱う。View/ViewModel は raw HTTP parsing や token refresh を実装していない。
- R-2: covered - `FeedView` は feed-specific screen に `.refreshable` を追加し、`feed.subscriptionID` を ViewModel に渡す。ViewModel は missing/blank subscription ID で fetch せず、refresh 重複と first/next page load 競合を deterministic に抑止する。Timeline refresh behavior の変更はない。
- R-3: covered - manual fetch 成功後は現在の `feedID` と `FeedItemFilter` で `loadFeedItemsFirstPage(feedID:filter:limit:)` を呼び、成功 snapshot で items/pagination/empty state を置き換える。reload failure は既存 items を保持して recoverable feedback を出す。
- R-4: covered - `429 / FEED_COOLDOWN` は typed `FeedmanAPIError.feedmanError` から判定し、`details.retry_after_seconds` を優先、`Retry-After` integer を fallback として guidance に含める。cooldown 時は既存 items を保持し、post-fetch reload や auto retry は実行しない。
- R-5: covered - non-cooldown error、transport failure、auth-required failure は refresh-specific feedback に変換され、manual fetch failure 前の visible items/filter/pagination は保持される。auto-loop retry は追加されていない。
- R-6: covered - `FeedViewModel` は `@MainActor` のまま `FeedRepository` protocol に依存し、refresh state/feedback を調停する。refresh handling は RFC3339 string decode や read/star mutation を追加していない。
- R-7: covered - `MockFeedRepository` は requested `subscriptionID` を記録し、manual fetch failure injection と既存 mock pagination behavior を維持している。Preview feed には `subscriptionID` が追加され、real token/secret/personal data は見当たらない。
- R-8: covered - repository tests は POST path/Bearer/no body/2xx success/cooldown metadata を検証し、ViewModel tests は fetch-before-reload、current feed/filter reload、items replacement、cooldown/generic error preservation、missing subscription ID、duplicate refresh suppression を検証している。tests は mock repository / mock transport を使い、real network/OAuth/Keychain/token に依存していない。

## Notes
- `tasks.md` が存在しないため、タスク注釈ベースの境界確認はできなかった。requirements.md の scope / implementation boundary / NFR と差分の範囲では、feed-specific manual fetch and cooldown handling を越える変更は見つからなかった。

RESULT: approve
