# Review Notes

<!-- idd-codex:review round=2 model=gpt-5 timestamp=2026-06-16T10:09:22Z -->

## Summary

- Branch: `codex/issue-47-impl-search-result-to-detail-bridge`
- HEAD commit: `4b4e82a53ae81374885bf858e7bf3e802b37ca12`
- Compared to: `develop..HEAD`
- `git diff --stat develop..HEAD` / `git log --oneline develop..HEAD` で差分を取得済み。差分は空ではない。
- `tasks.md` は存在しないため tasks 照合は実施不能。`design.md` も存在しないため design traceability 照合は実施不能。
- 前回 round=1 の reject 主因だった direct open read marking と失敗時挙動のテスト不足は、`AppShellSearchResultOpenLinkCoordinator` と `AppShellStateTests` の追加で解消されている。
- 判定カテゴリは指定どおり `AC 未カバー` / `missing test` / `boundary 逸脱` に限定した。

## Findings

なし

## AC Coverage

- Requirement 1: 検索結果 tap は `SearchResultRowDescriptor.detailInput` から `ArticleDetailSheetInput` を作り、`AppShellState.presentArticleDetail` と `RootView.sheetContent` 経由で既存 `ArticleDetailSheet` を表示する。invalid id no-op、別 route への遷移時 clear、dismiss 時の検索 route 維持も確認できる。
- Requirement 2: `ArticleDetailSummary(searchHit:)` は nullable fields を nil のまま保持し、`hatebuFetchedAt` を合成しない。`faviconURL` は既存 favicon component 境界に渡され、`AsyncImage(url:)` へ直接渡す差分はない。
- Requirement 3: 検索由来の detail sheet は `ArticleDetailViewModel.open()` で `ItemRepository.updateItemState(isRead: true, isStarred: nil)` と `itemDetail` を既存 repository 境界から呼ぶ。detail failure、read marking failure、auth-required は recoverable / non-blocking state に流れている。
- Requirement 4: open-link は `SearchResultOpenLinkRequest` で item id と URL を保持し、AppShell 側 coordinator が既存 external open boundary と read marking を調停する。invalid URL は request を作らず、open-link と card selection は分離されている。
- Requirement 5: detail sheet の star toggle は `ArticleDetailViewModel` の既存 mutation 経路を使い、成功時だけ `ItemStateChange` を通知して現在 visible な search hits に限定反映する。失敗時に成功状態を final として反映する差分はない。
- Requirement 6: AppShell が search selection、open-link、sheet presentation を調停し、networking logic は repository / ArticleDetail ViewModel 側に残っている。主な編集範囲は Search、ArticleDetail、AppShell、および bridge に必要な Core 型追加に収まっている。
- Requirement 7: search result card には detail 用 accessibility action、open-link control には別 label があり、detail sheet の detent / dismiss / star / retry / open-original 境界は #35 のものを維持している。v1 scope-out UI の追加はない。
- Requirement 8: coordinator presentation、nullable mapping、detail fetch/read marking、detail failure retry、direct open read marking、invalid URL、star reflection、mutation failure の focused XCTest が確認できる。

## Test Review

- 追加・既存テスト: `AppShellStateTests`、`GlobalSearchViewModelTests`、`ArticleDetailViewModelTests` で AC 主要経路を確認している。
- Reviewer 実行: `git diff --check develop..HEAD` 成功。
- Reviewer 実行: `plutil -lint Feedman.xcodeproj/project.pbxproj` 成功。
- Reviewer 実行: `xcrun swiftc -parse ...` 成功。
- Reviewer 実行: `xcodebuild -project Feedman.xcodeproj -scheme Feedman -destination 'platform=iOS Simulator,name=iPhone 16' test` は active developer directory が `/Library/Developer/CommandLineTools` のため実行不可。

## Boundary Review

- `tasks.md` が存在しないため `_Boundary:_` アノテーションによる照合はできなかった。
- 差分は `Feedman/Features/Search/`、`Feedman/Features/ArticleDetail/`、`Feedman/Features/AppShell/`、bridge に必要な `Feedman/Core/AppEnvironment.swift` / `Feedman/Core/Models.swift`、対象テスト、対象 spec dir に限定されている。
- `design/SPEC-iOS.md`、`design/SERVER.md`、prototype、他 Issue の `docs/specs/*` を変更する差分は確認していない。
- `boundary 逸脱` は検出していない。

RESULT: approve
