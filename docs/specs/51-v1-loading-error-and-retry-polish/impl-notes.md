# Issue #51 v1 loading error and retry polish 実装メモ

## Implementation Notes

### Task 1

Baseline audit として、実装変更は行わず、既存の DesignSystem primitive、v1 主要画面の ViewModel/View、関連 XCTest の loading / empty / error / retry / transient feedback / stale async response 対策を確認した。

採用方針:

- 既存の `FeedmanLoadingView`、`FeedmanCompactLoadingRow`、`FeedmanEmptyStateView`、`FeedmanRecoverableErrorView`、`FeedmanToast`、`FeedmanBannerView`、`FeedmanSheetShell` を継続利用する。DesignSystem は API error code を inspect しておらず、error mapping は Feature/ViewModel 側に閉じている。
- Timeline / Feed / Starred / Search / ArticleDetail は、画面ごとの state enum と operation-specific retry を維持する。共通 state machine へ置換する必要はない。
- Mutation failure は既存 `ItemStateCoordinator` と feature-local message/banner で扱い、sheet / route / visible list を保持する方針を継続する。
- Stale async response 対策は、Feed の `Session` / pending first-page、Search の `currentRequestID` と task cancellation、Drawer subscriptions の `loadGeneration` を中心に既存実装を活かす。

確認できた主な coverage:

- Timeline は initial loading / empty / error retry、refresh failure preservation、next-page retry、star rollback が実装・テスト済み。
- Feed list は filter empty、status banner、manual refresh cooldown (`retry_after_seconds` / `Retry-After` fallback)、manual refresh failure preservation、pagination retry、feed/filter 変更中の stale next-page response 抑制が実装・テスト済み。
- Starred は initial / refresh / pagination、unstar failure restore、auth-required boundary が実装・テスト済み。
- Search は suggestions / loading / empty / failed retry、auth-required boundary、query preservation、古い検索 response の破棄が実装・テスト済み。
- Article detail は summary + loading、detail failure retry、read/star mutation rollback、invalid original-link feedback が実装・テスト済み。
- RegisterFeed は submit loading、input preservation、duplicate / invalid URL / rate-limit / network / auth-required mapping、success event の一回配送が実装・テスト済み。
- AppShell drawer は subscriptions loading / empty / failed retry、既存 feed preservation、登録後 refresh failure preservation、latest reload wins が実装・テスト済み。
- Login / auth restoration は duplicate login prevention、cancel/failure retryable state、restore failure で credential clear + unauthenticated transition が実装・テスト済み。

残存課題 / 後続 task 候補:

- Timeline / Feed の list 系 ViewModel は `FeedmanAPIError.authRequired` を初回/refresh/pagination で明示的な auth boundary に渡していない。後続 auth-required handling task で確認・補強する。
- Starred / Search / ArticleDetail の auth-required failed state は callback を呼ぶ一方で retry button も表示する。再ログイン誘導との二重導線が意図通りか後続 task で整理する。
- SubscriptionSettings は save failure の selection preservation はテスト済みだが、resume / unsubscribe failure で confirmation context と sheet state を保持する観点のテストが薄い。
- Account logout は現状 placeholder で、実 logout の in-flight / failure / local clear policy は未接続。logout 実装接続後に Issue #51 の polish 対象として再確認が必要。
- Drawer 内の global route は Timeline / Starred / Account / feed registration があり、Search は toolbar 経由で利用できるが drawer entry としては存在しない。design.md の「Drawer subscriptions 中も Search など global entries が利用可能」との読み合わせが必要。
- ArticleDetail の original-link open は URL validation と Safari presentation までで、`SFSafariViewController` 側の表示失敗は現行 presenter 境界では検知できない。広い presenter redesign は task 1 scope 外。
- Timeline には route/feed/query 相当の request session key がなく、初回/refresh overlap は duplicate guard に依存している。実害は限定的だが、route 変更後 stale response の横断 test coverage としては Feed/Search/Drawer より薄い。

検証:

- `plutil -lint Feedman.xcodeproj/project.pbxproj`: 成功。
- `git diff --check`: 成功。
- `xcodebuild -project Feedman.xcodeproj -scheme Feedman -destination 'platform=iOS Simulator,name=iPhone 16' test`: 実行不可。`xcode-select` の active developer directory が `/Library/Developer/CommandLineTools` で、Xcode 本体ではないため。

### Task 2

採用方針: DesignSystem に API error 非依存の `FeedmanRetryDescriptor` を追加し、既存 `FeedmanRecoverableErrorView` の retry 表示補助として後方互換で接続した。

重要な判断:

- `FeedmanFeedbackPresentation` 相当の toast/banner 共通値型は追加しない。既存の `FeedmanToastCenter` は current toast を置換する deterministic policy を持ち、banner/local message も feature-local state で単一表示に収まっているため。
- `FeedmanRetryDescriptor` は label / accessibilityLabel / isEnabled だけに絞り、`FeedmanAPIError` や endpoint code の inspect は引き続き Feature/ViewModel 側に閉じた。
- Timeline / Feed / Starred / Search / ArticleDetail / Account の初回 recoverable retry は、ボタン表示名を変えずに画面固有の VoiceOver label を渡す形へ揃えた。

残存課題: なし。auth-required の二重導線整理や画面別 mutation polish は後続 task の scope で扱う。

Finding Closure Matrix:

| Target requirement | Category | Required Action | Fix commit | Test/assertion | Verification result | Notes / no-change reason |
|--------------------|----------|-----------------|------------|----------------|---------------------|--------------------------|
| boundary:tasks.md | boundary 逸脱 | task 2 の review range から `73c5336` 相当の `tasks.md` 正規化差分を除外し、許可された task 2 marker commit では task 2 checkbox の `[ ]` から `[x]` への変更だけにする。 | `4d1ec21 docs(tasks): undo issue 51 marker normalization`; `docs(tasks): mark 2 as done` | `git diff e9d2ca66016a15873e22de25599af01d43f24065..HEAD -- docs/specs/51-v1-loading-error-and-retry-polish/tasks.md` で task 1 / 3〜12 の marker 行追加と task 10 文言変更が残らず、task 2 完了行だけが残ることを確認。 | `plutil -lint Feedman.xcodeproj/project.pbxproj`: 成功。`git diff --check`: 成功。`xcodebuild -project Feedman.xcodeproj -scheme Feedman -destination 'platform=iOS Simulator,name=iPhone 16' test`: CommandLineTools active directory のため実行不可。 | reset / rebase 禁止のため既存 commit は温存し、打ち消し commit で非 canonical な spec artifact 差分を除去した。実装 code / test 変更は不要。 |

検証:

- `plutil -lint Feedman.xcodeproj/project.pbxproj`: 成功。
- `git diff --check`: 成功。
- `xcodebuild -project Feedman.xcodeproj -scheme Feedman -destination 'platform=iOS Simulator,name=iPhone 16' test`: 実行不可。`xcode-select` の active developer directory が `/Library/Developer/CommandLineTools` で、Xcode 本体ではないため。

### Task 3

採用方針: Timeline の production 実装は既に `FeedmanLoadingView`、`FeedmanEmptyStateView`、`FeedmanRecoverableErrorView`、`FeedmanBannerView`、`FeedmanCompactLoadingRow` に揃っていたため、挙動変更ではなく `TimelineViewModelTests` の不足 assertion を追加して regression を固定した。

重要な判断:

- `retryInitialLoad()` は既存テストで first-page のみを 2 回呼ぶことが固定済みだったため、追加実装は不要と判断した。
- `retryNextPage()` は next-page failure 後に `.nextPage` だけを再実行し、first-page session を reset しないことを call sequence で明示した。
- refresh failure は既存 items と `canLoadMore` を保持し、`refreshErrorMessage` で non-destructive feedback を出す既存 test coverage を維持した。
- star mutation failure は `selectedItemID` を保持する assertion を追加した。
- detail sheet 由来の read mutation failure は `ItemStateCoordinator` 共有下で Timeline の `selectedItemID` と loaded detail を保持し、既読 rollback と read failure message を出すことを追加テストで固定した。

残存課題: Task 3 範囲ではなし。Timeline の auth-required boundary 整理は task 8 の scope として扱う。

Finding Closure Matrix:

| Target requirement | Category | Required Action | Fix commit | Test/assertion | Verification result | Notes / no-change reason |
|--------------------|----------|-----------------|------------|----------------|---------------------|--------------------------|
| review-notes.md | review | 現行 review は approve / 追加 finding なしのため、reject finding の修正は不要。 | なし | なし | 追加 finding なしを確認。 | Task 3 learning として reject finding なしを記録した。 |
| boundary:tasks.md | marker correction | task 3 配下の子チェックを一括完了にした非 canonical marker を打ち消し、task 3 aggregate marker のみを終端 marker にする。 | `docs(tasks): restore task 3 marker granularity`; `docs(tasks): mark 3 as done` | `git diff HEAD~1..HEAD -- docs/specs/51-v1-loading-error-and-retry-polish/tasks.md` で task 3 aggregate marker の 1 行だけが `[ ]` から `[x]` になることを確認。 | `plutil` / `git diff --check` は成功。`xcodebuild` は CommandLineTools active directory のため実行不可。 | reset / rebase 禁止のため既存 commit は温存し、打ち消し commit と最新 marker commit で終端を正規化した。 |
| Timeline retry semantics | coverage | `retryNextPage()` が next-page request のみを再実行することを明示する。 | `test(timeline): cover timeline retry and mutation preservation` | `testNextPageFailurePreservesExistingItemsAndShowsRetryableError` の call sequence assertion。 | `plutil` / `git diff --check` は成功。`xcodebuild` は CommandLineTools active directory のため実行不可。 | `retryInitialLoad()` は既存 `testInitialLoadFailureCanRetryFirstPage` で first-page のみを固定済み。 |
| Timeline mutation navigation preservation | coverage | read/star mutation failure が selected item と sheet/list state を失わないことを明示する。 | `test(timeline): cover timeline retry and mutation preservation` | `testStarToggleFailureRollsBackEffectiveStateAndShowsError` の `selectedItemID` assertion と `testDetailReadFailurePreservesTimelineSelectionAndLoadedDetail`。 | `plutil` / `git diff --check` は成功。`xcodebuild` は CommandLineTools active directory のため実行不可。 | production 実装は `ItemStateCoordinator` rollback と feature-local banner を継続利用。 |

検証:

- `plutil -lint Feedman.xcodeproj/project.pbxproj`: 成功。
- `git diff --check`: 成功。
- `xcodebuild -project Feedman.xcodeproj -scheme Feedman -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:FeedmanTests/TimelineViewModelTests test`: 実行不可。`xcode-select` の active developer directory が `/Library/Developer/CommandLineTools` で、Xcode 本体ではないため。
- `xcodebuild -project Feedman.xcodeproj -scheme Feedman -destination 'platform=iOS Simulator,name=iPhone 16' test`: 実行不可。理由は同上。

### Task 4

採用方針: Feed list の production 実装は既に shared primitive と feature-local feedback に沿っていたため、挙動変更ではなく `FeedViewModelTests` の不足 assertion を追加して regression を固定した。

重要な判断:

- filter 別 empty state は `FeedViewModel.emptySubtitle` と `.empty` state の組み合わせで表示しているため、未読 / スター filter の空結果と文言を同一テストで固定した。
- `retryNextPage()` は first-page reload を行わず `.nextPage` だけを再実行し、既存 items / `canLoadMore` / `.loaded` state を保持することを call sequence で明示した。
- manual refresh generic failure と star mutation failure は、既存 list、pagination state、selected item を保持し、`FeedmanBannerView` に渡る feature-local message を出す既存方針を継続した。

残存課題: Task 4 範囲ではなし。Feed の `FeedmanAPIError.authRequired` boundary 整理は task 8 の scope として扱う。

Finding Closure Matrix:

| Target requirement | Category | Required Action | Fix commit | Test/assertion | Verification result | Notes / no-change reason |
|--------------------|----------|-----------------|------------|----------------|---------------------|--------------------------|
| boundary:tasks.md | boundary 逸脱 | `30ffca3 docs(tasks): add task 4 marker row` が追加した非 canonical な task 4 aggregate marker 行を打ち消し、最新終端 marker は空 commit で置く。 | `docs(tasks): remove noncanonical task 4 marker row`; `docs(tasks): mark 4 as done` | `git diff d7b0c4d904458448ec381e77500c003561499d50..HEAD -- docs/specs/51-v1-loading-error-and-retry-polish/tasks.md` で非 canonical marker 行の削除だけを確認。 | `plutil -lint Feedman.xcodeproj/project.pbxproj`: 成功。`git diff --check`: 成功。`xcodebuild -project Feedman.xcodeproj -scheme Feedman -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:FeedmanTests/FeedViewModelTests test`: CommandLineTools active directory のため実行不可。 | reset / rebase 禁止のため既存 commit は温存し、打ち消し commit と空の最新 marker commit で review range 終端を正規化する。code / test 変更は不要。 |
| Feed filter empty state | coverage | filter 別 empty state の文言と表示条件を固定する。 | `test(feed): cover feed list polish preservation` | `testFilterSpecificEmptyStateUsesSelectedFilterCopy` で unread / starred の `.empty` state と subtitle を確認。 | `plutil` / `git diff --check` は成功。`xcodebuild` は CommandLineTools active directory のため実行不可。 | production 実装は `FeedmanEmptyStateView` と `emptySubtitle` を継続利用。 |
| Feed next-page retry semantics | coverage | next-page failure retry が first-page session を reset せず next-page のみを再実行することを明示する。 | `test(feed): cover feed list polish preservation` | `testNextPageFailurePreservesExistingItemsAndShowsRetryableError` の `.loaded` / `canLoadMore` / call sequence assertion。 | `plutil` / `git diff --check` は成功。`xcodebuild` は CommandLineTools active directory のため実行不可。 | production 実装は `retryNextPage()` -> `loadNextPageIfNeeded()` を継続利用。 |
| Feed mutation and refresh preservation | coverage | manual refresh generic failure と star mutation failure が navigation/list state を失わないことを明示する。 | `test(feed): cover feed list polish preservation` | `testManualRefreshGenericErrorPreservesItemsAndShowsFailureGuidance` の `.loaded` / `canLoadMore` assertion と `testStarToggleFailureRollsBackEffectiveStateAndShowsError` の `selectedItemID` assertion。 | `plutil` / `git diff --check` は成功。`xcodebuild` は CommandLineTools active directory のため実行不可。 | `FeedStatusBannerDescriptor` と cooldown retry-after coverage は既存テストで確認済みのため production 変更なし。 |

検証:

- `plutil -lint Feedman.xcodeproj/project.pbxproj`: 成功。
- `git diff --check`: 成功。
- `xcodebuild -project Feedman.xcodeproj -scheme Feedman -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:FeedmanTests/FeedViewModelTests test`: 実行不可。`xcode-select` の active developer directory が `/Library/Developer/CommandLineTools` で、Xcode 本体ではないため。

### Task 5

採用方針: Starred の production 実装は既に `FeedmanLoadingView`、`FeedmanEmptyStateView`、`FeedmanRecoverableErrorView`、`FeedmanBannerView`、`FeedmanCompactLoadingRow` を Timeline / Feed と同じ構成で利用していたため、挙動変更ではなく `StarredViewModelTests` の不足 assertion を追加して regression を固定した。

重要な判断:

- 初回 loading は suspended repository で first-page request を停止し、`.loading` と空 items が request 中に見えることを固定した。
- refresh failure は既存 starred items と `canLoadMore` を保持し、`refreshErrorMessage` で non-destructive feedback を出す既存方針を継続した。
- next-page failure retry は `.nextPage` だけを再実行し、first-page reload / pagination reset を起こさないことを call sequence で明示した。
- unstar failure は削除済み item を元の index に restore し、starred effective state と failure feedback を保つことを確認した。
- auth-required は初回 / refresh / next-page で `onAuthRequired` を呼び、previous loaded / empty state へ残らず `.failed(..., isAuthRequired: true)` へ遷移する既存方針を固定した。

残存課題: Task 5 範囲ではなし。auth-required 失敗画面で retry button も表示される二重導線の整理は、既存 Task 1 の残存課題どおり task 8 の scope で扱う。

Finding Closure Matrix:

| Target requirement | Category | Required Action | Fix commit | Test/assertion | Verification result | Notes / no-change reason |
|--------------------|----------|-----------------|------------|----------------|---------------------|--------------------------|
| boundary:tasks.md | boundary 逸脱 | `68e2985 docs(tasks): restore issue 51 per-task markers` が追加した task 5 以外の aggregate marker 行と task 10 文言変更を打ち消し、task 5 の完了行だけが残る状態へ戻す。 | `docs: close task 5 review boundary findings`; `docs(tasks): mark 5 as done` | `git diff 29264b90f9b8ad27cc2ef800f856854f2d7cd09c -- docs/specs/51-v1-loading-error-and-retry-polish/tasks.md` で task 5 完了行の追加だけが残ることを確認。 | `plutil -lint Feedman.xcodeproj/project.pbxproj`: 成功。`git diff --check`: 成功。`xcodebuild -project Feedman.xcodeproj -scheme Feedman -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:FeedmanTests/StarredViewModelTests test`: CommandLineTools active directory のため実行不可。 | reset / rebase 禁止のため既存 commit は温存し、打ち消し commit と最新 marker commit で review range 終端を正規化する。 |
| boundary:review-notes.md | boundary 逸脱 | `744800e chore(watcher): preserve terminal diagnostics for #51` が追加した task 4 review 内容を task 5 range から打ち消す。 | `docs: close task 5 review boundary findings`; `docs(tasks): mark 5 as done` | `git diff 29264b90f9b8ad27cc2ef800f856854f2d7cd09c -- docs/specs/51-v1-loading-error-and-retry-polish/review-notes.md` で差分が残らないことを確認。 | `plutil -lint Feedman.xcodeproj/project.pbxproj`: 成功。`git diff --check`: 成功。`xcodebuild -project Feedman.xcodeproj -scheme Feedman -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:FeedmanTests/StarredViewModelTests test`: CommandLineTools active directory のため実行不可。 | reviewer notes の reject 内容はこの Task 5 Finding Closure Matrix に転記し、task scope 外 artifact は残さない。 |
| Starred initial state | coverage | 初回 loading / empty / failed retry が shared primitive 方針に沿うことを ViewModel state と retry call sequence で固定する。 | `test(starred): cover starred polish preservation` | `testInitialLoadShowsLoadingWhileRepositoryIsInFlight`、既存 `testInitialLoadEmptyPageExposesEmptyState`、`testInitialLoadFailureCanRetryFirstPage`。 | `plutil` / `git diff --check` は成功。`xcodebuild` は CommandLineTools active directory のため実行不可。 | production View は既に Timeline / Feed と同じ primitive 構成のため変更なし。 |
| Starred refresh / pagination preservation | coverage | refresh failure が既存 items / pagination state を保持し、next-page retry が pagination reset を起こさないことを明示する。 | `test(starred): cover starred polish preservation` | `testRefreshFailurePreservesExistingItems` の `canLoadMore` assertion と `testNextPageFailurePreservesExistingItemsAndShowsRetryableError` の call sequence assertion。 | `plutil` / `git diff --check` は成功。`xcodebuild` は CommandLineTools active directory のため実行不可。 | `retryNextPage()` は `loadNextPageIfNeeded()` に閉じ、first-page request を呼ばない既存実装を維持。 |
| Starred unstar failure / auth-required | coverage | unstar failure の元位置 restore と feedback、auth-required が stale success / empty として表示されないことを固定する。 | `test(starred): cover starred polish preservation` | `testUnstarFailureRestoresItemAndShowsNonBlockingError`、`testRefreshAuthRequiredDoesNotTreatExistingItemsAsCurrentSuccess`、`testRefreshAuthRequiredDoesNotLeavePreviousEmptyStateVisible`、既存 initial / next-page auth-required tests。 | `plutil` / `git diff --check` は成功。`xcodebuild` は CommandLineTools active directory のため実行不可。 | auth-required の最終導線整理は task 8 scope。 |

検証:

- `plutil -lint Feedman.xcodeproj/project.pbxproj`: 成功。
- `git diff --check`: 成功。
- `xcodebuild -project Feedman.xcodeproj -scheme Feedman -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:FeedmanTests/StarredViewModelTests test`: 実行不可。`xcode-select` の active developer directory が `/Library/Developer/CommandLineTools` で、Xcode 本体ではないため。

### Task 6

採用方針: Search / ArticleDetail の production 実装は既に shared primitive と feature-local state に沿っていたため、挙動変更ではなく `GlobalSearchViewModelTests` と `ArticleDetailViewModelTests` の不足 assertion を追加して regression を固定した。

重要な判断:

- Search は suggestions / loading / empty / failed retry / auth-required / stale response が既存 coverage 済みだったため、retry 時の query 保持と、選択した detail load が失敗しても search results を empty に戻さないことを追加で固定した。
- ArticleDetail は summary 付き loading を pending repository で確認し、detail read/star mutation failure が `.loaded` state と sheet-local feedback を維持する assertion を追加した。
- original-link open は invalid URL の feedback までは既存テストで固定済みだが、`SFSafariViewController` presentation 後の表示失敗は現行 `ArticleDetailSafariView` 境界では検知できないため production 変更しない。

残存課題: `SFSafariViewController` 側の表示失敗検知が必要になった場合は presenter 境界の redesign が必要。Task 6 範囲ではなし。

Finding Closure Matrix:

| Target requirement | Category | Required Action | Fix commit | Test/assertion | Verification result | Notes / no-change reason |
|--------------------|----------|-----------------|------------|----------------|---------------------|--------------------------|
| review-notes.md | review | 現行 review は task 5 approve / 追加 finding なしのため、reject finding の修正は不要。 | なし | なし | 追加 finding なしを確認。 | Task 6 learning として reject finding なしを記録した。 |
| Search retry / detail failure preservation | coverage | Search retry が最後に submit 済みの query を維持し、detail error が search results を empty に戻さないことを固定する。 | `test(search): cover search detail polish preservation` | `testFailureStateIsDistinctFromEmptyAndRetryUsesSameQuery` の query assertion と `testSelectedDetailFailureDoesNotClearSearchResults`。 | `plutil` / `git diff --check` は成功。`xcodebuild` は CommandLineTools active directory のため実行不可。 | production 実装は `GlobalSearchViewState.activeQuery` と search/detail の独立 ViewModel state を継続利用。 |
| ArticleDetail loading / mutation preservation | coverage | summary loading と read/star mutation failure 後の loaded sheet state 保持を固定する。 | `test(search): cover search detail polish preservation` | `testOpenShowsSummaryLoadingWhileDetailRequestIsInFlight`、`testReadMarkingFailureDoesNotBlockLoadedDetail`、`testStarFailureKeepsDeterministicFinalStateAndSurfacesMessage`。 | `plutil` / `git diff --check` は成功。`xcodebuild` は CommandLineTools active directory のため実行不可。 | production 実装は `ArticleDetailViewState.loading(summary:)`、`FeedmanBannerView`、`ItemStateCoordinator` rollback を継続利用。 |
| ArticleDetail original-link failure | boundary | 現行 presenter で検知可能な invalid URL feedback を確認し、Safari 表示後 failure は follow-up として記録する。 | なし | 既存 `testOpenOriginalWithInvalidURLReturnsNilAndDoesNotMarkRead`。 | `plutil` / `git diff --check` は成功。`xcodebuild` は CommandLineTools active directory のため実行不可。 | `SFSafariViewController` presentation failure を返す IF がないため、Task 6 では doc-only follow-up とした。 |

検証:

- `plutil -lint Feedman.xcodeproj/project.pbxproj`: 成功。
- `git diff --check`: 成功。
- `xcodebuild -project Feedman.xcodeproj -scheme Feedman -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:FeedmanTests/GlobalSearchViewModelTests -only-testing:FeedmanTests/ArticleDetailViewModelTests test`: 実行不可。`xcode-select` の active developer directory が `/Library/Developer/CommandLineTools` で、Xcode 本体ではないため。

### Task 7

採用方針: RegisterFeed / SubscriptionSettings / Account の production 実装は既に user input、sheet context、loaded account state を保持する方針に沿っていたため、挙動変更ではなく不足していた failure preservation と auth-required の assertion を追加して regression を固定した。

重要な判断:

- RegisterFeed は URL 入力保持、duplicate / invalid URL / rate-limit / network / generic / auth-required の表示文言が既存テストで固定済みだったため変更しない。
- SubscriptionSettings は save failure の選択値保持に加え、resume failure が stopped/error status を維持し、unsubscribe failure が confirmation boundary と unsubscribe event 未発火を維持することを追加した。
- Account は current-user auth-required と delete auth-required を generic failure と区別し、退会未完了時に loaded user state と session completion 未実行を維持することを追加した。

残存課題: Task 7 範囲ではなし。

Finding Closure Matrix:

| Target requirement | Category | Required Action | Fix commit | Test/assertion | Verification result | Notes / no-change reason |
|--------------------|----------|-----------------|------------|----------------|---------------------|--------------------------|
| Forms/settings/account mutation preservation | coverage | settings resume / unsubscribe failure と account deletion auth failure が context を失わないことを固定する。 | `test(forms): cover settings account polish preservation` | `testResumeFailurePreservesStoppedStatusAndShowsFailure`、`testUnsubscribeFailureKeepsConfirmationAndDoesNotPublishEvent`、`testConfirmDeleteAccountAuthRequiredPreservesLoadedUserAndDoesNotCompleteSession`。 | selected `xcodebuild` で 47 tests 成功。 | production 実装は既存の feature-local state を継続利用。 |
| RegisterFeed failure guidance | coverage review | URL 入力保持と主要 error mapping の既存 coverage を確認する。 | なし | 既存 `RegisterFeedViewModelTests`。 | selected `xcodebuild` で関連なし。最終 full test で確認予定。 | 既存 coverage が Issue #51 要件を満たしていたため変更なし。 |

検証:

- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Feedman.xcodeproj -scheme Feedman -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:FeedmanTests/SubscriptionSettingsViewModelTests -only-testing:FeedmanTests/AccountViewModelTests -only-testing:FeedmanTests/AppShellDrawerFeedStateTests test`: 成功。

### Task 8

採用方針: Auth-required は route owner callback を持つ画面では callback 発火、callback がない sheet/account では visible auth guidance として扱う既存 policy を維持し、不足していた SubscriptionSettings / Account の assertion を追加した。

重要な判断:

- Timeline / Feed / Starred / Search / ArticleDetail は既存テストで auth-required callback または auth-specific failed state が固定済み。
- RegisterFeed は `RegisterFeedViewModel.errorPresentation` が `.authRequired` として表示文言を返す既存テストがあったため変更しない。
- SubscriptionSettings は callback 境界を持たない sheet のため、`.authRequired` presentation を generic error と区別するテストを追加した。
- Account は current-user load と account deletion の両方で auth-expired guidance を固定した。

残存課題: Task 8 範囲ではなし。

Finding Closure Matrix:

| Target requirement | Category | Required Action | Fix commit | Test/assertion | Verification result | Notes / no-change reason |
|--------------------|----------|-----------------|------------|----------------|---------------------|--------------------------|
| Cross-screen auth-required handling | coverage | callback なし画面で auth-required を generic failure に落とさないことを固定する。 | `test(forms): cover settings account polish preservation` | `testAuthRequiredMapsToAuthGuidance`、`testCurrentUserAuthRequiredShowsAuthBoundaryError`、`testConfirmDeleteAccountAuthRequiredPreservesLoadedUserAndDoesNotCompleteSession`。 | selected `xcodebuild` で 47 tests 成功。 | callback あり画面は既存 coverage を継続利用。 |

検証:

- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Feedman.xcodeproj -scheme Feedman -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:FeedmanTests/SubscriptionSettingsViewModelTests -only-testing:FeedmanTests/AccountViewModelTests -only-testing:FeedmanTests/AppShellDrawerFeedStateTests test`: 成功。

### Task 9

採用方針: AppShell drawer、Login、Launch auth restoration、stale response suppression は既存 implementation と tests が概ね揃っていたため、AppShell drawer の loading 中 route preservation だけを追加で固定した。

重要な判断:

- Drawer subscriptions は failure 時の global route usability と既存 feed row preservation が既存テストで固定済みだったため、loading 中に既存 feeds を表示しながら global route を選択できる assertion を追加した。
- Login cancel / failure retry と AppEnvironment auth restoration failure は既存テストで retry 可能状態、credential clear、unauthenticated transition を確認済み。
- Feed / filter / search query / selected item 変更後の stale response suppression は Timeline / Feed / Search / drawer registration refresh の既存および追加 coverage で確認した。
- Token / Authorization header / private content を出力する debug log 追加は行っていない。

残存課題: Task 9 範囲ではなし。

Finding Closure Matrix:

| Target requirement | Category | Required Action | Fix commit | Test/assertion | Verification result | Notes / no-change reason |
|--------------------|----------|-----------------|------------|----------------|---------------------|--------------------------|
| Drawer loading route preservation | coverage | subscriptions reload loading 中も global route entries が利用可能であることを固定する。 | `test(appshell): cover drawer loading route preservation` | `testLoadSubscriptionsLoadingWithExistingFeedsKeepsGlobalRoutesUsable`。 | selected `xcodebuild` で 47 tests 成功。 | production 実装は `sectionState = .loading(feeds: currentFeeds)` を継続利用。 |
| Login / auth restoration / stale response | coverage review | 既存 coverage が Issue #51 要件を満たしていることを確認する。 | なし | 既存 `LoginViewModelTests`、`AppEnvironmentSessionRestoreTests`、各 stale response tests。 | 最終 full test で確認予定。 | production 変更なし。 |

検証:

- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Feedman.xcodeproj -scheme Feedman -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:FeedmanTests/SubscriptionSettingsViewModelTests -only-testing:FeedmanTests/AccountViewModelTests -only-testing:FeedmanTests/AppShellDrawerFeedStateTests test`: 成功。

### Task 10

採用方針: 追加子 Issue は作らず、Issue #51 の単一 PR で完結させる。Production 変更は shared primitive の軽微な統一と、各 ViewModel の failure preservation を固定する focused tests に収まっている。

重要な判断:

- Slice 1-5 はこの PR 内で実装 / coverage 確認が完了した。
- Follow-up として残したのは `SFSafariViewController` 表示後 failure の presenter redesign だけで、Issue #51 の blocking scope ではない。
- idd-codex watcher の旧 parser による `tasks.md` marker 破損は実装内容とは独立の運用事故として扱い、最終 PR は手動作成する。

残存課題: 追加子 Issue は不要。

### Task 11

採用方針: Risk が高い loading / retry / refresh / pagination / mutation / auth-required / stale response の観点を ViewModel tests で固定した。最終確認は full `xcodebuild test` で実施する。

重要な判断:

- Slow operation は Timeline / Feed / Starred / ArticleDetail / SubscriptionSettings / Account / AppShell で確認または追加済み。
- Refresh failure preservation は Timeline / Feed / Starred、Search detail failure preservation、AppShell subscriptions failure preservation を確認済み。
- Next-page failure retry は Timeline / Feed / Starred で first-page reset を起こさないことを固定済み。
- Mutation failure navigation preservation は read/star、registration、settings、account で確認済み。
- Cooldown / retry-after message、auth-required boundary、stale response suppression は既存および追加テストで確認済み。

残存課題: Task 11 範囲ではなし。

### Task 12

採用方針: macOS / Xcode 環境で AGENTS.md 指定の iPhone 16 simulator test を実行し、Issue #51 の最終検証を完了した。

検証:

- `plutil -lint Feedman.xcodeproj/project.pbxproj`: 成功。
- `git diff --check`: 成功。
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Feedman.xcodeproj -scheme Feedman -destination 'platform=iOS Simulator,name=iPhone 16' test`: 成功。377 tests、0 failures。

重要な判断:

- Xcode 本体は `/Applications/Xcode.app/Contents/Developer` を明示して利用できたため、実行不可理由の PR 記載は不要。
- Issue #51 は単一 PR に収まるため、追加子 Issue は作成しない。
- `tasks.md` の親 task marker は 1-12 を完了状態へ戻し、旧 watcher が `1 PR` を task ID として誤検出した行は `単一 PR` へ戻した。

残存課題: Task 12 範囲ではなし。
