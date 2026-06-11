# Issue #28 Review Notes

## Summary

- Review round: 1 / max 2
- Target HEAD: `4d4ce69c129de6902b05c6354977c1dda83b82f4`
- `git diff --stat develop..HEAD` は取得済み。差分は `Feedman/Features/AppShell`、`FeedmanTests/AppShellStateTests.swift`、project file、`requirements.md`、`impl-notes.md`。
- `git log --oneline develop..HEAD` は `4d4ce69 feat: add app shell route state and drawer` の 1 commit。
- 指定された `docs/specs/28-route-state-and-custom-drawer-shell/tasks.md` と `design.md` は存在しなかったため、tasks の `_Requirements:_` / `_Boundary:_` と design への照合は不可。`requirements.md`、`impl-notes.md`、実装差分、テスト差分で判定した。
- `xcodebuild -project Feedman.xcodeproj -scheme Feedman -destination 'platform=iOS Simulator,name=iPhone 16' test` は reviewer 環境でも active developer directory が `/Library/Developer/CommandLineTools` のため実行不可。
- `plutil -lint Feedman.xcodeproj/project.pbxproj` は成功。

## Findings

なし。

## Coverage Notes

- AC 未カバー: なし。`AppShellRoute` / `AppShellState` により timeline、starred、feed、search、account の明示 route と drawer open state の独立性が確認できる。`RootView` 側も toolbar title、drawer selected state、scrim dismiss、drawer route selection、search/account placeholder を同じ state から導出している。
- missing test: なし。`AppShellStateTests` は default route、dismiss で route が維持されること、route selection で drawer が閉じること、feed id/title 分離、unknown feed title fallback、同一 route 選択時の close behavior を最小 unit で検証している。SwiftUI gesture/layout は `impl-notes.md` に手動確認ポイントがある。
- boundary 逸脱: なし。実装は AppShell と project-file wiring、AppShell state test に限定され、real subscriptions API、data layer、keyword notification UI、feature-specific business logic は追加されていない。

RESULT: approve
