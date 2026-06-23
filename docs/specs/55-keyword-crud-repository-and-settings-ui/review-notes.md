# Review Notes

<!-- idd-codex:review round=3 model=gpt-5.5 timestamp=2026-06-22T14:03:24Z -->

## Reviewed Scope

- Branch: codex/issue-55-impl-keyword-crud-repository-and-settings-ui
- HEAD commit: 08dda182f9a40042b2ec47974f5a715503f9a87a
- Compared to: develop..HEAD

## Verified Requirements

- 1.1 — `Feedman/Core/APIModels.swift:239` の `KeywordResponse` と `KeywordRepositoryTests.testKeywordResponseDecodesCanonicalFieldsAndUnknownScope` で `id` / `term` / `scope` / `enabled` / `hits` を保持。
- 1.2 — `KeywordCreateRequest` と `testKeywordCreateRequestEncodesTitleScopeAndEnabled` / `testCreateKeywordPostsRequestBodyWithBearer` で `term` / `scope:"title"` / `enabled` を含む create body を確認。
- 1.3 — `KeywordUpdateRequest` と `testKeywordUpdateRequestEncodesOnlyMutableNonNilFields` / PATCH tests で `term` / `enabled` のみを送信。
- 1.4 — keyword model に Date field / Date decoding を追加せず、server string fields を `String` として保持。
- 1.5 — unknown `scope` を `String` として decode し、`KeywordSettingsRowPresentation` は `scope` に依存せず表示。
- 1.6 — `KeywordListResponse` が bare array / `items` / `keywords` wrapper を repository boundary で吸収。
- 2.1 — `APIClientKeywordRepository.keywords` と `testKeywordsGetsBareArrayWithBearer` で Bearer 付き `GET /api/keywords` を確認。
- 2.2 — `APIClientKeywordRepository.createKeyword` と `testCreateKeywordPostsRequestBodyWithBearer` で Bearer 付き `POST /api/keywords` を確認。
- 2.3 — `testUpdateKeywordPatchesOnlyEditedTermWithBearer` で `PATCH /api/keywords/{id}` の `term` 更新を確認。
- 2.4 — `testToggleKeywordPatchesOnlyEditedEnabledWithBearer` で `PATCH /api/keywords/{id}` の `enabled` 更新を確認。
- 2.5 — `APIClientKeywordRepository.deleteKeyword` と `testDeleteKeywordDeletesWithBearer` で Bearer 付き `DELETE /api/keywords/{id}` を確認。
- 2.6 — `testKeywordRepositoryDelegatesExpiredTokenRefreshToAPIClient` で 401 refresh retry を `APIClient` に委譲。
- 2.7 — `testKeywordRepositoryPreservesFeedmanAPIErrorContext` と ViewModel guidance tests で typed `FeedmanAPIError` context を保持。
- 2.8 — `KeywordSettingsSheet` は injected `KeywordRepository` を使い、View から `URLSession` / Keychain / APNs を直接触らない。
- 3.1 — `KeywordSettingsSheet.task` が `KeywordSettingsViewModel.loadKeywords()` を初回実行。
- 3.2 — `testLoadKeywordsSuccessPreservesRepositoryOrder` で repository response order の loaded list を確認。
- 3.3 — `testLoadKeywordsEmptyShowsEmptyState` で empty state を確認。
- 3.4 — `testInitialLoadFailureShowsRecoverableErrorAndRetryCanLoad` で recoverable error と retry を確認。
- 3.5 — `testVisibleListRefreshFailurePreservesContentAndShowsMessage` と mutation failure tests で visible list preservation を確認。
- 3.6 — `testConcurrentLoadPreventsDuplicateRepositoryCalls` / `testConcurrentCreatePreventsDuplicateRepositoryCalls` で duplicate in-flight guard を確認。
- 3.7 — `testNewViewModelStartsWithoutStaleMessageOrConfirmation` で新規 sheet session の stale state 非漏洩を確認。
- 4.1 — `testCreateWithWhitespaceOnlyTermDoesNotCallRepository` と `testUpdateWithWhitespaceOnlyTermDoesNotCallRepository` で create/edit の whitespace-only 抑止を確認。
- 4.2 — `testCreateTrimsTermAndAppendsServerConfirmedKeyword` / `testUpdateTrimsTermAndReplacesServerConfirmedKeyword` で trim を確認。
- 4.3 — `testDuplicateRateLimitAuthAndNetworkErrorsMapToGuidance` で duplicate guidance を確認。
- 4.4 — 同 test で rate-limit guidance と `retry_after_seconds` 表示を確認。
- 4.5 — initial load / mutation failure tests で network guidance と generic guidance の区別を確認。
- 4.6 — `testAuthRequiredCallsHandler` / `testAuthRequiredDuringVisibleMutationCallsHandlerAndPreservesContent` と `RootView` toast callback で auth-required guidance を確認。
- 4.7 — `testDeleteRequiresConfirmationBeforeRepositoryCall` で explicit confirmation 前の DELETE 抑止を確認。
- 4.8 — toggle/delete failure tests で failed server state を confirmed 表示しないことを確認。
- 5.1 — `AppShellPresentation.keywordSettings` と `RootView.sheetContent` が placeholder ではなく `KeywordSettingsSheet` を表示。
- 5.2 — `KeywordSettingsSheet` が `FeedmanSheetShell` と `.presentationDetents([.medium, .large])` を使用。
- 5.3 — sheet title は「キーワード通知」、subtitle は記事タイトル一致の scope を説明。
- 5.4 — `KeywordSettingsRowPresentation` と row UI が term / enabled / hits count を表示。
- 5.5 — sheet UI が add / edit / toggle / delete controls を ViewModel actions に接続。
- 5.6 — operation state により affected controls を disabled/progress 表示。
- 5.7 — `FeedmanTheme` と shared primitives を使用。
- 5.8 — #55 sheet 側に server worker / delivery diagnostics / feed-scoped search / OPML / body matching controls は見当たらない。
- 6.1 — drawer footer に「キーワード通知」entry point を追加。
- 6.2 — `presentKeywordSettings()` が drawer を閉じて `.keywordSettings` を設定。
- 6.3 — `testPresentingKeywordSettingsClosesDrawerAndPreservesCurrentRoute` で current route preservation を確認。
- 6.4 — `KeywordSettingsSheet` の auth-required callback が `RootView` toast guidance に接続。
- 6.5 — #55 keyword settings presentation 追加自体は既存 route state を直接変更しない。
- 7.1 — `MockKeywordRepository` が deterministic list / create / update / delete / failure hooks を提供。
- 7.2 — `KeywordRepositoryTests` が mock `APITransport` で method / path / JSON body / Bearer を検証。
- 7.3 — `testKeywordResponseDecodesCanonicalFieldsAndUnknownScope` で API model decode を検証。
- 7.4 — `KeywordSettingsViewModelTests` が loading / success / empty / error / mutation / guard / delete confirmation を検証。
- 7.5 — duplicate / rate-limit / auth / network guidance tests で raw token や private data を表示しない guidance を確認。
- 7.6 — tests は mock transport / mock repository を使い、実 network / OAuth / Keychain / APNs に依存しない。
- 8.1 — `KeywordSettingsRowPresentation` test と sheet accessibility labels で keyword controls の label を確認。
- 8.2 — sheet row/input は fixed-size overflow を避け、text wrapping を使う実装。
- 8.3 — long keyword row は `lineLimit(3)` と flexible layout で primary controls を押し出しにくい構成。
- 8.4 — keyword term と token を組み合わせる logging は差分上見当たらない。
- 8.5 — #55 の新規 Core / Notifications placement は要件通り。Round 1 の notification deep link / APNs 境界逸脱は `develop..HEAD` から除外済み。
- 8.6 — Round 1 で検出された #56 spec 削除は `develop..HEAD` から除外済み。他 Issue specs の差分は見当たらない。
- 8.7 — 新規 Swift type / identifier / file names は English。
- 8.8 — `impl-notes.md` に `xcodebuild ... test` pass（454 tests, 0 failures）が記録されている。Reviewer は `plutil -lint` と `git diff --check` を再実行し pass を確認。

## Findings

なし

## Summary

Round 2 の missing test は `testUpdateWithWhitespaceOnlyTermDoesNotCallRepository` 追加で解消済みです。`develop..HEAD` の差分は #55 の keyword CRUD repository / settings UI 境界内に収まり、AC 未カバー・missing test・boundary 逸脱はいずれも検出しませんでした。

RESULT: approve
