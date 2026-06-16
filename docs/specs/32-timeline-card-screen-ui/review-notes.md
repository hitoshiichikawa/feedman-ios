# Issue #32 Timeline card screen UI review notes

<!-- idd-codex:review round=3 model=gpt-5 timestamp=2026-06-16T00:00:00+09:00 -->

## Reviewed Scope

- Branch: codex/issue-32-impl-timeline-card-screen-ui
- HEAD commit: 2f56198e4e3982fa0f989ca618965a075b5a829b
- Compared to: develop..HEAD
- `git diff --stat develop..HEAD` / `git log --oneline develop..HEAD` を取得し、差分が空でないことを確認した。
- `docs/specs/32-timeline-card-screen-ui/tasks.md` と `docs/specs/32-timeline-card-screen-ui/design.md` は存在しなかったため、`requirements.md`、`impl-notes.md`、実装差分、既存実装コード、テストコードを突き合わせて判定した。

## Verified Requirements

- Requirement 1: `.timeline` route は `RootView` から `TimelineView` を表示し、navigation title は `AppShellState` の `すべての新着` を維持している。`TimelineViewModel` は `RootView` の `@StateObject` で保持され、drawer 開閉や同一 shell session 内の route 復帰で状態を維持できる。keyword notification route や Tweak controls は追加されていない。
- Requirement 2: `TimelineViewModel` は `@MainActor` で UI state を管理し、`FeedRepository` protocol の `loadCrossFeedFirstPage(limit:)` / `loadCrossFeedNextPage()` に依存している。初回 success / empty / error、next page failure、重複 load guard、RFC3339 `String` の表示層 formatting を確認した。
- Requirement 3: 初回 loading、empty copy、recoverable error retry、pull-to-refresh、refresh failure banner、near-end pagination、terminal row、bottom loading indicator を確認した。Timeline View / ViewModel は cross-feed query item を構築していない。
- Requirement 4: card は `ArticleSourceRow`、`ArticleHatebuCountControl`、`ArticleStarControl`、`ArticleOpenLinkControl`、`FeedmanTheme` を使用している。favicon は `FeedmanFaviconView` 経由、relative/estimated date、title 3 lines、summary 2 lines と blank omission、hatebu unavailable、star state、valid link、read opacity 0.55 を確認した。
- Requirement 5: card body selection intent は `selectedItemID` / `onSelectItem` に留まり、detail sheet、read mutation、real star mutation sync、cross-screen rollback は追加されていない。star/open-link controls は card body button の外にあり、malformed link は hidden になる。
- Requirement 6: card accessibility label は feed/title/date を含み、star/open-link/hatebu は #26 controls の accessible label と selected/unavailable semantics を再利用している。Dynamic Type / narrow width は line limits と stable control dimensions に沿っている。
- Requirement 7: `TimelineViewModelTests` は initial success / empty / error / retry、route return no-refetch、refresh failure preservation、next page success / failure / retry、terminal no-op、local star behavior、card descriptor derivation、intent separation を検証している。`AppShellDrawerFeedStateTests` は authenticated timeline startup で legacy `crossFeedItems()` を呼ばず、Timeline first page load の 1 経路に集約される regression を検証している。

## Verification

- `plutil -lint Feedman.xcodeproj/project.pbxproj`: 成功。
- `xcodebuild -project Feedman.xcodeproj -scheme Feedman -destination 'platform=iOS Simulator,name=iPhone 16' test`: active developer directory が `/Library/Developer/CommandLineTools` のため実行不可。

## Findings

なし

## カテゴリ別メモ

- AC 未カバー: なし。
- missing test: なし。
- boundary 逸脱: なし。

## Summary

Round 2 の指摘だった AppShell の旧 `crossFeedItems()` と TimelineViewModel の first page load 競合は解消され、regression test も追加されている。許可カテゴリである AC 未カバー / missing test / boundary 逸脱はいずれも検出しなかったため approve とする。

RESULT: approve
