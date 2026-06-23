import XCTest
@testable import Feedman

@MainActor
final class FeedViewModelTests: XCTestCase {
    func testInitialLoadSuccessExposesLoadedItemsForFeedAndFilter() async {
        let firstPage = snapshot(feedID: "feed-1", filter: .all, items: [item(id: "first"), item(id: "second")], canLoadMore: true)
        let repository = RecordingFeedItemsRepository(firstPageResults: [.success(firstPage)])
        let viewModel = FeedViewModel(repository: repository)

        await viewModel.loadInitialIfNeeded(feedID: "feed-1")

        XCTAssertEqual(viewModel.state, .loaded)
        XCTAssertEqual(viewModel.currentFeedID, "feed-1")
        XCTAssertEqual(viewModel.filter, .all)
        XCTAssertEqual(viewModel.items.map(\.id), ["first", "second"])
        XCTAssertTrue(viewModel.canLoadMore)
        let calls = await repository.calls()
        XCTAssertEqual(calls, [.firstPage(feedID: "feed-1", filter: .all, limit: nil)])
    }

    func testInitialLoadEmptyPageExposesEmptyState() async {
        let repository = RecordingFeedItemsRepository(
            firstPageResults: [.success(snapshot(feedID: "feed-1", filter: .all, items: [], canLoadMore: false))]
        )
        let viewModel = FeedViewModel(repository: repository)

        await viewModel.loadInitialIfNeeded(feedID: "feed-1")

        XCTAssertEqual(viewModel.state, .empty)
        XCTAssertEqual(viewModel.items, [])
        XCTAssertFalse(viewModel.canLoadMore)
    }

    func testFilterSpecificEmptyStateUsesSelectedFilterCopy() async {
        let repository = RecordingFeedItemsRepository(
            firstPageResults: [
                .success(snapshot(feedID: "feed-1", filter: .all, items: [item(id: "all")], canLoadMore: false)),
                .success(snapshot(feedID: "feed-1", filter: .unread, items: [], canLoadMore: false)),
                .success(snapshot(feedID: "feed-1", filter: .starred, items: [], canLoadMore: false))
            ]
        )
        let viewModel = FeedViewModel(repository: repository)

        await viewModel.loadInitialIfNeeded(feedID: "feed-1")
        await viewModel.selectFilter(.unread, feedID: "feed-1")

        XCTAssertEqual(viewModel.state, .empty)
        XCTAssertEqual(viewModel.filter, .unread)
        XCTAssertEqual(viewModel.items, [])
        XCTAssertEqual(
            viewModel.emptySubtitle,
            "未読の記事はありません。フィルターを切り替えると既読の記事も確認できます。"
        )

        await viewModel.selectFilter(.starred, feedID: "feed-1")

        XCTAssertEqual(viewModel.state, .empty)
        XCTAssertEqual(viewModel.filter, .starred)
        XCTAssertEqual(viewModel.items, [])
        XCTAssertEqual(
            viewModel.emptySubtitle,
            "スター付きの記事はありません。フィルターを切り替えると他の記事を確認できます。"
        )
    }

    func testInitialLoadFailureCanRetryFirstPage() async {
        let repository = RecordingFeedItemsRepository(
            firstPageResults: [
                .failure(FeedViewModelTestError.transport),
                .success(snapshot(feedID: "feed-1", filter: .all, items: [item(id: "recovered")], canLoadMore: false))
            ]
        )
        let viewModel = FeedViewModel(repository: repository)

        await viewModel.loadInitialIfNeeded(feedID: "feed-1")

        XCTAssertEqual(viewModel.state, .failed(message: "フィードの記事を読み込めませんでした。"))
        XCTAssertEqual(viewModel.items, [])

        await viewModel.retryInitialLoad(feedID: "feed-1")

        XCTAssertEqual(viewModel.state, .loaded)
        XCTAssertEqual(viewModel.items.map(\.id), ["recovered"])
        let calls = await repository.calls()
        XCTAssertEqual(
            calls,
            [
                .firstPage(feedID: "feed-1", filter: .all, limit: nil),
                .firstPage(feedID: "feed-1", filter: .all, limit: nil)
            ]
        )
    }

    func testRouteReturnForSameFeedAndFilterDoesNotRefetch() async {
        let repository = RecordingFeedItemsRepository(
            firstPageResults: [
                .success(snapshot(feedID: "feed-1", filter: .all, items: [item(id: "first")], canLoadMore: false)),
                .success(snapshot(feedID: "feed-1", filter: .all, items: [item(id: "unexpected")], canLoadMore: false))
            ]
        )
        let viewModel = FeedViewModel(repository: repository)

        await viewModel.loadInitialIfNeeded(feedID: "feed-1")
        await viewModel.loadInitialIfNeeded(feedID: "feed-1")

        XCTAssertEqual(viewModel.items.map(\.id), ["first"])
        let calls = await repository.calls()
        XCTAssertEqual(calls, [.firstPage(feedID: "feed-1", filter: .all, limit: nil)])
    }

    func testFilterChangeRequestsNewFilterAndReplacesItems() async {
        let repository = RecordingFeedItemsRepository(
            firstPageResults: [
                .success(snapshot(feedID: "feed-1", filter: .all, items: [item(id: "all")], canLoadMore: true)),
                .success(snapshot(feedID: "feed-1", filter: .unread, items: [item(id: "unread")], canLoadMore: false))
            ]
        )
        let viewModel = FeedViewModel(repository: repository)

        await viewModel.loadInitialIfNeeded(feedID: "feed-1")
        await viewModel.selectFilter(.unread, feedID: "feed-1")

        XCTAssertEqual(viewModel.filter, .unread)
        XCTAssertEqual(viewModel.items.map(\.id), ["unread"])
        XCTAssertFalse(viewModel.canLoadMore)
        let calls = await repository.calls()
        XCTAssertEqual(
            calls,
            [
                .firstPage(feedID: "feed-1", filter: .all, limit: nil),
                .firstPage(feedID: "feed-1", filter: .unread, limit: nil)
            ]
        )
    }

    func testSelectingSameFilterAgainDoesNotRefetch() async {
        let repository = RecordingFeedItemsRepository(
            firstPageResults: [
                .success(snapshot(feedID: "feed-1", filter: .all, items: [item(id: "first")], canLoadMore: false))
            ]
        )
        let viewModel = FeedViewModel(repository: repository)

        await viewModel.loadInitialIfNeeded(feedID: "feed-1")
        await viewModel.selectFilter(.all, feedID: "feed-1")

        let calls = await repository.calls()
        XCTAssertEqual(calls, [.firstPage(feedID: "feed-1", filter: .all, limit: nil)])
    }

    func testSelectedFeedChangeStartsNewFeedSpecificSession() async {
        let repository = RecordingFeedItemsRepository(
            firstPageResults: [
                .success(snapshot(feedID: "feed-1", filter: .all, items: [item(id: "old")], canLoadMore: false)),
                .success(snapshot(feedID: "feed-2", filter: .all, items: [item(id: "new")], canLoadMore: false))
            ]
        )
        let viewModel = FeedViewModel(repository: repository)

        await viewModel.loadInitialIfNeeded(feedID: "feed-1")
        await viewModel.loadInitialIfNeeded(feedID: "feed-2")

        XCTAssertEqual(viewModel.currentFeedID, "feed-2")
        XCTAssertEqual(viewModel.items.map(\.id), ["new"])
        let calls = await repository.calls()
        XCTAssertEqual(
            calls,
            [
                .firstPage(feedID: "feed-1", filter: .all, limit: nil),
                .firstPage(feedID: "feed-2", filter: .all, limit: nil)
            ]
        )
    }

    func testVisibleStateHidesLoadedItemsForDifferentRouteFeed() {
        let viewModel = FeedViewModel(
            state: .loaded,
            items: [item(id: "old")],
            canLoadMore: false,
            currentFeedID: "feed-1"
        )

        XCTAssertEqual(viewModel.visibleState(for: "feed-1"), .loaded)
        XCTAssertEqual(viewModel.visibleState(for: "feed-2"), .loading)
        XCTAssertEqual(viewModel.items.map(\.id), ["old"])
    }

    func testNextPageSuccessAppendsItemsInRepositoryOrder() async {
        let repository = RecordingFeedItemsRepository(
            firstPageResults: [
                .success(snapshot(feedID: "feed-1", filter: .all, items: [item(id: "first")], canLoadMore: true))
            ],
            nextPageResults: [
                .success(snapshot(feedID: "feed-1", filter: .all, items: [item(id: "first"), item(id: "second")], canLoadMore: false))
            ]
        )
        let viewModel = FeedViewModel(repository: repository)

        await viewModel.loadInitialIfNeeded(feedID: "feed-1")
        await viewModel.loadNextPageIfNeeded(currentItemID: "first")

        XCTAssertEqual(viewModel.items.map(\.id), ["first", "second"])
        XCTAssertFalse(viewModel.canLoadMore)
        let calls = await repository.calls()
        XCTAssertEqual(calls, [.firstPage(feedID: "feed-1", filter: .all, limit: nil), .nextPage])
    }

    func testNextPageFailurePreservesExistingItemsAndShowsRetryableError() async {
        let repository = RecordingFeedItemsRepository(
            firstPageResults: [
                .success(snapshot(feedID: "feed-1", filter: .all, items: [item(id: "first")], canLoadMore: true))
            ],
            nextPageResults: [
                .failure(FeedViewModelTestError.transport),
                .success(snapshot(feedID: "feed-1", filter: .all, items: [item(id: "first"), item(id: "second")], canLoadMore: false))
            ]
        )
        let viewModel = FeedViewModel(repository: repository)

        await viewModel.loadInitialIfNeeded(feedID: "feed-1")
        await viewModel.loadNextPageIfNeeded(currentItemID: "first")

        XCTAssertEqual(viewModel.items.map(\.id), ["first"])
        XCTAssertEqual(viewModel.nextPageErrorMessage, "続きを読み込めませんでした。")
        XCTAssertEqual(viewModel.state, .loaded)
        XCTAssertTrue(viewModel.canLoadMore)

        await viewModel.retryNextPage()

        XCTAssertEqual(viewModel.items.map(\.id), ["first", "second"])
        XCTAssertNil(viewModel.nextPageErrorMessage)
        let calls = await repository.calls()
        XCTAssertEqual(
            calls,
            [
                .firstPage(feedID: "feed-1", filter: .all, limit: nil),
                .nextPage,
                .nextPage
            ]
        )
    }

    func testFilterChangeDuringNextPageQueuesFirstPageUntilNextPageCompletes() async {
        let repository = PausedNextPageFeedItemsRepository(
            firstPageResults: [
                .success(snapshot(feedID: "feed-1", filter: .all, items: [item(id: "first")], canLoadMore: true)),
                .success(snapshot(feedID: "feed-1", filter: .unread, items: [item(id: "unread")], canLoadMore: false))
            ]
        )
        let viewModel = FeedViewModel(repository: repository)

        await viewModel.loadInitialIfNeeded(feedID: "feed-1")
        let nextPageTask = Task { @MainActor in
            await viewModel.loadNextPageIfNeeded(currentItemID: "first")
        }
        await repository.waitForNextPageStart()

        let filterTask = Task { @MainActor in
            await viewModel.selectFilter(.unread, feedID: "feed-1")
        }
        await filterTask.value

        XCTAssertEqual(viewModel.state, .loading)
        XCTAssertEqual(viewModel.filter, .unread)
        XCTAssertEqual(viewModel.items, [])
        let callsBeforeNextPageCompletes = await repository.calls()
        XCTAssertEqual(
            callsBeforeNextPageCompletes,
            [
                .firstPage(feedID: "feed-1", filter: .all, limit: nil),
                .nextPage
            ]
        )

        await repository.completeNextPage(
            with: .success(snapshot(feedID: "feed-1", filter: .all, items: [item(id: "first"), item(id: "old-next")], canLoadMore: false))
        )
        await nextPageTask.value

        XCTAssertEqual(viewModel.state, .loaded)
        XCTAssertEqual(viewModel.filter, .unread)
        XCTAssertEqual(viewModel.items.map(\.id), ["unread"])
        XCTAssertFalse(viewModel.canLoadMore)
        let calls = await repository.calls()
        XCTAssertEqual(
            calls,
            [
                .firstPage(feedID: "feed-1", filter: .all, limit: nil),
                .nextPage,
                .firstPage(feedID: "feed-1", filter: .unread, limit: nil)
            ]
        )
    }

    func testFeedChangeDuringNextPageQueuesFirstPageUntilNextPageCompletes() async {
        let repository = PausedNextPageFeedItemsRepository(
            firstPageResults: [
                .success(snapshot(feedID: "feed-1", filter: .all, items: [item(id: "first")], canLoadMore: true)),
                .success(snapshot(feedID: "feed-2", filter: .all, items: [item(id: "feed-2-item", feedID: "feed-2")], canLoadMore: false))
            ]
        )
        let viewModel = FeedViewModel(repository: repository)

        await viewModel.loadInitialIfNeeded(feedID: "feed-1")
        let nextPageTask = Task { @MainActor in
            await viewModel.loadNextPageIfNeeded(currentItemID: "first")
        }
        await repository.waitForNextPageStart()

        let feedChangeTask = Task { @MainActor in
            await viewModel.loadInitialIfNeeded(feedID: "feed-2")
        }
        await feedChangeTask.value

        XCTAssertEqual(viewModel.state, .loading)
        XCTAssertEqual(viewModel.currentFeedID, "feed-2")
        XCTAssertEqual(viewModel.filter, .all)
        XCTAssertEqual(viewModel.items, [])

        await repository.completeNextPage(with: .failure(FeedViewModelTestError.transport))
        await nextPageTask.value

        XCTAssertEqual(viewModel.state, .loaded)
        XCTAssertEqual(viewModel.currentFeedID, "feed-2")
        XCTAssertEqual(viewModel.items.map(\.id), ["feed-2-item"])
        XCTAssertNil(viewModel.nextPageErrorMessage)
        let calls = await repository.calls()
        XCTAssertEqual(
            calls,
            [
                .firstPage(feedID: "feed-1", filter: .all, limit: nil),
                .nextPage,
                .firstPage(feedID: "feed-2", filter: .all, limit: nil)
            ]
        )
    }

    func testTerminalStateDoesNotRequestNextPage() async {
        let repository = RecordingFeedItemsRepository(
            firstPageResults: [
                .success(snapshot(feedID: "feed-1", filter: .all, items: [item(id: "only")], canLoadMore: false))
            ],
            nextPageResults: [
                .success(snapshot(feedID: "feed-1", filter: .all, items: [item(id: "unexpected")], canLoadMore: false))
            ]
        )
        let viewModel = FeedViewModel(repository: repository)

        await viewModel.loadInitialIfNeeded(feedID: "feed-1")
        await viewModel.loadNextPageIfNeeded(currentItemID: "only")

        XCTAssertEqual(viewModel.items.map(\.id), ["only"])
        let calls = await repository.calls()
        XCTAssertEqual(calls, [.firstPage(feedID: "feed-1", filter: .all, limit: nil)])
    }

    func testStatusBannerDescriptorUsesFeedStatusAndFallbacks() {
        let viewModel = FeedViewModel()

        XCTAssertNil(viewModel.statusBanner(for: .active))

        let stopped = viewModel.statusBanner(for: .stopped(message: "  "))
        XCTAssertEqual(stopped?.message, "フィードの取得が停止しています")
        XCTAssertEqual(stopped?.style, .warning)
        XCTAssertEqual(stopped?.actionLabel, "再開")

        let error = viewModel.statusBanner(for: .error(message: "取得できません"))
        XCTAssertEqual(error?.message, "取得できません")
        XCTAssertEqual(error?.style, .error)
        XCTAssertEqual(error?.actionLabel, "再開")
    }

    func testResumeActionStoresIntentWithoutRepositoryMutation() async {
        let repository = RecordingFeedItemsRepository(firstPageResults: [])
        let viewModel = FeedViewModel(repository: repository)

        viewModel.requestResume(feedID: "feed-1")

        XCTAssertEqual(viewModel.requestedResumeFeedID, "feed-1")
        let calls = await repository.calls()
        XCTAssertEqual(calls, [])
    }

    func testDescriptorDerivesCardPresentationWithoutMutatingAPIDate() throws {
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-06-08T10:30:00Z"))
        let unread = item(
            id: "unread",
            summary: "  Summary  ",
            publishedAt: "2026-06-08T08:30:00Z",
            isRead: false,
            isStarred: true,
            hatebuCount: 12,
            hatebuFetchedAt: "2026-06-08T09:00:00Z"
        )
        let descriptor = FeedItemCardDescriptor(item: unread, now: now)

        XCTAssertEqual(descriptor.relativeDate, "2時間前")
        XCTAssertEqual(descriptor.summary, "Summary")
        XCTAssertEqual(descriptor.opacity, 1)
        XCTAssertTrue(descriptor.isStarred)
        XCTAssertEqual(descriptor.hatebuState, .available(12))
        XCTAssertEqual(descriptor.linkURL, URL(string: "https://example.com/unread"))
        XCTAssertEqual(unread.publishedAt, "2026-06-08T08:30:00Z")
    }

    func testDescriptorHandlesReadEmptySummaryUnavailableHatebuEstimatedDateAndBadLink() throws {
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-06-08T10:30:00Z"))
        let descriptor = FeedItemCardDescriptor(
            item: item(
                id: "read",
                summary: "   ",
                link: "not a url",
                publishedAt: "2026-06-08T10:20:00Z",
                isDateEstimated: true,
                isRead: true,
                hatebuCount: 0,
                hatebuFetchedAt: nil
            ),
            now: now
        )

        XCTAssertEqual(descriptor.relativeDate, "推定 10分前")
        XCTAssertNil(descriptor.summary)
        XCTAssertEqual(descriptor.opacity, 0.55)
        XCTAssertEqual(descriptor.hatebuState, .unavailable)
        XCTAssertNil(descriptor.linkURL)
    }

    func testDescriptorUsesSelectedFeedMetadataWhenFeedScopedItemOmitsMetadata() throws {
        let viewModel = FeedViewModel()
        viewModel.configure(
            repository: RecordingFeedItemsRepository(firstPageResults: []),
            selectedFeed: Feed(
                id: "feed-1",
                subscriptionID: "sub-1",
                title: "Selected Feed",
                unreadCount: 0,
                status: .active,
                faviconURL: "data:image/png;base64,iVBORw0KGgo="
            )
        )
        let descriptor = viewModel.descriptor(
            for: item(id: "missing-feed-metadata", feedTitle: "", feedFaviconURL: nil),
            now: Date(timeIntervalSince1970: 0)
        )

        XCTAssertEqual(descriptor.sourceMetadata.feedTitle, "Selected Feed")
        XCTAssertEqual(descriptor.sourceMetadata.faviconURL, "data:image/png;base64,iVBORw0KGgo=")
        XCTAssertTrue(descriptor.accessibilityLabel.contains("Selected Feed"))
    }

    func testDetailInputUsesSelectedFeedMetadataWhenFeedScopedItemOmitsMetadata() async throws {
        let repository = RecordingFeedItemsRepository(
            firstPageResults: [
                .success(snapshot(
                    feedID: "feed-1",
                    filter: .all,
                    items: [item(id: "missing-feed-metadata", feedTitle: "", feedFaviconURL: nil)],
                    canLoadMore: false
                ))
            ]
        )
        let viewModel = FeedViewModel(repository: repository)
        viewModel.configure(
            repository: repository,
            selectedFeed: Feed(
                id: "feed-1",
                subscriptionID: "sub-1",
                title: "Selected Feed",
                unreadCount: 0,
                status: .active,
                faviconURL: "data:image/png;base64,iVBORw0KGgo="
            )
        )

        await viewModel.loadInitialIfNeeded(feedID: "feed-1")

        let input = viewModel.detailInput(for: "missing-feed-metadata")
        XCTAssertEqual(input.summary?.feedTitle, "Selected Feed")
        XCTAssertEqual(input.summary?.feedFaviconURL, "data:image/png;base64,iVBORw0KGgo=")
    }

    func testDescriptorSeparatesSelectionStarAndOpenLinkIntents() throws {
        let descriptor = FeedItemCardDescriptor(item: item(id: "action"))
        var selectedIDs: [String] = []
        var starredIDs: [String] = []
        var openedURLs: [URL] = []

        descriptor.openLink { url in
            openedURLs.append(url)
        }
        descriptor.toggleStar { id in
            starredIDs.append(id)
        }
        descriptor.select { id in
            selectedIDs.append(id)
        }

        XCTAssertEqual(selectedIDs, ["action"])
        XCTAssertEqual(starredIDs, ["action"])
        XCTAssertEqual(openedURLs, [try XCTUnwrap(URL(string: "https://example.com/action"))])
    }

    func testStarToggleCallsRepositoryMutationAndUpdatesEffectiveState() async throws {
        let repository = RecordingFeedItemsRepository(
            firstPageResults: [
                .success(snapshot(feedID: "feed-1", filter: .all, items: [item(id: "target", isStarred: false)], canLoadMore: false))
            ]
        )
        let itemRepository = MockItemRepository()
        let viewModel = FeedViewModel(
            repository: repository,
            itemRepository: itemRepository,
            accessToken: "test-access-token"
        )

        await viewModel.loadInitialIfNeeded(feedID: "feed-1")
        await viewModel.toggleStar(id: "target")

        let firstItem = try XCTUnwrap(viewModel.items.first)
        XCTAssertTrue(viewModel.descriptor(for: firstItem).isStarred)
        let calls = await repository.calls()
        XCTAssertEqual(calls, [.firstPage(feedID: "feed-1", filter: .all, limit: nil)])
        XCTAssertEqual(
            itemRepository.stateUpdates,
            [
                MockItemStateUpdate(
                    itemID: "target",
                    request: ItemStateUpdateRequest(isRead: nil, isStarred: true)
                )
            ]
        )
    }

    func testStarToggleFailureRollsBackEffectiveStateAndShowsError() async throws {
        let repository = RecordingFeedItemsRepository(
            firstPageResults: [
                .success(snapshot(feedID: "feed-1", filter: .all, items: [item(id: "target", isStarred: false)], canLoadMore: false))
            ]
        )
        let viewModel = FeedViewModel(
            repository: repository,
            itemRepository: MockItemRepository(stateUpdateFailure: FeedViewModelTestError.transport),
            accessToken: "test-access-token"
        )

        await viewModel.loadInitialIfNeeded(feedID: "feed-1")
        viewModel.selectItem(id: "target")
        await viewModel.toggleStar(id: "target")

        let firstItem = try XCTUnwrap(viewModel.items.first)
        XCTAssertFalse(viewModel.descriptor(for: firstItem).isStarred)
        XCTAssertEqual(viewModel.items.map(\.id), ["target"])
        XCTAssertEqual(viewModel.selectedItemID, "target")
        XCTAssertEqual(viewModel.starMutationErrorMessage, "スターを更新できませんでした。")
    }

    func testManualRefreshSuccessFetchesBeforeReloadAndPreservesFilter() async {
        let repository = RecordingFeedItemsRepository(
            firstPageResults: [
                .success(snapshot(feedID: "feed-1", filter: .all, items: [item(id: "all")], canLoadMore: false)),
                .success(snapshot(feedID: "feed-1", filter: .unread, items: [item(id: "old-unread")], canLoadMore: false)),
                .success(snapshot(feedID: "feed-1", filter: .unread, items: [item(id: "new-unread")], canLoadMore: true))
            ],
            manualFetchResults: [.success(())]
        )
        let viewModel = FeedViewModel(repository: repository)

        await viewModel.loadInitialIfNeeded(feedID: "feed-1")
        await viewModel.selectFilter(.unread, feedID: "feed-1")
        await viewModel.refreshFeed(feedID: "feed-1", subscriptionID: "sub-feed-1")

        XCTAssertEqual(viewModel.state, .loaded)
        XCTAssertEqual(viewModel.filter, .unread)
        XCTAssertEqual(viewModel.items.map(\.id), ["new-unread"])
        XCTAssertTrue(viewModel.canLoadMore)
        XCTAssertNil(viewModel.refreshFeedback)
        XCTAssertFalse(viewModel.isRefreshing)
        let calls = await repository.calls()
        XCTAssertEqual(
            calls,
            [
                .firstPage(feedID: "feed-1", filter: .all, limit: nil),
                .firstPage(feedID: "feed-1", filter: .unread, limit: nil),
                .manualFetch(subscriptionID: "sub-feed-1"),
                .firstPage(feedID: "feed-1", filter: .unread, limit: nil)
            ]
        )
    }

    func testManualRefreshCooldownPreservesItemsAndShowsRetryAfterGuidance() async {
        let repository = RecordingFeedItemsRepository(
            firstPageResults: [
                .success(snapshot(feedID: "feed-1", filter: .all, items: [item(id: "existing")], canLoadMore: true))
            ],
            manualFetchResults: [.failure(cooldownError(retryAfterSeconds: 120, retryAfter: "180"))]
        )
        let viewModel = FeedViewModel(repository: repository)

        await viewModel.loadInitialIfNeeded(feedID: "feed-1")
        await viewModel.refreshFeed(feedID: "feed-1", subscriptionID: "sub-feed-1")

        XCTAssertEqual(viewModel.state, .loaded)
        XCTAssertEqual(viewModel.items.map(\.id), ["existing"])
        XCTAssertTrue(viewModel.canLoadMore)
        XCTAssertEqual(viewModel.refreshFeedback?.style, .warning)
        XCTAssertEqual(
            viewModel.refreshFeedback?.message,
            "このフィードは取得間隔の制限中です。約 120 秒後にもう一度お試しください。"
        )
        let calls = await repository.calls()
        XCTAssertEqual(
            calls,
            [
                .firstPage(feedID: "feed-1", filter: .all, limit: nil),
                .manualFetch(subscriptionID: "sub-feed-1")
            ]
        )
    }

    func testManualRefreshCooldownUsesRetryAfterHeaderFallback() async {
        let repository = RecordingFeedItemsRepository(
            firstPageResults: [
                .success(snapshot(feedID: "feed-1", filter: .all, items: [item(id: "existing")], canLoadMore: false))
            ],
            manualFetchResults: [.failure(cooldownError(retryAfterSeconds: nil, retryAfter: "90"))]
        )
        let viewModel = FeedViewModel(repository: repository)

        await viewModel.loadInitialIfNeeded(feedID: "feed-1")
        await viewModel.refreshFeed(feedID: "feed-1", subscriptionID: "sub-feed-1")

        XCTAssertEqual(
            viewModel.refreshFeedback?.message,
            "このフィードは取得間隔の制限中です。約 90 秒後にもう一度お試しください。"
        )
        XCTAssertEqual(viewModel.items.map(\.id), ["existing"])
    }

    func testManualRefreshGenericErrorPreservesItemsAndShowsFailureGuidance() async {
        let repository = RecordingFeedItemsRepository(
            firstPageResults: [
                .success(snapshot(feedID: "feed-1", filter: .all, items: [item(id: "existing")], canLoadMore: true))
            ],
            manualFetchResults: [.failure(FeedViewModelTestError.transport)]
        )
        let viewModel = FeedViewModel(repository: repository)

        await viewModel.loadInitialIfNeeded(feedID: "feed-1")
        await viewModel.refreshFeed(feedID: "feed-1", subscriptionID: "sub-feed-1")

        XCTAssertEqual(viewModel.state, .loaded)
        XCTAssertEqual(viewModel.items.map(\.id), ["existing"])
        XCTAssertTrue(viewModel.canLoadMore)
        XCTAssertEqual(
            viewModel.refreshFeedback?.message,
            "フィードを更新できませんでした。しばらく待ってからもう一度お試しください。"
        )
        let calls = await repository.calls()
        XCTAssertEqual(
            calls,
            [
                .firstPage(feedID: "feed-1", filter: .all, limit: nil),
                .manualFetch(subscriptionID: "sub-feed-1")
            ]
        )
    }

    func testManualRefreshMissingSubscriptionIDDoesNotCallFetch() async {
        let repository = RecordingFeedItemsRepository(
            firstPageResults: [
                .success(snapshot(feedID: "feed-1", filter: .all, items: [item(id: "existing")], canLoadMore: false))
            ],
            manualFetchResults: [.success(())]
        )
        let viewModel = FeedViewModel(repository: repository)

        await viewModel.loadInitialIfNeeded(feedID: "feed-1")
        await viewModel.refreshFeed(feedID: "feed-1", subscriptionID: "   \n")

        XCTAssertEqual(viewModel.items.map(\.id), ["existing"])
        XCTAssertEqual(
            viewModel.refreshFeedback?.message,
            "このフィードは手動更新に必要な購読情報がありません。"
        )
        let calls = await repository.calls()
        XCTAssertEqual(calls, [.firstPage(feedID: "feed-1", filter: .all, limit: nil)])
    }

    func testDuplicateManualRefreshSuppressesDuplicateFetch() async {
        let repository = PausedManualFetchRepository(
            firstPageResults: [
                .success(snapshot(feedID: "feed-1", filter: .all, items: [item(id: "initial")], canLoadMore: false)),
                .success(snapshot(feedID: "feed-1", filter: .all, items: [item(id: "reloaded")], canLoadMore: false))
            ]
        )
        let viewModel = FeedViewModel(repository: repository)

        await viewModel.loadInitialIfNeeded(feedID: "feed-1")
        let refreshTask = Task { @MainActor in
            await viewModel.refreshFeed(feedID: "feed-1", subscriptionID: "sub-feed-1")
        }
        await repository.waitForManualFetchStart()

        await viewModel.refreshFeed(feedID: "feed-1", subscriptionID: "sub-feed-1")

        let callsDuringRefresh = await repository.calls()
        XCTAssertEqual(
            callsDuringRefresh,
            [
                .firstPage(feedID: "feed-1", filter: .all, limit: nil),
                .manualFetch(subscriptionID: "sub-feed-1")
            ]
        )

        await repository.completeManualFetch(with: .success(()))
        await refreshTask.value

        XCTAssertEqual(viewModel.items.map(\.id), ["reloaded"])
        let calls = await repository.calls()
        XCTAssertEqual(
            calls,
            [
                .firstPage(feedID: "feed-1", filter: .all, limit: nil),
                .manualFetch(subscriptionID: "sub-feed-1"),
                .firstPage(feedID: "feed-1", filter: .all, limit: nil)
            ]
        )
    }

    private func snapshot(
        feedID: String,
        filter: FeedItemFilter,
        items: [ItemSummary],
        canLoadMore: Bool
    ) -> FeedItemPaginationSnapshot {
        FeedItemPaginationSnapshot(
            items: items,
            nextCursor: canLoadMore ? "next" : nil,
            canLoadMore: canLoadMore,
            feedID: feedID,
            filter: filter,
            limit: CrossFeedPageLimit.defaultValue
        )
    }

    private func item(
        id: String,
        feedID: String = "feed-1",
        feedTitle: String = "Feed",
        feedFaviconURL: String? = nil,
        summary: String? = "Summary",
        link: String? = nil,
        publishedAt: String = "2026-06-08T08:30:00Z",
        isDateEstimated: Bool = false,
        isRead: Bool = false,
        isStarred: Bool = false,
        hatebuCount: Int? = nil,
        hatebuFetchedAt: String? = nil
    ) -> ItemSummary {
        ItemSummary(
            id: id,
            feedID: feedID,
            feedTitle: feedTitle,
            feedFaviconURL: feedFaviconURL,
            title: "Title \(id)",
            summary: summary,
            link: link ?? "https://example.com/\(id)",
            publishedAt: publishedAt,
            isDateEstimated: isDateEstimated,
            isRead: isRead,
            isStarred: isStarred,
            hatebuCount: hatebuCount,
            hatebuFetchedAt: hatebuFetchedAt,
            author: nil
        )
    }

    private func cooldownError(
        retryAfterSeconds: Int?,
        retryAfter: String?
    ) -> FeedmanAPIError {
        FeedmanAPIError.feedmanError(
            FeedmanErrorContext(
                statusCode: 429,
                body: FeedmanErrorBody(
                    code: "FEED_COOLDOWN",
                    message: "cooldown",
                    category: "rate_limit",
                    action: "retry_later",
                    details: retryAfterSeconds.map {
                        ["retry_after_seconds": .int($0)]
                    }
                ),
                retryAfter: retryAfter
            )
        )
    }
}

private enum FeedViewModelTestError: Error {
    case transport
}

private enum FeedItemsRepositoryCall: Equatable {
    case firstPage(feedID: String, filter: FeedItemFilter, limit: Int?)
    case manualFetch(subscriptionID: String)
    case nextPage
}

private actor RecordingFeedItemsRepository: FeedRepository {
    private var recordedCalls: [FeedItemsRepositoryCall] = []
    private var firstPageResults: [Result<FeedItemPaginationSnapshot, Error>]
    private var manualFetchResults: [Result<Void, Error>]
    private var nextPageResults: [Result<FeedItemPaginationSnapshot, Error>]

    init(
        firstPageResults: [Result<FeedItemPaginationSnapshot, Error>],
        manualFetchResults: [Result<Void, Error>] = [],
        nextPageResults: [Result<FeedItemPaginationSnapshot, Error>] = []
    ) {
        self.firstPageResults = firstPageResults
        self.manualFetchResults = manualFetchResults
        self.nextPageResults = nextPageResults
    }

    func calls() -> [FeedItemsRepositoryCall] {
        recordedCalls
    }

    func subscriptions() async throws -> [Feed] {
        []
    }

    func registerFeed(url: String) async throws -> RegisteredFeed {
        throw FeedItemRepositoryError.paginationUnsupported
    }

    func crossFeedItems() async throws -> [FeedItem] {
        []
    }

    func loadCrossFeedFirstPage(limit: Int?) async throws -> CrossFeedPaginationSnapshot {
        throw CrossFeedRepositoryError.paginationUnsupported
    }

    func loadCrossFeedNextPage() async throws -> CrossFeedPaginationSnapshot {
        throw CrossFeedRepositoryError.paginationUnsupported
    }

    func manualFetchSubscription(subscriptionID: String) async throws {
        recordedCalls.append(.manualFetch(subscriptionID: subscriptionID))
        guard !manualFetchResults.isEmpty else {
            return
        }

        try manualFetchResults.removeFirst().get()
    }

    func loadFeedItemsFirstPage(
        feedID: String,
        filter: FeedItemFilter,
        limit: Int?
    ) async throws -> FeedItemPaginationSnapshot {
        recordedCalls.append(.firstPage(feedID: feedID, filter: filter, limit: limit))
        return try nextResult(from: &firstPageResults)
    }

    func loadFeedItemsNextPage() async throws -> FeedItemPaginationSnapshot {
        recordedCalls.append(.nextPage)
        return try nextResult(from: &nextPageResults)
    }

    private func nextResult(
        from results: inout [Result<FeedItemPaginationSnapshot, Error>]
    ) throws -> FeedItemPaginationSnapshot {
        guard !results.isEmpty else {
            throw FeedViewModelTestError.transport
        }

        return try results.removeFirst().get()
    }
}

private actor PausedNextPageFeedItemsRepository: FeedRepository {
    private var recordedCalls: [FeedItemsRepositoryCall] = []
    private var firstPageResults: [Result<FeedItemPaginationSnapshot, Error>]
    private var nextPageContinuation: CheckedContinuation<FeedItemPaginationSnapshot, Error>?
    private var nextPageStartedContinuation: CheckedContinuation<Void, Never>?

    init(firstPageResults: [Result<FeedItemPaginationSnapshot, Error>]) {
        self.firstPageResults = firstPageResults
    }

    func calls() -> [FeedItemsRepositoryCall] {
        recordedCalls
    }

    func waitForNextPageStart() async {
        if recordedCalls.contains(.nextPage) {
            return
        }

        await withCheckedContinuation { continuation in
            nextPageStartedContinuation = continuation
        }
    }

    func completeNextPage(with result: Result<FeedItemPaginationSnapshot, Error>) {
        guard let nextPageContinuation else {
            return
        }

        self.nextPageContinuation = nil
        nextPageContinuation.resume(with: result)
    }

    func subscriptions() async throws -> [Feed] {
        []
    }

    func registerFeed(url: String) async throws -> RegisteredFeed {
        throw FeedItemRepositoryError.paginationUnsupported
    }

    func crossFeedItems() async throws -> [FeedItem] {
        []
    }

    func loadCrossFeedFirstPage(limit: Int?) async throws -> CrossFeedPaginationSnapshot {
        throw CrossFeedRepositoryError.paginationUnsupported
    }

    func loadCrossFeedNextPage() async throws -> CrossFeedPaginationSnapshot {
        throw CrossFeedRepositoryError.paginationUnsupported
    }

    func manualFetchSubscription(subscriptionID: String) async throws {
        recordedCalls.append(.manualFetch(subscriptionID: subscriptionID))
    }

    func loadFeedItemsFirstPage(
        feedID: String,
        filter: FeedItemFilter,
        limit: Int?
    ) async throws -> FeedItemPaginationSnapshot {
        recordedCalls.append(.firstPage(feedID: feedID, filter: filter, limit: limit))
        return try nextFirstPageResult()
    }

    func loadFeedItemsNextPage() async throws -> FeedItemPaginationSnapshot {
        recordedCalls.append(.nextPage)
        nextPageStartedContinuation?.resume()
        nextPageStartedContinuation = nil

        return try await withCheckedThrowingContinuation { continuation in
            nextPageContinuation = continuation
        }
    }

    private func nextFirstPageResult() throws -> FeedItemPaginationSnapshot {
        guard !firstPageResults.isEmpty else {
            throw FeedViewModelTestError.transport
        }

        return try firstPageResults.removeFirst().get()
    }
}

private actor PausedManualFetchRepository: FeedRepository {
    private var recordedCalls: [FeedItemsRepositoryCall] = []
    private var firstPageResults: [Result<FeedItemPaginationSnapshot, Error>]
    private var manualFetchContinuation: CheckedContinuation<Void, Error>?
    private var manualFetchStartedContinuation: CheckedContinuation<Void, Never>?

    init(firstPageResults: [Result<FeedItemPaginationSnapshot, Error>]) {
        self.firstPageResults = firstPageResults
    }

    func calls() -> [FeedItemsRepositoryCall] {
        recordedCalls
    }

    func waitForManualFetchStart() async {
        if recordedCalls.contains(.manualFetch(subscriptionID: "sub-feed-1")) {
            return
        }

        await withCheckedContinuation { continuation in
            manualFetchStartedContinuation = continuation
        }
    }

    func completeManualFetch(with result: Result<Void, Error>) {
        guard let manualFetchContinuation else {
            return
        }

        self.manualFetchContinuation = nil
        manualFetchContinuation.resume(with: result)
    }

    func subscriptions() async throws -> [Feed] {
        []
    }

    func registerFeed(url: String) async throws -> RegisteredFeed {
        throw FeedItemRepositoryError.paginationUnsupported
    }

    func crossFeedItems() async throws -> [FeedItem] {
        []
    }

    func loadCrossFeedFirstPage(limit: Int?) async throws -> CrossFeedPaginationSnapshot {
        throw CrossFeedRepositoryError.paginationUnsupported
    }

    func loadCrossFeedNextPage() async throws -> CrossFeedPaginationSnapshot {
        throw CrossFeedRepositoryError.paginationUnsupported
    }

    func manualFetchSubscription(subscriptionID: String) async throws {
        recordedCalls.append(.manualFetch(subscriptionID: subscriptionID))
        manualFetchStartedContinuation?.resume()
        manualFetchStartedContinuation = nil

        return try await withCheckedThrowingContinuation { continuation in
            manualFetchContinuation = continuation
        }
    }

    func loadFeedItemsFirstPage(
        feedID: String,
        filter: FeedItemFilter,
        limit: Int?
    ) async throws -> FeedItemPaginationSnapshot {
        recordedCalls.append(.firstPage(feedID: feedID, filter: filter, limit: limit))
        guard !firstPageResults.isEmpty else {
            throw FeedViewModelTestError.transport
        }

        return try firstPageResults.removeFirst().get()
    }

    func loadFeedItemsNextPage() async throws -> FeedItemPaginationSnapshot {
        recordedCalls.append(.nextPage)
        throw FeedItemRepositoryError.nextPageRequestedBeforeFirstPage
    }
}
