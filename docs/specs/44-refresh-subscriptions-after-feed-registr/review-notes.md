# Review Notes

<!-- idd-codex:review round=3 model=gpt-5.5 timestamp=2026-06-17T06:35:37Z -->

## Reviewed Scope

- Branch: `codex/issue-44-impl-refresh-subscriptions-after-feed-registr`
- HEAD commit: `2441390384b6c97fa19f8112b4d8da4279d710e8`
- Compared to: `develop..HEAD`
- Diff scope: `AppShellDrawerFeedState.swift`, `RootView.swift`, `RegisterFeedSheet.swift`, `AppShellDrawerFeedStateTests.swift`, `RegisterFeedViewModelTests.swift`, Issue #44 spec notes
- 必読確認: `AGENTS.md`、`requirements.md`、`impl-notes.md`、`.codex/agents/reviewer.md` を確認済み
- `docs/specs/44-refresh-subscriptions-after-feed-registr/tasks.md` は存在しないため、tasks の `_Boundary:_` 注釈による追加判定はできなかった
- `docs/specs/44-refresh-subscriptions-after-feed-registr/design.md` は存在しなかった
- `AGENTS.md` に `## Feature Flag Protocol` 節は見つからなかったため、feature flag opt-in 判定は適用していない

## Verified Requirements

- 1.1 — `RegisterFeedViewModel.submit()` が登録成功時に `successEvent` を発行し、`RegisterFeedSheet` が `.onChange(of: viewModel.successEvent)` で `onRegistered` へ配送する実装を確認した（`RegisterFeedViewModelTests.testSubmitTrimsURLAndPublishesSuccessEvent`、`RegisterFeedSheet.swift:41`）
- 1.2 / 2.1 / 2.2 — `RootView.completeFeedRegistration(_:)` が `refreshSubscriptionsAfterFeedRegistration(_:repository:)` を `Task` で起動し、同 method が `FeedRepository.subscriptions()` を呼ぶことを確認した
- 1.3 / 3.1 — `testRegistrationSuccessEventDeliveryStartsPostRegistrationReloadBeforeCompletionButton` と `testRefreshAfterFeedRegistrationReloadsSubscriptionsAndUsesRepositoryResult` が、登録成功後に app restart なしで reload 結果を drawer state に反映する経路を検証している
- 1.4 / 5.1 — success state の `完了` button は dismissal のみを行い、reload は success event 配送側から開始される実装を確認した（`RegisterFeedSheet.swift:49`、`RootView.swift:329`）
- 1.5 / 7.3 — `testRegistrationDismissWithoutSuccessEventDoesNotStartPostRegistrationReload` と `RegisterFeedViewModelTests.testSubmitFailureKeepsURLEditableAndMapsNetworkError` が、success event 不在または登録失敗時に subscriptions reload が走らないことを検証している
- 1.6 / 3.3 / 3.4 — 登録成功レスポンスは optimistic 表示にのみ使われ、reload 成功時は subscriptions response を source of truth とし、同じ feed id は upsert で重複させない実装を確認した
- 2.3 / 3.2 — reload 成功時に repository result で drawer feeds を置き換え、`route(for:)` が stable feed id と title を `AppShellRoute.feed(id:title:)` に渡すことを test で確認した
- 2.4 / 4.3 / 4.4 / 4.7 / 5.3 / 5.4 — loading / failed state は既存 feeds を保持でき、`DrawerView` の global route 操作や retry 表示を塞がない構造を確認した
- 2.5 / 7.5 — `loadGeneration` と `testLatestSubscriptionReloadWinsWhenRegistrationRefreshesOverlap` により、重複 reload 完了時の最終 drawer state が deterministic であることを確認した
- 2.6 / 6.1 / 6.5 — View は `URLSession`、Keychain、raw endpoint、token refresh を直接扱わず、既存 repository 経由の reload に限定されている
- 3.5 / 5.6 — reload result が登録 feed を含まない場合も repository result または empty state に遷移するだけで crash する経路は見つからなかった
- 3.6 / 5.5 — reload 成功時に current route を強制遷移する差分はなく、既存 route state は維持される
- 4.1 / 4.2 / 4.8 / 5.2 — post-registration reload failure は登録成功 toast と別に `フィードは登録されましたが、一覧を更新できませんでした` の recoverable guidance として表現される
- 4.5 / 4.6 / 7.4 — retry は `RootView` の `onRetryFeeds` から既存 `loadSubscriptions(repository:)` を再実行し、成功時に loaded state へ戻る test を確認した
- 5.7 / NFR 2.3 — keyword notification drawer entries や v1 scope 外 UI を追加する差分は見つからなかった
- 6.2 / 6.3 / 6.4 / 6.6 — Swift Concurrency を使い、AppShell / RegisterFeed / drawer state 境界内に実装が収まり、新規 API contract や日本語 Swift 識別子は追加されていない
- 7.1 / 7.2 / 7.6 / 7.7 — mock repository による success / failure / retry / overlap tests が追加され、実 network、OAuth、Keychain、個人 data、prototype-only preview fields への依存は見つからなかった

## Findings

なし

## AC Coverage

- Covered: 登録成功 event は `RegisterFeedSuccessEvent` と `RegisterFeedSuccessEventDispatcher` を通じて AppShell の `onRegistered` に配送され、`完了` button を押す前に subscriptions reload が開始される。
- Covered: reload は View から raw API を組み立てず、既存 `FeedRepository.subscriptions()` / `AppShellDrawerFeedViewModel.loadSubscriptions(repository:)` 境界を使っている。
- Covered: reload 成功時は subscriptions response を drawer feed list の source of truth とし、新規 feed の row selection は stable feed id と title を使う。
- Covered: reload 失敗時は登録成功 toast と区別した日本語 guidance を failed state に出し、retry で再取得できる。
- Covered: 複数 registration success / reload overlap では `loadGeneration` により最後に開始された reload の結果だけが state を確定する。
- Covered: Issue #44 の責務外である API contract 変更、keyword notification UI、OPML、subscription settings の再定義、feed-scoped search UI 追加は見つからなかった。
- Not covered: なし

## Tests/Verification

- `git diff --stat develop..HEAD`: 差分概要を確認済み。
- `git log --oneline develop..HEAD`: `2441390`、`d26b57d`、`a33be59` を確認済み。
- `git diff develop..HEAD -- <changed files>`: 実装・テスト差分をファイル単位で確認済み。
- `git diff --check develop..HEAD`: 成功。
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Feedman.xcodeproj -scheme Feedman -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:FeedmanTests/AppShellDrawerFeedStateTests -only-testing:FeedmanTests/RegisterFeedViewModelTests test`: 成功。30 tests、0 failures。
- full test suite は reviewer として再実行していない。`impl-notes.md` には同一環境で 298 tests、0 failures と記録されている。

## Summary

前回指摘されていた「登録成功後 refresh が success card の `完了` 操作に依存する」問題は、`successEvent` の `.onChange` 配送と dispatcher により解消されている。対象差分は Issue #44 の AppShell / RegisterFeed / drawer refresh 境界に収まり、AC 未カバー、missing test、boundary 逸脱はいずれも検出しなかった。

RESULT: approve
