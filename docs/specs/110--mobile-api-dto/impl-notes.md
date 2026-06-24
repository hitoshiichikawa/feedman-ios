# Implementation Notes

## Summary

- Cross-feed next page request を `since_time` query から `since` query へ変更した。
- Search repository は `{ items, next_cursor, has_more }` wrapper を decode し、global search では `scope` を送らない。Global search ViewModel は wrapper metadata を保持して next page request / terminal page 判定に使う。内部 feed-scoped search は `SearchScope.feed(id:)` / `feed_id` で表現する。
- `ItemSummary` / `ItemDetail` は redundant feed metadata 欠落時も decode し、feed-scoped list / detail 表示では route の selected feed または originating summary を補完に使う。
- `POST /api/feeds` は server feed response shape と successful empty body を成功扱いにし、drawer は既存の subscription reload flow を正本にする。

## Decisions

- `ItemSummary.feedTitle` / `ItemDetail.feedTitle` は既存 UI component への波及を抑えるため non-optional のまま維持し、decode 欠落時は空文字で保持する。表示層では空文字を metadata 欠落として扱い、selected feed / originating summary を優先する。
- no-content registration は server feed payload が無いため、登録 URL を一時的な `RegisteredFeed` payload として success event に載せる。drawer の最終正本は registration 後の `/api/subscriptions` reload であり、reload failure 時のみ recoverable guidance と optimistic row に使われる。
- 追加依存は無し。

## Verification

- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Feedman.xcodeproj -scheme Feedman -destination 'platform=iOS Simulator,name=iPhone 16' test`
  - Result: PASS
  - Executed 495 tests, 0 failures
  - Note: 既存の `SharedPrimitives.swift` async warning が 1 件出るが、今回変更範囲外で test は成功。

## AC Coverage Matrix

| Requirement / AC | Implementation path | Production entrypoint / owning flow | Test / assertion | Verification result | Notes |
|------------------|---------------------|-------------------------------------|------------------|---------------------|-------|
| 1.1 | `APIClientFeedRepository.loadCrossFeedFirstPage` stores `response.sinceTime` | Timeline cross-feed first page repository flow | `CrossFeedRepositoryTests.testFirstPageRequestsCrossFeedWithLimitOnlyAndStoresSinceTime` | xcodebuild PASS | RFC3339 string のまま保持 |
| 1.2 | `fetchCrossFeedPage` sends `since` from stored baseline | Timeline next-page repository flow | `CrossFeedRepositoryTests.testNextPageSendsStoredCursorAndFirstPageSinceTimeThenAppendsItems` | xcodebuild PASS | `since=firstPage.since_time` |
| 1.3 | `fetchCrossFeedPage` no longer appends `since_time` query | Timeline next-page repository flow | same test asserts `since_time == nil` | xcodebuild PASS | old query regression |
| 1.4 | `loadCrossFeedNextPage` keeps stored cursor and normalized limit | Timeline next-page repository flow | same test asserts `cursor` and `limit` | xcodebuild PASS | existing pagination session preserved |
| 1.5 | `loadCrossFeedNextPage` guards missing baseline | Timeline next-page repository flow | `CrossFeedRepositoryTests.testNextPageBeforeFirstPageFailsWithoutNetworkRequest` | xcodebuild PASS | no network request without first page |
| 2.1 | `APIClientSearchRepository.searchItemsPage` sends `q` | Global search repository flow | `SearchRepositoryTests.testGlobalSearchRequestsEndpointWithQueryLimitAndBearerTokenWithoutScope` | xcodebuild PASS | encoded query asserted |
| 2.2 | `GlobalSearchViewModel` stores `SearchItemsResponse.usableNextCursor` and `searchItemsPage` sends `cursor` on next page | Global search next-page production flow | `SearchRepositoryTests.testGlobalSearchRequestsEndpointWithQueryLimitAndBearerTokenWithoutScope`; `GlobalSearchViewModelTests.testNextPageUsesStoredCursorAndAppendsResultsInServerOrder`; `GlobalSearchViewModelTests.testNextPageFailurePreservesResultsAndCanRetryWithStoredCursor` | xcodebuild PASS | stored cursor drives production next-page request |
| 2.3 | `searchItemsPage` normalizes and sends `limit` | Global search repository flow | same test asserts `limit=50` | xcodebuild PASS | uses existing page-size policy |
| 2.4 | `searchItemsPage` omits `scope` | Global search repository flow | same test asserts `scope == nil` | xcodebuild PASS | old contract regression |
| 2.5 | `SearchItemsResponse.items` | Search response decode | `APIDomainModelDecodeTests.testSearchItemsResponseDecodesWrapperMetadata` | xcodebuild PASS | wrapper decode |
| 2.6 | `SearchItemsResponse.nextCursor` | Search response decode | same test asserts `nextCursor` | xcodebuild PASS | snake_case mapping |
| 2.7 | `SearchItemsResponse.hasMore` | Search response decode | same test asserts `hasMore` | xcodebuild PASS | snake_case mapping |
| 2.8 | `GlobalSearchViewModel` consumes wrapper response items in order | Global search ViewModel repository dependency | `SearchRepositoryTests.testGlobalSearchItemsCompatibilityReturnsWrapperItemsInOrder`; `GlobalSearchViewModelTests.testNonEmptySearchShowsLoadingThenResultsInAPIOrder`; `GlobalSearchViewModelTests.testNextPageUsesStoredCursorAndAppendsResultsInServerOrder` | xcodebuild PASS | server order preserved for first and next page |
| 2.9 | `SearchItemsResponse.canLoadMore` requires `hasMore` and usable cursor; `GlobalSearchViewModel` clears `canLoadMore` on terminal page | Search pagination metadata and UI state | `SearchRepositoryTests.testTerminalSearchPageWhenHasMoreFalseOrCursorMissing`; `GlobalSearchViewModelTests.testNextPageUsesStoredCursorAndAppendsResultsInServerOrder` | xcodebuild PASS | blank cursor is treated as terminal |
| 2.10 | `SearchScope.feed(id:)` sends `feed_id` | Internal feed-scoped search repository capability | `SearchRepositoryTests.testFeedScopedSearchSendsFeedIDInsteadOfScope` | xcodebuild PASS | no `scope=feed` |
| 2.11 | No feed-scoped search UI added | Search feature UI | Diff review: `GlobalSearchView` unchanged for feed-scoped route | xcodebuild PASS | scope control |
| 3.1 | `ItemSummary.init(from:)` tolerates missing `feed_title` | Feed-scoped item list decode | `APIDomainModelDecodeTests.testFeedScopedItemSummaryDecodesWithoutFeedMetadata` | xcodebuild PASS | empty title marks missing metadata |
| 3.2 | `ItemSummary.init(from:)` tolerates missing `feed_favicon_url` | Feed-scoped item list decode | same test asserts nil favicon | xcodebuild PASS | nullable favicon preserved |
| 3.3 | `FeedViewModel.configure(selectedFeed:)` and descriptors use selected feed metadata | Feed route list presentation | `FeedViewModelTests.testDescriptorUsesSelectedFeedMetadataWhenFeedScopedItemOmitsMetadata` | xcodebuild PASS | production route owns selected feed |
| 3.4 | `ArticleDetailPresentation` preserves detail `feedTitle` | Article detail loaded presentation | `ArticleDetailViewModelTests.testOpenFetchesDetailAndMarksReadWithPartialRequest` | xcodebuild PASS | detail value wins |
| 3.5 | `ArticleDetailPresentation` preserves detail favicon | Article detail loaded presentation | existing detail tests use detail data URL favicon path | xcodebuild PASS | no generic remote-image change |
| 3.6 | `ItemDetail.init(from:)` tolerates missing `feed_title` | Item detail repository decode | `APIDomainModelDecodeTests.testItemDetailDecodesWithoutFeedMetadata` | xcodebuild PASS | no malformed response |
| 3.7 | `ItemDetail.init(from:)` tolerates missing `feed_favicon_url` | Item detail repository decode | same test asserts nil favicon | xcodebuild PASS | nullable favicon preserved |
| 3.8 | `ArticleDetailPresentation(detail:fallbackSummary:)` uses originating summary metadata | Article detail sheet from list/search summary | `ArticleDetailViewModelTests.testDetailPresentationUsesOriginatingSummaryMetadataWhenDetailOmitsFeedMetadata`; `FeedViewModelTests.testDetailInputUsesSelectedFeedMetadataWhenFeedScopedItemOmitsMetadata` | xcodebuild PASS | summary fallback only when detail lacks metadata |
| 3.9 | `ArticleDetailPresentation` renders neutral source state with no metadata | Article detail sheet presentation | `ArticleDetailViewModelTests.testDetailPresentationRendersNeutralSourceWhenNoFeedMetadataIsAvailable` | xcodebuild PASS | no invented server title |
| 4.1 | `FeedRegistrationResponse` decodes `id/feed_url/site_url/title/fetch_status` | Feed registration repository decode | `APIDomainModelDecodeTests.testFeedRegistrationResponseDecodesFlatFeedResponse` | xcodebuild PASS | server feed response shape |
| 4.2 | `RegisteredFeed.init(response:)` does not require subscription-only fields | Register feed submit flow | `FeedRegistrationRepositoryTests.testRegisterFeedPostsURLWithBearerTokenAndMapsResponse` | xcodebuild PASS | subscriptionID/fetchInterval nil |
| 4.3 | `APIClient.sendOptional` treats empty 2xx body as success | Register feed submit flow | `FeedRegistrationRepositoryTests.testRegisterFeedAcceptsSuccessfulNoContentResponse` | xcodebuild PASS | 204 covered |
| 4.4 | `RegisterFeedSuccessEvent` triggers drawer subscription reload | AppShell registration completion flow | `AppShellDrawerFeedStateTests.testRegistrationSuccessEventDeliveryStartsPostRegistrationReloadBeforeCompletionButton` | xcodebuild PASS | existing production flow retained |
| 4.5 | Drawer uses reloaded subscriptions as source of truth | AppShell drawer state | `AppShellDrawerFeedStateTests.testRefreshAfterFeedRegistrationReloadsSubscriptionsAndUsesRepositoryResult` | xcodebuild PASS | optimistic row replaced by repository result |
| 4.6 | Reload failure preserves registration success and shows recoverable refresh failure | AppShell drawer state | `AppShellDrawerFeedStateTests.testRefreshAfterFeedRegistrationFailureKeepsRegisteredFeedWithGuidance` | xcodebuild PASS | success event remains delivered |
| 4.7 | `POST /api/feeds` no longer decodes subscription response shape | Feed registration repository | `FeedRegistrationRepositoryTests.testRegisterFeedPostsURLWithBearerTokenAndMapsResponse`; fixture `feed_registration_response.json` | xcodebuild PASS | old subscription fixture replaced |
| 5.1 | cross-feed next page sends `since` | Regression test | `CrossFeedRepositoryTests.testNextPageSendsStoredCursorAndFirstPageSinceTimeThenAppendsItems` | xcodebuild PASS | direct query assertion |
| 5.2 | cross-feed next page does not send `since_time` | Regression test | same test asserts nil | xcodebuild PASS | direct query assertion |
| 5.3 | search request does not send `scope` | Regression test | `SearchRepositoryTests.testGlobalSearchRequestsEndpointWithQueryLimitAndBearerTokenWithoutScope` | xcodebuild PASS | direct query assertion |
| 5.4 | search wrapper response decodes metadata and production search preserves it | Regression test | `APIDomainModelDecodeTests.testSearchItemsResponseDecodesWrapperMetadata`; `GlobalSearchViewModelTests.testSearchFirstPageStoresPaginationMetadata`; `GlobalSearchViewModelTests.testNextPageUsesStoredCursorAndAppendsResultsInServerOrder` | xcodebuild PASS | items/cursor/has_more |
| 5.5 | feed-scoped item list decode and selected feed display fallback | Regression test | `APIDomainModelDecodeTests.testFeedScopedItemSummaryDecodesWithoutFeedMetadata`; `FeedViewModelTests.testDescriptorUsesSelectedFeedMetadataWhenFeedScopedItemOmitsMetadata` | xcodebuild PASS | production presentation path covered |
| 5.6 | item detail decode and originating summary fallback | Regression test | `APIDomainModelDecodeTests.testItemDetailDecodesWithoutFeedMetadata`; `ArticleDetailViewModelTests.testDetailPresentationUsesOriginatingSummaryMetadataWhenDetailOmitsFeedMetadata` | xcodebuild PASS | production sheet path covered |
| 5.7 | feed registration server feed response succeeds | Regression test | `FeedRegistrationRepositoryTests.testRegisterFeedPostsURLWithBearerTokenAndMapsResponse` | xcodebuild PASS | no subscription-only fields |
| 5.8 | feed registration no-body success can trigger subscription reload | Regression test | `FeedRegistrationRepositoryTests.testRegisterFeedAcceptsSuccessfulNoContentResponse`; `AppShellDrawerFeedStateTests.testRegistrationSuccessEventDeliveryStartsPostRegistrationReloadBeforeCompletionButton` | xcodebuild PASS | repository success event remains reload trigger |

## Non-Functional Coverage

- NFR 1.1: API date strings remain `String`; decode tests continue asserting RFC3339 strings.
- NFR 1.2: favicon remains nullable; no new generic remote image loading path was added.
- NFR 1.3: APIClient auth refresh behavior is unchanged and covered by existing APIClient tests.
- NFR 1.4: No token/query/content logging was added.
- NFR 2.1-2.4: No new feed-scoped search UI, notification UI, OPML/cache/feed URL editing UI, server spec edits, or visual/route redesign were added.
- NFR 3.1: canonical xcodebuild test passed.

## 確認事項

- なし。

## Reviewer Round 1 Corrective Action

Round 1 reject の対象は実装コードではなく、境界判定の正本である `docs/specs/110--mobile-api-dto/tasks.md` の欠落だった。既存実装差分を Requirements 1-5 に沿って task 化し、各 task に `_Requirements:_` と `_Boundary:_` を付けた `tasks.md` を復元した。

### Finding Closure Matrix

| Target requirement | Category | Required Action | Fix commit | Test/assertion | Verification result | Notes / no-change reason |
|--------------------|----------|-----------------|------------|----------------|---------------------|--------------------------|
| `boundary:docs/specs/110--mobile-api-dto/tasks.md` | boundary 逸脱 | 正本の `tasks.md` を復元し、各 task の `_Requirements:_` / `_Boundary:_` アノテーションで今回変更ファイルが許可範囲に入ることを確認できる状態にする | `docs(spec): restore mobile api dto task boundaries` | `test -f docs/specs/110--mobile-api-dto/tasks.md`; `rg -n "_Requirements:|_Boundary:" docs/specs/110--mobile-api-dto/tasks.md` | PASS | doc-only corrective action。実装コードと既存 test は変更していないため xcodebuild は前回 PASS 結果を維持する。 |

## Reviewer Round 2 Corrective Action

Round 2 reject の対象は実装コードではなく、`docs/specs/110--mobile-api-dto/requirements.md` と `tasks.md` に対応する `design.md` が欠落していたことによる設計 traceability 不足だった。
`design.md` を追加し、component / interface、data contract summary、Requirement AC と task の traceability matrix、NFR / risk coverage を明文化した。

### Finding Closure Matrix

| Target requirement | Category | Required Action | Fix commit | Test/assertion | Verification result | Notes / no-change reason |
|--------------------|----------|-----------------|------------|----------------|---------------------|--------------------------|
| `docs/specs/110--mobile-api-dto/design.md` | design traceability | `requirements.md` の AC 1.1-5.8 と `tasks.md` の Task 1-5 を結ぶ design component / interface / traceability matrix を追加する | `docs(spec): add mobile api dto design traceability` | `test -f docs/specs/110--mobile-api-dto/design.md`; `rg -n "CrossFeedPaginationContract|SearchAPIContract|ItemFeedMetadataContract|FeedRegistrationContract|5\\.8" docs/specs/110--mobile-api-dto/design.md`; canonical xcodebuild test | PASS | doc-only corrective action。実装コードは変更していないが、PR head で canonical xcodebuild も再実行済み。 |

## Reviewer Round 3 Corrective Action

Round 3 reject は search pagination の production 経路で wrapper metadata が失われる点と、空白だけの `next_cursor` を usable cursor と扱う点だった。
`SearchRepository` protocol を page response 境界へ拡張し、`GlobalSearchViewModel` / `GlobalSearchView` が first page の `next_cursor` / `has_more` を保持して末尾 sentinel から次ページを取得するようにした。

### Finding Closure Matrix

| Target requirement | Category | Required Action | Fix commit | Test/assertion | Verification result | Notes / no-change reason |
|--------------------|----------|-----------------|------------|----------------|---------------------|--------------------------|
| `Feedman/Core/SearchRepository.swift:29` | production pagination metadata | `searchItemsPage` を `SearchRepository` protocol 境界へ出し、`GlobalSearchViewModel` が `SearchItemsResponse` の `items` / `nextCursor` / `hasMore` を保持して next page request と terminal 判定に使う | `fix(search): preserve global search pagination metadata` | `GlobalSearchViewModelTests.testSearchFirstPageStoresPaginationMetadata`; `GlobalSearchViewModelTests.testNextPageUsesStoredCursorAndAppendsResultsInServerOrder`; `GlobalSearchViewModelTests.testNextPageFailurePreservesResultsAndCanRetryWithStoredCursor` | PASS | GlobalSearchView の末尾 sentinel から production next-page flow が呼ばれる |
| `Feedman/Core/APIModels.swift:272` | cursor validation | `SearchItemsResponse.usableNextCursor` を追加し、空白だけの cursor を terminal として扱う | `fix(search): preserve global search pagination metadata` | `SearchRepositoryTests.testTerminalSearchPageWhenHasMoreFalseOrCursorMissing` | PASS | stored cursor は trimmed value のみを使う |

### Verification

- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Feedman.xcodeproj -scheme Feedman -destination 'platform=iOS Simulator,name=iPhone 16' test`
  - Result: PASS
  - Executed 495 tests, 0 failures

STATUS: complete
