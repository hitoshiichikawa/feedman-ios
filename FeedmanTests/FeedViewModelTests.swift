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

        await viewModel.retryNextPage()

        XCTAssertEqual(viewModel.items.map(\.id), ["first", "second"])
        XCTAssertNil(viewModel.nextPageErrorMessage)
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

    func testLocalStarToggleDoesNotCallRepositoryMutation() async throws {
        let repository = RecordingFeedItemsRepository(
            firstPageResults: [
                .success(snapshot(feedID: "feed-1", filter: .all, items: [item(id: "target", isStarred: false)], canLoadMore: false))
            ]
        )
        let viewModel = FeedViewModel(repository: repository)

        await viewModel.loadInitialIfNeeded(feedID: "feed-1")
        viewModel.toggleStar(id: "target")

        let firstItem = try XCTUnwrap(viewModel.items.first)
        XCTAssertTrue(firstItem.isStarred)
        let calls = await repository.calls()
        XCTAssertEqual(calls, [.firstPage(feedID: "feed-1", filter: .all, limit: nil)])
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
            feedTitle: "Feed",
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
}

private enum FeedViewModelTestError: Error {
    case transport
}

private enum FeedItemsRepositoryCall: Equatable {
    case firstPage(feedID: String, filter: FeedItemFilter, limit: Int?)
    case nextPage
}

private actor RecordingFeedItemsRepository: FeedRepository {
    private var recordedCalls: [FeedItemsRepositoryCall] = []
    private var firstPageResults: [Result<FeedItemPaginationSnapshot, Error>]
    private var nextPageResults: [Result<FeedItemPaginationSnapshot, Error>]

    init(
        firstPageResults: [Result<FeedItemPaginationSnapshot, Error>],
        nextPageResults: [Result<FeedItemPaginationSnapshot, Error>] = []
    ) {
        self.firstPageResults = firstPageResults
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
