# Review Notes

<!-- idd-codex:review round=2 model=gpt-5.5 timestamp=2026-06-23T11:38:07Z -->

## Reviewed Scope

- Branch: codex/issue-110-impl--mobile-api-dto
- HEAD commit: 0e0470b5bed7e1634949de336eb3a87e8971eac8
- Compared to: develop..HEAD

## Verified Requirements

- 1.1 — `Feedman/Core/FeedRepository.swift:460` で first page の `response.sinceTime` を `sessionSinceTime` に保持。`CrossFeedRepositoryTests.testFirstPageRequestsCrossFeedWithLimitOnlyAndStoresSinceTime` で確認。
- 1.2 — `Feedman/Core/FeedRepository.swift:615` で next page query に `since` を送信。`CrossFeedRepositoryTests.testNextPageSendsStoredCursorAndFirstPageSinceTimeThenAppendsItems` で確認。
- 1.3 — `Feedman/Core/FeedRepository.swift:615` の送信名が `since` で、同 test が `since_time == nil` を確認。
- 1.4 — `Feedman/Core/FeedRepository.swift:484` で stored cursor / normalized limit / baseline を継続送信。同 test で `cursor` と `limit` を確認。
- 1.5 — `Feedman/Core/FeedRepository.swift:466` で baseline 未確立時に next page を拒否。`CrossFeedRepositoryTests.testNextPageBeforeFirstPageFailsWithoutNetworkRequest` で確認。
- 2.1 — `Feedman/Core/SearchRepository.swift:50` で `q` を送信。`SearchRepositoryTests.testGlobalSearchRequestsEndpointWithQueryLimitAndBearerTokenWithoutScope` で確認。
- 2.2 — `Feedman/Core/SearchRepository.swift:55` で `cursor` を送信。同 test で確認。
- 2.3 — `Feedman/Core/SearchRepository.swift:49` で limit を normalized にして送信。同 test で確認。
- 2.4 — `Feedman/Core/SearchRepository.swift:50` から `scope` は送信されず、同 test が `scope == nil` を確認。
- 2.5 — `Feedman/Core/APIModels.swift:266` の `SearchItemsResponse.items` と `APIDomainModelDecodeTests.testSearchItemsResponseDecodesWrapperMetadata` で確認。
- 2.6 — `Feedman/Core/APIModels.swift:277` の `next_cursor` mapping と同 decode test で確認。
- 2.7 — `Feedman/Core/APIModels.swift:278` の `has_more` mapping と同 decode test で確認。
- 2.8 — `SearchRepositoryTests.testGlobalSearchItemsCompatibilityReturnsWrapperItemsInOrder` と `GlobalSearchViewModelTests.testNonEmptySearchShowsLoadingThenResultsInAPIOrder` で server order の公開を確認。
- 2.9 — `Feedman/Core/APIModels.swift:271` の `canLoadMore` と `SearchRepositoryTests.testTerminalSearchPageWhenHasMoreFalseOrCursorMissing` で確認。
- 2.10 — `Feedman/Core/SearchRepository.swift:59` で internal feed-scoped search は `feed_id` を送信。`SearchRepositoryTests.testFeedScopedSearchSendsFeedIDInsteadOfScope` で確認。
- 2.11 — 差分上、`Feedman/Features/Search` に feed-scoped UI 追加なし。global search は `Feedman/Features/Search/GlobalSearchViewModel.swift:215` の既存 `.global` 呼び出しを維持。
- 3.1 — `Feedman/Core/APIModels.swift:72` で `feed_title` 欠落を許容。`APIDomainModelDecodeTests.testFeedScopedItemSummaryDecodesWithoutFeedMetadata` で確認。
- 3.2 — `Feedman/Core/APIModels.swift:73` で `feed_favicon_url` 欠落を許容。同 decode test で確認。
- 3.3 — `Feedman/Features/Feeds/FeedView.swift:47` と `Feedman/Features/Feeds/FeedViewModel.swift:203` で selected feed metadata を表示補完に使用。`FeedViewModelTests.testDescriptorUsesSelectedFeedMetadataWhenFeedScopedItemOmitsMetadata` で確認。
- 3.4 — `Feedman/Features/ArticleDetail/ArticleDetailViewModel.swift:154` で detail の `feedTitle` を優先。`ArticleDetailViewModelTests.testOpenFetchesDetailAndMarksReadWithPartialRequest` で確認。
- 3.5 — `Feedman/Features/ArticleDetail/ArticleDetailViewModel.swift:156` で detail favicon を優先。既存 detail presentation tests で確認。
- 3.6 — `Feedman/Core/APIModels.swift:160` で detail の `feed_title` 欠落を許容。`APIDomainModelDecodeTests.testItemDetailDecodesWithoutFeedMetadata` で確認。
- 3.7 — `Feedman/Core/APIModels.swift:161` で detail の `feed_favicon_url` 欠落を許容。同 decode test で確認。
- 3.8 — `Feedman/Features/ArticleDetail/ArticleDetailViewModel.swift:148` で originating summary fallback を使用。`ArticleDetailViewModelTests.testDetailPresentationUsesOriginatingSummaryMetadataWhenDetailOmitsFeedMetadata` で確認。
- 3.9 — `Feedman/Features/ArticleDetail/ArticleDetailViewModel.swift:155` で metadata 不在時は空文字の neutral source state。`ArticleDetailViewModelTests.testDetailPresentationRendersNeutralSourceWhenNoFeedMetadataIsAvailable` で確認。
- 4.1 — `Feedman/Core/APIModels.swift:286` の `FeedRegistrationResponse` が server feed response fields を decode。`APIDomainModelDecodeTests.testFeedRegistrationResponseDecodesFlatFeedResponse` で確認。
- 4.2 — `Feedman/Core/FeedRepository.swift:283` で subscription-only fields を要求しない。`FeedRegistrationRepositoryTests.testRegisterFeedPostsURLWithBearerTokenAndMapsResponse` で確認。
- 4.3 — `Feedman/Core/APIClient.swift:75` の `sendOptional` と `FeedRegistrationRepositoryTests.testRegisterFeedAcceptsSuccessfulNoContentResponse` で no-body success を確認。
- 4.4 — `Feedman/Features/AppShell/RootView.swift:414` から `refreshSubscriptionsAfterFeedRegistration` を起動。`AppShellDrawerFeedStateTests.testRegistrationSuccessEventDeliveryStartsPostRegistrationReloadBeforeCompletionButton` で確認。
- 4.5 — `Feedman/Features/AppShell/AppShellDrawerFeedState.swift:61` で reload 結果を source of truth にする。`AppShellDrawerFeedStateTests.testRefreshAfterFeedRegistrationReloadsSubscriptionsAndUsesRepositoryResult` で確認。
- 4.6 — `Feedman/Features/AppShell/AppShellDrawerFeedState.swift:67` で登録成功を保ち recoverable failure を表示。`AppShellDrawerFeedStateTests.testRefreshAfterFeedRegistrationFailureKeepsRegisteredFeedWithGuidance` で確認。
- 4.7 — `Feedman/Core/APIModels.swift:286` と `FeedmanTests/Fixtures/feed_registration_response.json` が subscription response shape を要求しない。`FeedRegistrationRepositoryTests.testRegisterFeedPostsURLWithBearerTokenAndMapsResponse` で確認。
- 5.1 — `CrossFeedRepositoryTests.testNextPageSendsStoredCursorAndFirstPageSinceTimeThenAppendsItems` が `since` 送信を確認。
- 5.2 — 同 test が `since_time` 非送信を確認。
- 5.3 — `SearchRepositoryTests.testGlobalSearchRequestsEndpointWithQueryLimitAndBearerTokenWithoutScope` が `scope` 非送信を確認。
- 5.4 — `APIDomainModelDecodeTests.testSearchItemsResponseDecodesWrapperMetadata` が `items` / `next_cursor` / `has_more` decode を確認。
- 5.5 — `APIDomainModelDecodeTests.testFeedScopedItemSummaryDecodesWithoutFeedMetadata` と `FeedViewModelTests.testDescriptorUsesSelectedFeedMetadataWhenFeedScopedItemOmitsMetadata` で確認。
- 5.6 — `APIDomainModelDecodeTests.testItemDetailDecodesWithoutFeedMetadata` と `ArticleDetailViewModelTests.testDetailPresentationUsesOriginatingSummaryMetadataWhenDetailOmitsFeedMetadata` で確認。
- 5.7 — `FeedRegistrationRepositoryTests.testRegisterFeedPostsURLWithBearerTokenAndMapsResponse` が server feed response shape を確認。
- 5.8 — `FeedRegistrationRepositoryTests.testRegisterFeedAcceptsSuccessfulNoContentResponse` と `AppShellDrawerFeedStateTests.testRegistrationSuccessEventDeliveryStartsPostRegistrationReloadBeforeCompletionButton` で確認。

## Findings

なし

## Summary

Round 1 の reject 理由だった `tasks.md` 欠落は `0e0470b` で復元され、各変更ファイルは復元後の `_Boundary:_` に照合できる。AC 対応の実装と regression test も確認できたため approve と判定する。

RESULT: approve
