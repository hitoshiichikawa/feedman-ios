# Review Notes

<!-- idd-codex:review round=3 model=gpt-5.5 timestamp=2026-06-18T00:07:22Z -->

## Reviewed Scope

- Branch: codex/issue-37-impl-optimistic-read-and-star-state-synchroni
- HEAD commit: f4c05ccf4e3a6294aee93ba1752e4599cb396553
- Compared to: develop..HEAD

## Verified Requirements

- 1.1-1.4 — `ItemStateCoordinator` が in-memory overlay と `effectiveSummary` / `effectiveDetail` / `effectiveSearchHit` を提供し、visible state を repository data + override から合成。
- 1.5-1.8 — pending/confirmed local value は app session scoped な `RootView` の `@StateObject` 注入で保持し、title/content/link 等は copied model の read/star 以外を維持、global singleton は未追加。
- 2.1-2.4 — `ArticleDetailViewModel.markReadOnOpen` が `beginMutation(... isRead: true)` を repository 完了前に実行し、成功時は `commitMutation` で list/detail の effective read を維持。
- 2.5-2.8 — read failure は `rollbackMutation` と「既読状態を更新できませんでした。」系 message、detail 維持、open-original/search open-link も read sync flow を使用。
- 3.1-3.5 — Timeline/Feed card と ArticleDetail star toggle は shared coordinator 経由で optimistic star を反映し、成功時に confirmed visible state として保持。
- 3.6-3.9 — star failure rollback、non-blocking error、separate card body/open action、same item/star pending 中 disabled を `TimelineViewModel` / `FeedViewModel` / `ArticleStarControl` で確認。
- 4.1-4.5 — read-only は `ItemStateUpdateRequest(isRead: true, isStarred: nil)`、star-only は `ItemStateUpdateRequest(isRead: nil, isStarred: target)` を送る tests が追加済み。
- 4.6-4.9 — View/ViewModel は `ItemRepository.updateItemState` を使い、`URLSession`/Keychain 直触りや endpoint-specific refresh、updated body 要求を追加していない。
- 5.1-5.5 — coordinator が field ごとに previous value/token/pending optimistic value を保持し、token 一致時だけ rollback、read/star independent rollback と stale refresh 中の optimistic 優先を tests で確認。
- 5.6-5.8 — session alive 中の confirmed/effective state と duplicate visible copy convergence は shared coordinator と Timeline/detail cross-visible tests で確認。
- 6.1-6.4 — read/star failure は日本語の non-blocking banner/message/toast 経路を使い、primary navigation や detail dismissal を強制しない。
- 6.5-6.8 — optimistic/pending state は `ArticleStarControl` の selected/value/disabled と card read accessibility value に連動し、既存 responsive layout 内の action row に収まる変更。
- 7.1-7.9 — Timeline/Feed/Search/ArticleDetail は effective state と shared coordinator 注入に接続され、dismiss 時に stale selected detail override を追加していない。
- 7.10 — keyword notification UI、feed-scoped search UI、新 route type は追加されていない。
- 8.1-8.4 — `TimelineViewModelTests` と `ArticleDetailViewModelTests` が card/detail star success/failure、cross-visible sync、rollback/error を検証。
- 8.5-8.8 — detail open read success/failure、read/star overlap rollback、pending stale refresh は `ArticleDetailViewModelTests` と `ItemStateCoordinatorTests` で検証。
- 8.9-8.10 — tests は mock repository/dummy ids を使用。`xcodebuild ... test` は active developer directory が CommandLineTools のため実行不可で、impl-notes に理由記載済み。

## Findings

なし

## Summary

AC 未カバー、missing test、boundary 逸脱はいずれも検出しませんでした。`git diff --check` と `plutil -lint Feedman.xcodeproj/project.pbxproj` は成功、Xcode test は環境都合で実行不可でした。

RESULT: approve
