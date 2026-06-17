# Review Notes

<!-- idd-codex:review round=1 model=gpt-5.5 timestamp=2026-06-16T00:55:17Z -->

## Reviewed Scope

- Branch: codex/issue-40-impl-feed-screen-ui-with-filters-and-status-b
- HEAD commit: 6970a5d77f56e55fe9bfeb7b402d873f3e463bb6
- Compared to: develop..HEAD

## Verified Requirements

- 1.1 — `RootView.feedContent` renders `FeedView` for a selected drawer feed instead of the prior placeholder.
- 1.2 — `RootView` keeps `.navigationTitle(shellState.title)`, and `AppShellRoute.feed` title remains the source.
- 1.3 — `FeedView.task(id: feed.id)` and `FeedViewModel.loadInitialIfNeeded(feedID:)` start a new first-page session and clear old items on feed id change.
- 1.4 — `FeedViewModel.loadInitialIfNeeded(feedID:)` returns without refetch when current feed/filter state already matches.
- 1.5 — Feed UI is wired through existing `AppShellRoute.feed`; no second navigation state was added.
- 1.6 — Diff adds no keyword notification route, prototype Tweak control, or feed-scoped search UI.
- 2.1 — `FeedView.filterControl` renders exactly `すべて` / `未読` / `スター`.
- 2.2 — `FeedViewModel` default filter is `.all`, and tests verify first-page request with `.all`.
- 2.3 — Picker tags and `selectFilter` pass `FeedItemFilter.unread`; tests verify unread filter reload.
- 2.4 — Picker tags and generic `selectFilter` pass `FeedItemFilter.starred`.
- 2.5 — `selectFilter` calls `loadFirstPage(feedID:filter:)`; tests verify visible items are replaced for a changed filter.
- 2.6 — `loadFirstPage` clears `items` before new first-page load; tests verify old filter items are not appended.
- 2.7 — `selectFilter` guards same feed/filter; tests verify same filter does not refetch.
- 2.8 — SwiftUI segmented `Picker` exposes selected state, with a stable min height.
- 2.9 — Filter UI uses SwiftUI `.segmented` picker, not prototype DOM styling.
- 3.1 — `FeedViewModel` is annotated `@MainActor`.
- 3.2 — `FeedViewModel` stores `any FeedRepository`; no `URLSession`, Keychain, token, or APIClient dependency is introduced.
- 3.3 — Initial load calls `loadFeedItemsFirstPage(feedID:filter:limit:)`; tests verify call recording.
- 3.4 — Success exposes `items`, `canLoadMore`, `currentFeedID`, and `filter`; tests verify these fields.
- 3.5 — Empty first page maps to `.empty`; tests verify empty state.
- 3.6 — First-page failure maps to `.failed` and `FeedView` renders `FeedmanRecoverableErrorView` with retry; tests verify retry.
- 3.7 — Next-page failure preserves `items` and sets `nextPageErrorMessage`; tests verify retryable non-destructive error.
- 3.8 — ViewModel guards duplicate in-flight first/next page requests for the same visible session.
- 3.9 — User-facing error strings are fixed Japanese copy without debug/token/transport details.
- 3.10 — `ItemSummary.publishedAt` remains `String`; date formatting is descriptor/display-layer only.
- 4.1 — `.idle` / `.loading` render shared `FeedmanLoadingView` while the task requests first page.
- 4.2 — `.loaded` renders `itemList` cards.
- 4.3 — `.empty` renders `FeedmanEmptyStateView`.
- 4.4 — Empty copy includes `記事がありません` plus filter-aware subtitles.
- 4.5 — First-page failure renders shared `FeedmanRecoverableErrorView` and retry.
- 4.6 — Retry calls `retryInitialLoad(feedID:)`, which requests first page for current filter; tests verify.
- 4.7 — Card `onAppear` near suffix items calls `loadFeedItemsNextPage()` when `canLoadMore`.
- 4.8 — #39 repository returns cumulative snapshots after append; ViewModel applies that order and tests verify first then second item.
- 4.9 — `isLoadingNextPage` renders `FeedmanCompactLoadingRow`.
- 4.10 — Next-page failure keeps cards visible and renders retry banner; tests verify preservation.
- 4.11 — Terminal loaded list renders `最後まで読みました`.
- 4.12 — View code does not construct feed item query/path; it uses #39 repository methods.
- 5.1 — `FeedStatus.active` returns nil banner descriptor; tests verify.
- 5.2 — stopped/error descriptors include message and `再開` action label.
- 5.3 — stopped status uses warning style and status-derived/fallback message.
- 5.4 — error status uses error style and status-derived/fallback message.
- 5.5 — descriptor fallback code covers blank stopped/error messages; tests cover stopped fallback.
- 5.6 — action affordance label is `再開`.
- 5.7 — action stores/emits resume intent and does not call resume mutation; tests verify no repository mutation.
- 5.8 — UI uses shared `FeedmanBannerView`.
- 5.9 — Banner is rendered before filter control/list content.
- 5.10 — Shared banner wraps message with line limit and action content in the same stable row.
- 6.1 — Card renders `descriptor.title`.
- 6.2 — Title uses `.lineLimit(2)`.
- 6.3 — Non-empty summary renders with `.lineLimit(2)`.
- 6.4 — Blank/nil summary returns nil and the summary view is omitted; tests verify blank summary.
- 6.5 — Descriptor derives relative date from `publishedAt`.
- 6.6 — Estimated date is prefixed through shared `TimelineRelativeDateFormatter`; tests verify.
- 6.7 — Hatebu available state uses existing `ArticleHatebuCountControl`; tests verify available count.
- 6.8 — Hatebu unavailable state uses existing unavailable descriptor and does not imply zero; tests verify.
- 6.9 — Starred item passes filled state to existing `ArticleStarControl`; tests verify starred descriptor/toggle behavior.
- 6.10 — Unstarred item passes unfilled state through the same descriptor path.
- 6.11 — Valid link passes a URL to existing `ArticleOpenLinkControl`; tests verify valid link.
- 6.12 — Malformed link maps to nil and hidden open-link control; tests verify bad link.
- 6.13 — Read item opacity is `0.55`; tests verify.
- 6.14 — Unread item opacity is `1`; tests verify.
- 6.15 — Card uses `FeedmanTheme` and shared metadata/star/open-link/hatebu controls.
- 6.16 — Card structure matches compact surface, metadata/title/summary, and bottom actions.
- 7.1 — Card body emits item-selection intent; tests verify selected id.
- 7.2 — No article detail sheet is presented.
- 7.3 — No read mutation or `ItemRepository.updateItemState` call is introduced.
- 7.4 — Star control is outside the body button and has its own intent; tests verify intent separation.
- 7.5 — Star action is local ViewModel state only; tests verify no repository mutation.
- 7.6 — Open-link control is outside the body button and has its own intent; tests verify separation.
- 7.7 — Open link routes to existing `openURL` and does not add read sync.
- 7.8 — Existing star/open-link controls keep 44pt touch targets.
- 8.1 — Segmented `Picker` communicates label/selection via native SwiftUI control semantics.
- 8.2 — Banner message and action are exposed through shared banner plus labeled `再開` button.
- 8.3 — Card accessibility label includes feed title, article title, and published time.
- 8.4 — Existing star control exposes label, value, and selected trait.
- 8.5 — Existing open-link control exposes `元記事をブラウザで開く`.
- 8.6 — Existing hatebu control announces unavailable as `はてなブックマーク未取得`.
- 8.7 — Text uses line limits/wrapping and fixed-size vertical behavior to avoid overlap under larger Dynamic Type.
- 8.8 — Narrow width behavior uses title/summary line limits and fixed 44pt action controls.
- 8.9 — Read/unread accessibility value is added, so opacity is not the only signal.
- 9.1 — `testInitialLoadSuccessExposesLoadedItemsForFeedAndFilter`.
- 9.2 — `testInitialLoadEmptyPageExposesEmptyState`.
- 9.3 — `testInitialLoadFailureCanRetryFirstPage`.
- 9.4 — `testFilterChangeRequestsNewFilterAndReplacesItems`.
- 9.5 — `testSelectedFeedChangeStartsNewFeedSpecificSession`.
- 9.6 — `testNextPageSuccessAppendsItemsInRepositoryOrder`.
- 9.7 — `testNextPageFailurePreservesExistingItemsAndShowsRetryableError`.
- 9.8 — `testTerminalStateDoesNotRequestNextPage`.
- 9.9 — `testStatusBannerDescriptorUsesFeedStatusAndFallbacks` covers active no-banner.
- 9.10 — `testStatusBannerDescriptorUsesFeedStatusAndFallbacks` covers stopped/error banner message and action label.
- 9.11 — Descriptor tests cover read/unread opacity, summary present/absent, hatebu available/unavailable, link, estimated date, and star behavior.
- 9.12 — Tests use `RecordingFeedItemsRepository` mock data and no network/OAuth/Keychain/token dependency.
- 9.13 — `impl-notes.md` documents why `xcodebuild ... test` could not run; reviewer reproduced the same CommandLineTools failure.
- NFR 1.1 — Implementation is SwiftUI/iOS project code only.
- NFR 1.2 — Feed feature follows MVVM + Repository and keeps query/API construction out of View/ViewModel.
- NFR 1.3 — Feature code is under `Feedman/Features/Feeds` with minimal AppShell wiring.
- NFR 1.4 — No new DesignSystem component was added.
- NFR 1.5 — New Swift identifiers and file names are English.
- NFR 2.1 — Feed UI uses `FeedmanTheme` semantic tokens.
- NFR 2.2 — Existing shared article metadata controls are reused.
- NFR 2.3 — Controls and terminal/loading rows have stable dimensions in implementation.
- NFR 2.4 — No OGP thumbnail, magazine layout, keyword match badge, or prototype Tweak alternative was added.
- NFR 3.1 — Diff stays within Feed screen UI, ViewModel, AppShell wiring, tests, and issue spec notes.
- NFR 3.2 — `design/SPEC-iOS.md`, `design/SERVER.md`, prototype files, and other issue specs were not modified.
- NFR 3.3 — No new server API contract or prototype JSON dependency is introduced.
- NFR 3.4 — Manual fetch cooldown, settings/resume mutation, article detail sheet, and real read/star sync are not implemented.
- NFR 3.5 — Diff contains no PR creation, reviewer/project-manager invocation, or commit automation.

## Findings

なし

## Summary

`tasks.md` と `design.md` は指定 spec dir に存在しなかったため、tasks の `_Requirements:_` / `_Boundary:_` annotation は直接照合できなかった。差分は空ではなく、requirements/impl-notes の scope と変更パスに照らした範囲では AC 未カバー、missing test、boundary 逸脱はいずれも検出しなかった。

Reviewer 再検証: `plutil -lint Feedman.xcodeproj/project.pbxproj` と `xcrun swiftc -frontend -parse ...` は成功。`xcodebuild -project Feedman.xcodeproj -scheme Feedman -destination 'platform=iOS Simulator,name=iPhone 16' test` は impl-notes と同じく active developer directory が CommandLineTools のため実行不可。

RESULT: approve
