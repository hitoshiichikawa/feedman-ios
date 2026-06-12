# Review Notes

<!-- idd-codex:review round=1 model=gpt-5 timestamp=2026-06-12T09:44:14Z -->

## Reviewed Scope

- Branch: `codex/issue-39-impl-feed-item-list-repository-with-filters-a`
- HEAD commit: `f428a03ce6e06ef35425393b6cf2ded2442a4d75`
- Compared to: `develop..HEAD`
- 差分確認: `git diff --stat develop..HEAD`、`git log --oneline develop..HEAD`、`git diff develop..HEAD -- Feedman/Core/FeedRepository.swift`、`git diff develop..HEAD -- FeedmanTests/CrossFeedRepositoryTests.swift`
- 判定カテゴリ: AC 未カバー、missing test、boundary 逸脱

## Verified Requirements

- Requirement 1 — `Feedman/Core/FeedRepository.swift:9` 以降で feed-specific first/next page contract を追加し、`APIClientFeedRepository` は `:356` 以降と `:441` 以降で `GET /api/feeds/{id}/items` を shared `APIClient` 経由で呼ぶ。snapshot は `FeedItemPaginationSnapshot` として `items` / `nextCursor` / `canLoadMore` / `feedID` / `filter` / `limit` を返す。
- Requirement 2 — `FeedItemFilter` は `:158` 以降で `all` / `unread` / `starred` の typed enum として定義され、`:447` 以降で `filter` query item に反映される。first page 再読み込み時は `:366` 以降で pagination state を reset し、旧 filter の items を append しない。
- Requirement 3 — first page は `cursor` なし、normalized `limit` 付きで取得され、成功時に `applyFirstPage` で置換される。失敗時は `APIClient` の error がそのまま throw され、空成功には変換されない。
- Requirement 4 — next page は `:387` 以降で成功済み session を要求し、同じ `feedID` / `filter` / `limit` と保存済み cursor で取得して append する。first page 前は typed error、終端後は network request なし、失敗時は state 更新前に throw される。
- Requirement 5 — `CursorPaginationState` の共有挙動により `has_more == false`、`next_cursor == nil`、`next_cursor == ""` が終端になる。limit は `CrossFeedPageLimit.normalized` により default `50`、maximum `200`、非正値は `50` に正規化される。
- Requirement 6 — `MockFeedRepository` は `:628` 以降で feed-specific first/next page を実装し、`:694` 以降で feed id と filter に基づく deterministic な mock page を生成する。
- Requirement 7 — `FeedmanTests/CrossFeedRepositoryTests.swift:168` 以降で request path / method / bearer auth / filter / limit / cursor なし、filter change、next page cursor append、terminal no-request、first page 前 typed error、nil/empty cursor terminal、auth/transport error propagation、mock filter/pagination がテストされている。

## Findings

なし

## Summary

指定の必須 read 対象を確認した。`docs/specs/39-feed-item-list-repository-with-filters-a/tasks.md` と `docs/specs/39-feed-item-list-repository-with-filters-a/design.md` は存在しなかったため、task/design 由来の追加境界照合は実施できない。差分は `Feedman/Core/FeedRepository.swift`、`FeedmanTests/CrossFeedRepositoryTests.swift`、対象 spec dir の `requirements.md` / `impl-notes.md` に閉じており、今回の判定カテゴリ内で reject すべき AC 未カバー、missing test、boundary 逸脱は見当たらない。

検証として `xcodebuild -project Feedman.xcodeproj -scheme Feedman -destination 'platform=iOS Simulator,name=iPhone 16' test` を実行したが、active developer directory が `/Library/Developer/CommandLineTools` のため `tool 'xcodebuild' requires Xcode` で失敗した。代替で `xcrun swiftc -typecheck -parse-as-library Feedman/Core/APIModels.swift Feedman/Core/APIError.swift Feedman/Core/APIClient.swift Feedman/Core/Models.swift Feedman/Core/Pagination/CursorPaginationState.swift Feedman/Core/FeedRepository.swift` は成功した。

RESULT: approve
