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
        XCTAssertEqual(await repository.calls(), [.firstPage(limit: nil)])
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
        XCTAssertEqual(await repository.calls(), [.firstPage(limit: nil), .firstPage(limit: nil)])
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
        XCTAssertEqual(await repository.calls(), [.firstPage(limit: nil), .nextPage])
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
        XCTAssertEqual(viewModel.nextPageErrorMessage, "続きを読み込めませんでした。")

        await viewModel.retryNextPage()

        XCTAssertEqual(viewModel.items.map(\.id), ["first", "second"])
        XCTAssertNil(viewModel.nextPageErrorMessage)
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
        XCTAssertEqual(await repository.calls(), [.firstPage(limit: nil)])
    }

    func testLocalStarToggleDoesNotCallRepositoryMutation() async throws {
        let repository = RecordingTimelineFeedRepository(
            firstPageResults: [
                .success(snapshot(items: [item(id: "target", isStarred: false)], canLoadMore: false))
            ]
        )
        let viewModel = TimelineViewModel(repository: repository)

        await viewModel.loadInitialIfNeeded()
        viewModel.toggleStar(id: "target")

        XCTAssertTrue(XCTUnwrap(viewModel.items.first).isStarred)
        XCTAssertEqual(await repository.calls(), [.firstPage(limit: nil)])
    }

    func testLocalStarToggleSurvivesPaginationSnapshotReplacement() async throws {
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
        let viewModel = TimelineViewModel(repository: repository)

        await viewModel.loadInitialIfNeeded()
        viewModel.toggleStar(id: "target")
        await viewModel.loadNextPageIfNeeded(currentItemID: "target")

        XCTAssertTrue(try XCTUnwrap(viewModel.items.first { $0.id == "target" }).isStarred)
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
