# Review Notes

<!-- idd-codex:review round=1 model=gpt-5.5 timestamp=2026-06-12T08:11:29Z -->

## Reviewed Scope

- Branch: codex/issue-46-impl-global-search-repository-and-screen
- HEAD commit: 13f7b381763ae2185439aeae76066c6aac189c67
- Compared to: develop..HEAD

## Verified Requirements

- 1.1 — `Feedman/Core/SearchRepository.swift:8` の `SearchRepository` async API と `APIClientSearchRepository.searchItems` が `/api/items/search` を呼び出す。
- 1.2 — `SearchScope` と `searchItems(query:scope:)` が Repository 境界で scope を表現し、`GlobalSearchViewModel` は `.global` を指定する。
- 1.3 — `APIClientSearchRepository.searchItems` は `[ItemSearchHit]` を返す。
- 1.4 — `SearchRepository` / `APIClientSearchRepository` / tests は `ItemSearchHit` を直接扱い、`ItemSummary` 変換はない。
- 1.5 — View / ViewModel は `SearchRepository` protocol のみを受け取り、`URLSession` / Keychain / refresh 詳細へ直接触れない。
- 1.6 — `MockSearchRepositoryResponse` と `MockSearchRepository` が success / empty / failure を deterministic に返せる。
- 2.1 — `SearchRepositoryTests.testGlobalSearchRequestsEndpointWithQueryScopeAndBearerToken` が path、`q`、`scope=global` を検証している。
- 2.2 — 同 test が日本語、空白、予約文字の URL encoding を検証している。
- 2.3 — `APIClientSearchRepository` は共有 `APIClient.send` に `accessToken` を渡して認証付き request を構成する。
- 2.4 — 共有 `APIClient` の refresh retry behavior に委譲しており、既存 `APIClientTests.testAuthenticated401RefreshesOnceAndRetriesWithNewBearerToken` が retry 成功を検証している。
- 2.5 — `SearchRepositoryTests.testAuthRequiredErrorPropagatesWithoutEmptyResult` と `GlobalSearchViewModelTests.testAuthRequiredFailureCallsBoundaryAndDoesNotShowEmptyResult` が auth-required を空結果にしないことを検証している。
- 2.6 — 差分内に token / Authorization / query / response body の logging 追加はない。
- 3.1 — `GlobalSearchViewModel.submitSearch` が空 query で repository call 前に停止し、`testEmptyAndWhitespaceQueriesDoNotCallRepository` が検証している。
- 3.2 — 同 test が whitespace-only query の no-request を検証している。
- 3.3 — 初期 state は `.suggestions` で、`testInitialStateShowsSuggestions` と `GlobalSearchView.suggestionsContent` が候補/空状態を表示する。
- 3.4 — `clearQuery()` が active search を clear し、request を発行しない。
- 3.5 — `submitSuggestion` が suggestion を query に設定して `.global` search を実行し、`testSuggestionSelectionSubmitsGlobalSearch` が検証している。
- 4.1 — `submitSearch` が non-empty query で `.loading` に遷移し、`testNonEmptySearchShowsLoadingThenResultsInAPIOrder` が検証している。
- 4.2 — success hits は API order のまま `.results` に公開され、同 test が検証している。
- 4.3 — zero hits は `.empty(query:)` になり、`testZeroResultSearchShowsEmptyStateForSubmittedQuery` が検証している。
- 4.4 — failure は retry 可能な `.failed` 表示と retry action を持ち、`testFailureStateIsDistinctFromEmptyAndRetryUsesSameQuery` が検証している。
- 4.5 — auth-required は `onAuthRequired` boundary を呼び、stale success ではなく failed state にする。
- 4.6 — `currentRequestID` guard により古い response の適用を避ける。
- 4.7 — submit ごとに既存 task を cancel し request id を更新し、`testOlderResponseDoesNotOverwriteNewerSubmittedQuery` が検証している。
- 5.1 — `publishedAt` は optional のまま descriptor / UI で扱われる。
- 5.2 — `publishedDateText` は nil/blank を nil として扱い、timestamp を合成しない。
- 5.3 — `faviconURL` は optional のまま `ArticleSourceMetadata` に渡される。
- 5.4 — `ArticleSourceRow` 経由で既存 `FeedmanFaviconView` fallback を使う。
- 5.5 — `data:` URL も `ArticleSourceRow` / `FeedmanFaviconView` 経由で扱われ、`AsyncImage(url:)` へ直接渡す差分はない。
- 5.6 — `hatebuState` は `.unavailable` 固定で、`hatebu_fetched_at` を要求しない。
- 5.7 — `SearchResultCard` は VStack/HStack と shared controls で構成され、narrow width で重なりを誘発する固定幅本文は追加されていない。
- 6.1 — result card tap は `onSelectItem` callback 境界へ item id を渡す。既存記事詳細 UI/coordinator は未存在のため重複実装していない。
- 6.2 — open-link control は `onOpenLink` boundary へ URL を渡し、RootView は既存 SwiftUI `openURL` へ委譲する。
- 6.3 — open-link action と card select は descriptor 上で分離され、`testResultDescriptorSeparatesCardAndOpenLinkActions` が検証している。
- 6.4 — `ArticleStarControl` が `isStarred` state を shared control として表示する。
- 6.5 — star mutation は disabled で、検索専用 mutation API を追加していない。
- 6.6 — search repository 内に detail networking、Safari presentation、item state mutation の重複実装はない。
- 7.1 — AppShell の `.search` route が `GlobalSearchView` を表示する。
- 7.2 — 既存 `AppShellState.activateSearch()` route に委譲しており、検索 route の重複 push 差分はない。
- 7.3 — `GlobalSearchView` header に「購読フィードを横断検索」が表示される。
- 7.4 — RootView の既存 drawer / route state 構成を維持して placeholder のみ差し替えている。
- 7.5 — keyword notification、feed-scoped search、search history entry point の追加はない。
- 8.1 — Repository は `Feedman/Core`、UI は `Feedman/Features/Search`、AppShell 統合は既存境界に置かれている。
- 8.2 — ViewModel は `@MainActor` で Swift Concurrency の async/await を使う。
- 8.3 — `ArticleSourceRow`、`ArticleStarControl`、`ArticleOpenLinkControl`、`ArticleHatebuCountControl` を利用している。
- 8.4 — `design/SPEC-iOS.md` / `design/SERVER.md` の変更はない。
- 8.5 — feed-scoped search UI と search history sync は追加されていない。
- 8.6 — mock JSON 形への依存や `ItemSummary` 変換は追加されていない。

## Findings

なし

## Summary

Repository、ViewModel、Search 画面、AppShell 統合、主要 XCTest は AC の範囲を満たしている。`xcodebuild` は active developer directory が CommandLineTools のため実行不可だったが、`xcrun swiftc -parse` は成功した。

RESULT: approve
