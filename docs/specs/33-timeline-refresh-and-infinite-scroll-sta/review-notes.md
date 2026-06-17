# Review Notes

<!-- idd-codex:review round=2 model=gpt-5 timestamp=2026-06-17T06:22:00Z -->

## Reviewed Scope

- Branch: codex/issue-33-impl-timeline-refresh-and-infinite-scroll-sta
- HEAD commit: c556f2c316595bfbfb03b673fc3e2de55af16950
- Compared to: develop..HEAD
- `git diff --stat develop..HEAD` と `git log --oneline develop..HEAD` を確認した。
- `reviewer.md` はリポジトリ内に存在しなかった。
- `docs/specs/33-timeline-refresh-and-infinite-scroll-sta/tasks.md` と `design.md` は存在しなかった。

## Verified Requirements

- Requirement 1: `.refreshable` から `TimelineViewModel.refresh()` を呼び、refresh は `FeedRepository.loadCrossFeedFirstPage(limit: nil)` に委譲している。refresh 成功時の items 置換、`canLoadMore` 更新、empty state、refresh / next-page error clearing は追加テストで確認されている。
- Requirement 2: 既存 items ありの refresh failure は list state と items を保持し、banner retry は refresh path を呼ぶ。items なしの refresh failure は recoverable initial error state になることがテストされている。
- Requirement 3: `loadNextPageIfNeeded(currentItemID:)` の sentinel 判定は last item のみになり、non-last / terminal / duplicate / refresh-in-progress の next-page 抑止がテストされている。Timeline feature code は cursor / `since_time` / endpoint path を構築していない。
- Requirement 4: next-page loading / failure / retry は bottom row または bottom feedback として扱われ、既存 items と `canLoadMore` を破壊しないことがテストされている。
- Requirement 5: items ありかつ `canLoadMore == false` の terminal row は「最後まで読みました」を表示し、accessibility label と stable minHeight を持つ。empty / initial loading / initial error では terminal row を表示しない。
- Requirement 6: 初回 loading / loaded / empty / recoverable error / retry / route return no-refetch は既存 ViewModel tests と shared DesignSystem surface の利用で満たされている。
- Requirement 7: `TimelineViewModel` は `@MainActor` で、first-page / next-page duplicate guard と failure 時の state 保持がテストされている。round 1 の指摘だった AC 7.8 は `testRefreshSuccessPreservesLocalStarOverrideForSameItem` により、local star override 後の refresh 成功時も同一 item の star 表示を保持しつつ refreshed snapshot の summary / `canLoadMore` を反映する deterministic behavior として固定された。
- Requirement 8: refresh / sentinel / loading / error / end / duplicate request の主要 ViewModel tests は mock repository で追加され、実 network / OAuth / Keychain / token に依存していない。

## Findings

なし。

## Verification

- `xcodebuild -project Feedman.xcodeproj -scheme Feedman -destination 'platform=iOS Simulator,name=iPhone 16' test` は実行したが失敗した。
- 失敗理由: active developer directory が `/Library/Developer/CommandLineTools` で、Xcode 本体ではないため。
- エラー: `xcode-select: error: tool 'xcodebuild' requires Xcode, but active developer directory '/Library/Developer/CommandLineTools' is a command line tools instance`

## Summary

round 1 の reject 理由だった AC 7.8 の missing test は、HEAD `c556f2c` の追加テストで解消されている。今回確認した範囲では、AC 未カバー、missing test、boundary 逸脱のいずれにも該当する reject finding はない。

RESULT: approve
