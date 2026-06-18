import XCTest
@testable import Feedman

@MainActor
final class TimelineViewModelTests: XCTestCase {
    func testInitialLoadSuccessExposesLoadedItems() async {
        let firstPage = snapshot(items: [item(id: "first"), item(id: "second")], canLoadMore: true)
        let repository = RecordingTimelineFeedRepository(firstPageResults: [.success(firstPage)])
        let viewModel = TimelineViewModel(repository: repository)

        await viewModel.loadInitialIfNeeded()

        XCTAssertEqual(viewModel.state, .loaded)
        XCTAssertEqual(viewModel.items.map(\.id), ["first", "second"])
        XCTAssertTrue(viewModel.canLoadMore)
        let calls = await repository.calls()
        XCTAssertEqual(calls, [.firstPage(limit: nil)])
    }

    func testInitialLoadEmptyPageExposesEmptyState() async {
        let repository = RecordingTimelineFeedRepository(
            firstPageResults: [.success(snapshot(items: [], canLoadMore: false))]
        )
        let viewModel = TimelineViewModel(repository: repository)

        await viewModel.loadInitialIfNeeded()

        XCTAssertEqual(viewModel.state, .empty)
        XCTAssertEqual(viewModel.items, [])
        XCTAssertFalse(viewModel.canLoadMore)
    }

    func testInitialLoadEmptyStateDoesNotRefetchOnRouteReturn() async {
        let repository = RecordingTimelineFeedRepository(
            firstPageResults: [
                .success(snapshot(items: [], canLoadMore: false)),
                .success(snapshot(items: [item(id: "unexpected")], canLoadMore: false))
            ]
        )
        let viewModel = TimelineViewModel(repository: repository)

        await viewModel.loadInitialIfNeeded()
        await viewModel.loadInitialIfNeeded()

        XCTAssertEqual(viewModel.state, .empty)
        XCTAssertEqual(viewModel.items, [])
        let calls = await repository.calls()
        XCTAssertEqual(calls, [.firstPage(limit: nil)])
    }

    func testInitialLoadWithExistingItemsDoesNotRefetchOnRouteReturn() async {
        let repository = RecordingTimelineFeedRepository(
            firstPageResults: [
                .success(snapshot(items: [item(id: "unexpected")], canLoadMore: false))
            ]
        )
        let existingItem = item(id: "existing")
        let viewModel = TimelineViewModel(
            repository: repository,
            state: .loaded,
            items: [existingItem],
            canLoadMore: false
        )

        await viewModel.loadInitialIfNeeded()

        XCTAssertEqual(viewModel.state, .loaded)
        XCTAssertEqual(viewModel.items, [existingItem])
        let calls = await repository.calls()
        XCTAssertEqual(calls, [])
    }

    func testInitialLoadFailureCanRetryFirstPage() async {
        let repository = RecordingTimelineFeedRepository(
            firstPageResults: [
                .failure(TimelineViewModelTestError.transport),
                .success(snapshot(items: [item(id: "recovered")], canLoadMore: false))
            ]
        )
        let viewModel = TimelineViewModel(repository: repository)

        await viewModel.loadInitialIfNeeded()

        XCTAssertEqual(viewModel.state, .failed(message: "タイムラインを読み込めませんでした。"))
        XCTAssertEqual(viewModel.items, [])

        await viewModel.retryInitialLoad()

        XCTAssertEqual(viewModel.state, .loaded)
        XCTAssertEqual(viewModel.items.map(\.id), ["recovered"])
        let calls = await repository.calls()
        XCTAssertEqual(calls, [.firstPage(limit: nil), .firstPage(limit: nil)])
    }

    func testRefreshSuccessReplacesItemsAndClearsNextPageError() async {
        let repository = RecordingTimelineFeedRepository(
            firstPageResults: [
                .success(snapshot(items: [item(id: "existing")], canLoadMore: true)),
                .success(snapshot(items: [item(id: "refreshed")], canLoadMore: false))
            ],
            nextPageResults: [
                .failure(TimelineViewModelTestError.transport)
            ]
        )
        let viewModel = TimelineViewModel(repository: repository)

        await viewModel.loadInitialIfNeeded()
        await viewModel.loadNextPageIfNeeded(currentItemID: "existing")
        await viewModel.refresh()

        XCTAssertEqual(viewModel.state, .loaded)
        XCTAssertEqual(viewModel.items.map(\.id), ["refreshed"])
        XCTAssertFalse(viewModel.canLoadMore)
        XCTAssertNil(viewModel.nextPageErrorMessage)
    }

    func testRefreshSuccessWithEmptyPageClearsExistingItemsAndRefreshError() async {
        let repository = RecordingTimelineFeedRepository(
            firstPageResults: [
                .success(snapshot(items: [item(id: "existing")], canLoadMore: true)),
                .failure(TimelineViewModelTestError.transport),
                .success(snapshot(items: [], canLoadMore: false))
            ]
        )
        let viewModel = TimelineViewModel(repository: repository)

        await viewModel.loadInitialIfNeeded()
        await viewModel.refresh()
        await viewModel.refresh()

        XCTAssertEqual(viewModel.state, .empty)
        XCTAssertEqual(viewModel.items, [])
        XCTAssertFalse(viewModel.canLoadMore)
        XCTAssertNil(viewModel.refreshErrorMessage)
    }

    func testRefreshFailurePreservesExistingItems() async {
        let repository = RecordingTimelineFeedRepository(
            firstPageResults: [
                .success(snapshot(items: [item(id: "existing")], canLoadMore: true)),
                .failure(TimelineViewModelTestError.transport)
            ]
        )
        let viewModel = TimelineViewModel(repository: repository)

        await viewModel.loadInitialIfNeeded()
        await viewModel.refresh()

        XCTAssertEqual(viewModel.state, .loaded)
        XCTAssertEqual(viewModel.items.map(\.id), ["existing"])
        XCTAssertEqual(viewModel.refreshErrorMessage, "タイムラインを更新できませんでした。")
    }

    func testRefreshFailureBeforeItemsExposesInitialRecoverableError() async {
        let repository = RecordingTimelineFeedRepository(
            firstPageResults: [.failure(TimelineViewModelTestError.transport)]
        )
        let viewModel = TimelineViewModel(repository: repository)

        await viewModel.refresh()

        XCTAssertEqual(viewModel.state, .failed(message: "タイムラインを読み込めませんでした。"))
        XCTAssertEqual(viewModel.items, [])
        XCTAssertFalse(viewModel.canLoadMore)
    }

    func testRefreshSuccessPreservesLocalStarOverrideForSameItem() async throws {
        let repository = RecordingTimelineFeedRepository(
            firstPageResults: [
                .success(snapshot(
                    items: [item(id: "target", summary: "Original Summary", isStarred: false)],
                    canLoadMore: true
                )),
                .success(snapshot(
                    items: [item(id: "target", summary: "Refreshed Summary", isStarred: false)],
                    canLoadMore: false
                ))
            ]
        )
        let itemRepository = MockItemRepository()
        let viewModel = TimelineViewModel(
            repository: repository,
            itemRepository: itemRepository,
            accessToken: "test-access-token"
        )

        await viewModel.loadInitialIfNeeded()
        await viewModel.toggleStar(id: "target")
        await viewModel.refresh()

        let refreshedItem = try XCTUnwrap(viewModel.items.first { $0.id == "target" })
        XCTAssertTrue(viewModel.descriptor(for: refreshedItem).isStarred)
        XCTAssertEqual(refreshedItem.summary, "Refreshed Summary")
        XCTAssertFalse(viewModel.canLoadMore)
        let calls = await repository.calls()
        XCTAssertEqual(calls, [.firstPage(limit: nil), .firstPage(limit: nil)])
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

    func testNextPageSuccessAppendsItemsInRepositoryOrder() async {
        let repository = RecordingTimelineFeedRepository(
            firstPageResults: [
                .success(snapshot(items: [item(id: "first")], canLoadMore: true))
            ],
            nextPageResults: [
                .success(snapshot(items: [item(id: "first"), item(id: "second")], canLoadMore: false))
            ]
        )
        let viewModel = TimelineViewModel(repository: repository)

        await viewModel.loadInitialIfNeeded()
        await viewModel.loadNextPageIfNeeded(currentItemID: "first")

        XCTAssertEqual(viewModel.items.map(\.id), ["first", "second"])
        XCTAssertFalse(viewModel.canLoadMore)
        XCTAssertEqual(viewModel.state, .loaded)
        let calls = await repository.calls()
        XCTAssertEqual(calls, [.firstPage(limit: nil), .nextPage])
    }

    func testNonLastSentinelDoesNotRequestNextPage() async {
        let repository = RecordingTimelineFeedRepository(
            firstPageResults: [
                .success(snapshot(items: [item(id: "first"), item(id: "last")], canLoadMore: true))
            ],
            nextPageResults: [
                .success(snapshot(items: [item(id: "unexpected")], canLoadMore: false))
            ]
        )
        let viewModel = TimelineViewModel(repository: repository)

        await viewModel.loadInitialIfNeeded()
        await viewModel.loadNextPageIfNeeded(currentItemID: "first")

        XCTAssertEqual(viewModel.items.map(\.id), ["first", "last"])
        let calls = await repository.calls()
        XCTAssertEqual(calls, [.firstPage(limit: nil)])
    }

    func testNextPageFailurePreservesExistingItemsAndShowsRetryableError() async {
        let repository = RecordingTimelineFeedRepository(
            firstPageResults: [
                .success(snapshot(items: [item(id: "first")], canLoadMore: true))
            ],
            nextPageResults: [
                .failure(TimelineViewModelTestError.transport),
                .success(snapshot(items: [item(id: "first"), item(id: "second")], canLoadMore: false))
            ]
        )
        let viewModel = TimelineViewModel(repository: repository)

        await viewModel.loadInitialIfNeeded()
        await viewModel.loadNextPageIfNeeded(currentItemID: "first")

        XCTAssertEqual(viewModel.items.map(\.id), ["first"])
        XCTAssertTrue(viewModel.canLoadMore)
        XCTAssertEqual(viewModel.nextPageErrorMessage, "続きを読み込めませんでした。")

        await viewModel.retryNextPage()

        XCTAssertEqual(viewModel.items.map(\.id), ["first", "second"])
        XCTAssertNil(viewModel.nextPageErrorMessage)
        let calls = await repository.calls()
        XCTAssertEqual(calls, [.firstPage(limit: nil), .nextPage, .nextPage])
    }

    func testDuplicateRefreshIsIgnoredWhileFirstPageIsLoading() async {
        let repository = SuspendedTimelineFeedRepository(
            firstPageResult: snapshot(items: [item(id: "refreshed")], canLoadMore: false),
            nextPageResult: snapshot(items: [], canLoadMore: false),
            suspendFirstPage: true
        )
        let viewModel = TimelineViewModel(repository: repository)

        let refreshTask = Task { @MainActor in
            await viewModel.refresh()
        }
        await repository.waitForCallCount(1)

        await viewModel.refresh()

        var calls = await repository.calls()
        XCTAssertEqual(calls, [.firstPage(limit: nil)])

        await repository.resumeFirstPage()
        await refreshTask.value

        calls = await repository.calls()
        XCTAssertEqual(calls, [.firstPage(limit: nil)])
    }

    func testNextPageIsIgnoredWhileRefreshIsLoading() async {
        let repository = SuspendedTimelineFeedRepository(
            firstPageResult: snapshot(items: [item(id: "refreshed")], canLoadMore: false),
            nextPageResult: snapshot(items: [item(id: "existing"), item(id: "unexpected")], canLoadMore: false),
            suspendFirstPage: true
        )
        let viewModel = TimelineViewModel(
            repository: repository,
            state: .loaded,
            items: [item(id: "existing")],
            canLoadMore: true
        )

        let refreshTask = Task { @MainActor in
            await viewModel.refresh()
        }
        await repository.waitForCallCount(1)

        await viewModel.loadNextPageIfNeeded(currentItemID: "existing")

        let calls = await repository.calls()
        XCTAssertEqual(calls, [.firstPage(limit: nil)])

        await repository.resumeFirstPage()
        await refreshTask.value
    }

    func testDuplicateNextPageRequestIsIgnoredWhileNextPageIsLoading() async {
        let repository = SuspendedTimelineFeedRepository(
            firstPageResult: snapshot(items: [item(id: "first")], canLoadMore: true),
            nextPageResult: snapshot(items: [item(id: "first"), item(id: "second")], canLoadMore: false),
            suspendNextPage: true
        )
        let viewModel = TimelineViewModel(repository: repository)

        await viewModel.loadInitialIfNeeded()
        let nextPageTask = Task { @MainActor in
            await viewModel.loadNextPageIfNeeded(currentItemID: "first")
        }
        await repository.waitForCallCount(2)

        await viewModel.loadNextPageIfNeeded(currentItemID: "first")

        let calls = await repository.calls()
        XCTAssertEqual(calls, [.firstPage(limit: nil), .nextPage])

        await repository.resumeNextPage()
        await nextPageTask.value
    }

    func testTerminalStateDoesNotRequestNextPage() async {
        let repository = RecordingTimelineFeedRepository(
            firstPageResults: [
                .success(snapshot(items: [item(id: "only")], canLoadMore: false))
            ],
            nextPageResults: [
                .success(snapshot(items: [item(id: "unexpected")], canLoadMore: false))
            ]
        )
        let viewModel = TimelineViewModel(repository: repository)

        await viewModel.loadInitialIfNeeded()
        await viewModel.loadNextPageIfNeeded(currentItemID: "only")

        XCTAssertEqual(viewModel.items.map(\.id), ["only"])
        let calls = await repository.calls()
        XCTAssertEqual(calls, [.firstPage(limit: nil)])
    }

    func testStarToggleCallsRepositoryMutationAndUpdatesEffectiveState() async throws {
        let repository = RecordingTimelineFeedRepository(
            firstPageResults: [
                .success(snapshot(items: [item(id: "target", isStarred: false)], canLoadMore: false))
            ]
        )
        let itemRepository = MockItemRepository()
        let viewModel = TimelineViewModel(
            repository: repository,
            itemRepository: itemRepository,
            accessToken: "test-access-token"
        )

        await viewModel.loadInitialIfNeeded()
        await viewModel.toggleStar(id: "target")

        let firstItem = try XCTUnwrap(viewModel.items.first)
        XCTAssertTrue(viewModel.descriptor(for: firstItem).isStarred)
        let calls = await repository.calls()
        XCTAssertEqual(calls, [.firstPage(limit: nil)])
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

    func testCardStarSuccessSyncsVisibleTimelineAndLoadedDetail() async throws {
        let coordinator = ItemStateCoordinator()
        let repository = RecordingTimelineFeedRepository(
            firstPageResults: [
                .success(snapshot(items: [item(id: "target", isRead: true, isStarred: false)], canLoadMore: false))
            ]
        )
        let itemRepository = MockItemRepository(
            itemDetails: ["target": detail(id: "target", isRead: true, isStarred: false)]
        )
        let timelineViewModel = TimelineViewModel(
            repository: repository,
            itemRepository: itemRepository,
            accessToken: "test-access-token",
            itemStateCoordinator: coordinator
        )
        let detailViewModel = ArticleDetailViewModel(
            itemID: "target",
            summary: ArticleDetailSummary(item: item(id: "target", isRead: true, isStarred: false)),
            repository: itemRepository,
            accessToken: "test-access-token",
            itemStateCoordinator: coordinator
        )

        await timelineViewModel.loadInitialIfNeeded()
        await detailViewModel.open()
        await timelineViewModel.toggleStar(id: "target")
        await Task.yield()

        let timelineItem = try XCTUnwrap(timelineViewModel.items.first { $0.id == "target" })
        XCTAssertTrue(timelineViewModel.descriptor(for: timelineItem).isStarred)
        XCTAssertEqual(detailViewModel.loadedPresentation?.isStarred, true)
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
        let repository = RecordingTimelineFeedRepository(
            firstPageResults: [
                .success(snapshot(items: [item(id: "target", isStarred: false)], canLoadMore: false))
            ]
        )
        let itemRepository = MockItemRepository(stateUpdateFailure: TimelineViewModelTestError.transport)
        let viewModel = TimelineViewModel(
            repository: repository,
            itemRepository: itemRepository,
            accessToken: "test-access-token"
        )

        await viewModel.loadInitialIfNeeded()
        viewModel.selectItem(id: "target")
        await viewModel.toggleStar(id: "target")

        let firstItem = try XCTUnwrap(viewModel.items.first)
        XCTAssertFalse(viewModel.descriptor(for: firstItem).isStarred)
        XCTAssertEqual(viewModel.starMutationErrorMessage, "スターを更新できませんでした。")
        XCTAssertEqual(viewModel.selectedItemID, "target")
    }

    func testCardStarFailureRollsBackVisibleTimelineAndLoadedDetail() async throws {
        let coordinator = ItemStateCoordinator()
        let repository = RecordingTimelineFeedRepository(
            firstPageResults: [
                .success(snapshot(items: [item(id: "target", isRead: true, isStarred: false)], canLoadMore: false))
            ]
        )
        let itemRepository = MockItemRepository(
            itemDetails: ["target": detail(id: "target", isRead: true, isStarred: false)],
            stateUpdateFailure: TimelineViewModelTestError.transport
        )
        let timelineViewModel = TimelineViewModel(
            repository: repository,
            itemRepository: itemRepository,
            accessToken: "test-access-token",
            itemStateCoordinator: coordinator
        )
        let detailViewModel = ArticleDetailViewModel(
            itemID: "target",
            summary: ArticleDetailSummary(item: item(id: "target", isRead: true, isStarred: false)),
            repository: itemRepository,
            accessToken: "test-access-token",
            itemStateCoordinator: coordinator
        )

        await timelineViewModel.loadInitialIfNeeded()
        await detailViewModel.open()
        await timelineViewModel.toggleStar(id: "target")
        await Task.yield()

        let timelineItem = try XCTUnwrap(timelineViewModel.items.first { $0.id == "target" })
        XCTAssertFalse(timelineViewModel.descriptor(for: timelineItem).isStarred)
        XCTAssertEqual(detailViewModel.loadedPresentation?.isStarred, false)
        XCTAssertEqual(timelineViewModel.starMutationErrorMessage, "スターを更新できませんでした。")
    }

    func testDetailReadFailurePreservesTimelineSelectionAndLoadedDetail() async throws {
        let coordinator = ItemStateCoordinator()
        let repository = RecordingTimelineFeedRepository(
            firstPageResults: [
                .success(snapshot(items: [item(id: "target", isRead: false, isStarred: false)], canLoadMore: false))
            ]
        )
        let itemRepository = MockItemRepository(
            itemDetails: ["target": detail(id: "target", isRead: false, isStarred: false)],
            stateUpdateFailure: TimelineViewModelTestError.transport
        )
        let timelineViewModel = TimelineViewModel(
            repository: repository,
            itemRepository: itemRepository,
            accessToken: "test-access-token",
            itemStateCoordinator: coordinator
        )

        await timelineViewModel.loadInitialIfNeeded()
        timelineViewModel.selectItem(id: "target")

        let detailViewModel = ArticleDetailViewModel(
            itemID: "target",
            summary: timelineViewModel.detailInput(for: "target").summary,
            repository: itemRepository,
            accessToken: "test-access-token",
            itemStateCoordinator: coordinator
        )

        await detailViewModel.open()
        await Task.yield()

        let timelineItem = try XCTUnwrap(timelineViewModel.items.first { $0.id == "target" })
        XCTAssertEqual(timelineViewModel.selectedItemID, "target")
        XCTAssertFalse(timelineViewModel.descriptor(for: timelineItem).item.isRead)
        XCTAssertEqual(detailViewModel.loadedPresentation?.isRead, false)
        XCTAssertEqual(detailViewModel.mutationMessage?.kind, .read)
        XCTAssertEqual(detailViewModel.mutationMessage?.message, "既読状態を更新できませんでした。")
    }

    func testStarToggleSurvivesPaginationSnapshotReplacement() async throws {
        let repository = RecordingTimelineFeedRepository(
            firstPageResults: [
                .success(snapshot(items: [item(id: "target", isStarred: false)], canLoadMore: true))
            ],
            nextPageResults: [
                .success(snapshot(
                    items: [
                        item(id: "target", isStarred: false),
                        item(id: "next", isStarred: false)
                    ],
                    canLoadMore: false
                ))
            ]
        )
        let viewModel = TimelineViewModel(
            repository: repository,
            itemRepository: MockItemRepository(),
            accessToken: "test-access-token"
        )

        await viewModel.loadInitialIfNeeded()
        await viewModel.toggleStar(id: "target")
        await viewModel.loadNextPageIfNeeded(currentItemID: "target")

        let target = try XCTUnwrap(viewModel.items.first { $0.id == "target" })
        XCTAssertTrue(viewModel.descriptor(for: target).isStarred)
        XCTAssertEqual(viewModel.items.map(\.id), ["target", "next"])
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
        let descriptor = TimelineCardDescriptor(item: unread, now: now)

        XCTAssertEqual(descriptor.relativeDate, "2時間前")
        XCTAssertEqual(descriptor.summary, "Summary")
        XCTAssertEqual(descriptor.opacity, 1)
        XCTAssertEqual(descriptor.accessibilityValue, "未読")
        XCTAssertTrue(descriptor.isStarred)
        XCTAssertEqual(descriptor.hatebuState, .available(12))
        XCTAssertEqual(descriptor.linkURL, URL(string: "https://example.com/unread"))
        XCTAssertEqual(unread.publishedAt, "2026-06-08T08:30:00Z")
    }

    func testDescriptorHandlesReadEmptySummaryUnavailableHatebuEstimatedDateAndBadLink() throws {
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-06-08T10:30:00Z"))
        let descriptor = TimelineCardDescriptor(
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
        XCTAssertEqual(descriptor.accessibilityValue, "既読")
        XCTAssertEqual(descriptor.hatebuState, .unavailable)
        XCTAssertNil(descriptor.linkURL)
    }

    func testDescriptorSeparatesSelectionStarAndOpenLinkIntents() throws {
        let descriptor = TimelineCardDescriptor(item: item(id: "action"))
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

    private func snapshot(
        items: [ItemSummary],
        canLoadMore: Bool
    ) -> CrossFeedPaginationSnapshot {
        CrossFeedPaginationSnapshot(
            items: items,
            nextCursor: canLoadMore ? "next" : nil,
            canLoadMore: canLoadMore,
            sinceTime: "2026-06-08T10:30:00Z",
            limit: CrossFeedPageLimit.defaultValue
        )
    }

    private func item(
        id: String,
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
            feedID: "feed-\(id)",
            feedTitle: "Feed \(id)",
            feedFaviconURL: nil,
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

    private func detail(
        id: String,
        isRead: Bool,
        isStarred: Bool
    ) -> ItemDetail {
        ItemDetail(
            id: id,
            feedID: "feed-\(id)",
            feedTitle: "Feed \(id)",
            feedFaviconURL: nil,
            title: "Title \(id)",
            summary: "Summary",
            content: "<p>Body</p>",
            link: "https://example.com/\(id)",
            publishedAt: "2026-06-08T08:30:00Z",
            isDateEstimated: false,
            isRead: isRead,
            isStarred: isStarred,
            hatebuCount: nil,
            hatebuFetchedAt: nil,
            author: nil
        )
    }
}

private enum TimelineViewModelTestError: Error {
    case transport
}

private enum TimelineRepositoryCall: Equatable {
    case firstPage(limit: Int?)
    case nextPage
}

private actor RecordingTimelineFeedRepository: FeedRepository {
    private var recordedCalls: [TimelineRepositoryCall] = []
    private var firstPageResults: [Result<CrossFeedPaginationSnapshot, Error>]
    private var nextPageResults: [Result<CrossFeedPaginationSnapshot, Error>]

    init(
        firstPageResults: [Result<CrossFeedPaginationSnapshot, Error>],
        nextPageResults: [Result<CrossFeedPaginationSnapshot, Error>] = []
    ) {
        self.firstPageResults = firstPageResults
        self.nextPageResults = nextPageResults
    }

    func calls() -> [TimelineRepositoryCall] {
        recordedCalls
    }

    func subscriptions() async throws -> [Feed] {
        []
    }

    func registerFeed(url: String) async throws -> RegisteredFeed {
        throw CrossFeedRepositoryError.paginationUnsupported
    }

    func crossFeedItems() async throws -> [FeedItem] {
        []
    }

    func loadCrossFeedFirstPage(limit: Int?) async throws -> CrossFeedPaginationSnapshot {
        recordedCalls.append(.firstPage(limit: limit))
        return try nextResult(from: &firstPageResults)
    }

    func loadCrossFeedNextPage() async throws -> CrossFeedPaginationSnapshot {
        recordedCalls.append(.nextPage)
        return try nextResult(from: &nextPageResults)
    }

    func loadFeedItemsFirstPage(
        feedID: String,
        filter: FeedItemFilter,
        limit: Int?
    ) async throws -> FeedItemPaginationSnapshot {
        throw FeedItemRepositoryError.paginationUnsupported
    }

    func loadFeedItemsNextPage() async throws -> FeedItemPaginationSnapshot {
        throw FeedItemRepositoryError.paginationUnsupported
    }

    private func nextResult(
        from results: inout [Result<CrossFeedPaginationSnapshot, Error>]
    ) throws -> CrossFeedPaginationSnapshot {
        guard !results.isEmpty else {
            throw TimelineViewModelTestError.transport
        }

        return try results.removeFirst().get()
    }
}

private actor SuspendedTimelineFeedRepository: FeedRepository {
    private var recordedCalls: [TimelineRepositoryCall] = []
    private let firstPageResult: CrossFeedPaginationSnapshot
    private let nextPageResult: CrossFeedPaginationSnapshot
    private let suspendFirstPage: Bool
    private let suspendNextPage: Bool
    private var firstPageContinuations: [CheckedContinuation<CrossFeedPaginationSnapshot, Error>] = []
    private var nextPageContinuations: [CheckedContinuation<CrossFeedPaginationSnapshot, Error>] = []
    private var callCountWaiters: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []

    init(
        firstPageResult: CrossFeedPaginationSnapshot,
        nextPageResult: CrossFeedPaginationSnapshot,
        suspendFirstPage: Bool = false,
        suspendNextPage: Bool = false
    ) {
        self.firstPageResult = firstPageResult
        self.nextPageResult = nextPageResult
        self.suspendFirstPage = suspendFirstPage
        self.suspendNextPage = suspendNextPage
    }

    func calls() -> [TimelineRepositoryCall] {
        recordedCalls
    }

    func waitForCallCount(_ count: Int) async {
        guard recordedCalls.count < count else {
            return
        }

        await withCheckedContinuation { continuation in
            callCountWaiters.append((count, continuation))
        }
    }

    func resumeFirstPage() {
        let continuations = firstPageContinuations
        firstPageContinuations = []
        continuations.forEach { $0.resume(returning: firstPageResult) }
    }

    func resumeNextPage() {
        let continuations = nextPageContinuations
        nextPageContinuations = []
        continuations.forEach { $0.resume(returning: nextPageResult) }
    }

    func subscriptions() async throws -> [Feed] {
        []
    }

    func registerFeed(url: String) async throws -> RegisteredFeed {
        throw CrossFeedRepositoryError.paginationUnsupported
    }

    func crossFeedItems() async throws -> [FeedItem] {
        []
    }

    func loadCrossFeedFirstPage(limit: Int?) async throws -> CrossFeedPaginationSnapshot {
        record(.firstPage(limit: limit))
        guard suspendFirstPage else {
            return firstPageResult
        }

        return try await withCheckedThrowingContinuation { continuation in
            firstPageContinuations.append(continuation)
        }
    }

    func loadCrossFeedNextPage() async throws -> CrossFeedPaginationSnapshot {
        record(.nextPage)
        guard suspendNextPage else {
            return nextPageResult
        }

        return try await withCheckedThrowingContinuation { continuation in
            nextPageContinuations.append(continuation)
        }
    }

    func loadFeedItemsFirstPage(
        feedID: String,
        filter: FeedItemFilter,
        limit: Int?
    ) async throws -> FeedItemPaginationSnapshot {
        throw FeedItemRepositoryError.paginationUnsupported
    }

    func loadFeedItemsNextPage() async throws -> FeedItemPaginationSnapshot {
        throw FeedItemRepositoryError.paginationUnsupported
    }

    private func record(_ call: TimelineRepositoryCall) {
        recordedCalls.append(call)
        let currentCallCount = recordedCalls.count
        let readyWaiters = callCountWaiters.filter { currentCallCount >= $0.count }
        callCountWaiters.removeAll { currentCallCount >= $0.count }
        readyWaiters.forEach { $0.continuation.resume() }
    }
}
