# Review Notes

idd-codex per-task review for Issue 51 task 4

Reviewed Scope

Branch: codex/issue-51-impl-v1-loading-error-and-retry-polish
HEAD commit: d7b0c4d904458448ec381e77500c003561499d50
Compared range: 3bceb8843d5f35a9011f14c5b8567014214bba62..d7b0c4d904458448ec381e77500c003561499d50

Required Command Results

git rev-parse HEAD returned d7b0c4d904458448ec381e77500c003561499d50. HEAD は range_end_sha と一致している。ROUND 1 のため stale range fallback reject は不要。

git diff --stat returned FeedmanTests/FeedViewModelTests.swift, docs/specs/51-v1-loading-error-and-retry-polish/impl-notes.md, docs/specs/51-v1-loading-error-and-retry-polish/tasks.md の 3 files changed, 78 insertions(+), 1 deletion(-).

git log --oneline returned d7b0c4d docs(tasks): mark 4 as done, 30ffca3 docs(tasks): add task 4 marker row, 6924e31 test(feed): cover feed list polish preservation.

git log -1 --format=%s d7b0c4d904458448ec381e77500c003561499d50 returned docs(tasks): mark 4 as done.

Target AC

現行 tasks.md の task 4 には _Requirements:_ numeric ID の注記が存在しない。そのため、task 4 の _Requirements:_ numeric ID に限定した形式上の AC 判定対象は特定できなかった。

参考確認として、task 4 本文に対応する Feed list polish の範囲で Requirement 5.2、Requirement 7.1、Requirement 7.5、Requirement 7.6、Requirement 7.10 に関わる test coverage を確認した。

Tests Checked

FeedmanTests/FeedViewModelTests.swift の追加差分で、filter 別 empty state、next-page failure 後の loaded items / canLoadMore preservation と next-page のみの retry call sequence、manual refresh generic failure 後の loaded state / items / canLoadMore preservation、star mutation failure 後の rollback / selectedItemID preservation / feedback が追加または補強されていることを確認した。

Verification

git diff --check 3bceb8843d5f35a9011f14c5b8567014214bba62..d7b0c4d904458448ec381e77500c003561499d50 は成功した。

plutil -lint Feedman.xcodeproj/project.pbxproj は成功した。

xcodebuild -project Feedman.xcodeproj -scheme Feedman -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:FeedmanTests/FeedViewModelTests test は、active developer directory が /Library/Developer/CommandLineTools で Xcode 本体ではないため実行不可だった。

Marker Classification

d7b0c4d docs(tasks): mark 4 as done は range_end_sha の commit subject が docs(tasks): mark 4 as done に完全一致し、含まれるファイルが tasks.md のみで、task 4 aggregate marker の [ ] から [x] への変更のみだったため、allowed orchestration artifact と分類した。

30ffca3 docs(tasks): add task 4 marker row は range_end_sha ではなく、commit subject も docs(tasks): mark 4 as done に完全一致せず、tasks.md に task 4 aggregate marker 行を新規追加している。この差分は許可された checkbox update ではないため、allowed orchestration artifact ではない。

Findings

AC 未カバー: なし。

missing test: なし。

boundary 逸脱: あり。指定 range に含まれる 30ffca3 docs(tasks): add task 4 marker row が docs/specs/51-v1-loading-error-and-retry-polish/tasks.md に - [ ] 4. Feed list polish 行を新規追加している。per-task marker 契約で許可されるのは range_end_sha の docs(tasks): mark 4 as done が task 4 checkbox を [ ] から [x] に変更する差分のみであり、この追加 commit は subject も diff 形状も canonical marker 条件を満たさない。したがって task boundary 逸脱として reject する。

RESULT: reject
