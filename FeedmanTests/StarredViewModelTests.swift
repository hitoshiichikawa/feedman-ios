import XCTest
@testable import Feedman

@MainActor
final class StarredViewModelTests: XCTestCase {
    func testInitialLoadSuccessExposesLoadedItems() async {
        let repository = RecordingStarredRepository(
            firstPageResults: [
                .success(snapshot(items: [item(id: "first"), item(id: "second")], canLoadMore: true))
            ]
        )
        let viewModel = StarredViewModel(repository: repository)

        await viewModel.loadInitialIfNeeded()

        XCTAssertEqual(viewModel.state, .loaded)
        XCTAssertEqual(viewModel.items.map(\.id), ["first", "second"])
        XCTAssertTrue(viewModel.canLoadMore)
        let calls = await repository.calls()
        XCTAssertEqual(calls, [.firstPage(limit: nil)])
    }

    func testInitialLoadEmptyPageExposesEmptyState() async {
        let repository = RecordingStarredRepository(
            firstPageResults: [.success(snapshot(items: [], canLoadMore: false))]
        )
        let viewModel = StarredViewModel(repository: repository)

        await viewModel.loadInitialIfNeeded()

        XCTAssertEqual(viewModel.state, .empty)
        XCTAssertEqual(viewModel.items, [])
        XCTAssertFalse(viewModel.canLoadMore)
    }

    func testInitialLoadFailureCanRetryFirstPage() async {
        let repository = RecordingStarredRepository(
            firstPageResults: [
                .failure(StarredViewModelTestError.transport),
                .success(snapshot(items: [item(id: "recovered")], canLoadMore: false))
            ]
        )
        let viewModel = StarredViewModel(repository: repository)

        await viewModel.loadInitialIfNeeded()

        XCTAssertEqual(viewModel.state, .failed(message: "お気に入りを読み込めませんでした。"))
        XCTAssertEqual(viewModel.items, [])

        await viewModel.retryInitialLoad()

        XCTAssertEqual(viewModel.state, .loaded)
        XCTAssertEqual(viewModel.items.map(\.id), ["recovered"])
        let calls = await repository.calls()
        XCTAssertEqual(calls, [.firstPage(limit: nil), .firstPage(limit: nil)])
    }

    func testRefreshSuccessReplacesItemsAndClearsNextPageError() async {
        let repository = RecordingStarredRepository(
            firstPageResults: [
                .success(snapshot(items: [item(id: "existing")], canLoadMore: true)),
                .success(snapshot(items: [item(id: "refreshed")], canLoadMore: false))
            ],
            nextPageResults: [
                .failure(StarredViewModelTestError.transport)
            ]
        )
        let viewModel = StarredViewModel(repository: repository)

        await viewModel.loadInitialIfNeeded()
        await viewModel.loadNextPageIfNeeded(currentItemID: "existing")
        await viewModel.refresh()

        XCTAssertEqual(viewModel.state, .loaded)
        XCTAssertEqual(viewModel.items.map(\.id), ["refreshed"])
        XCTAssertFalse(viewModel.canLoadMore)
        XCTAssertNil(viewModel.nextPageErrorMessage)
    }

    func testRefreshFailurePreservesExistingItems() async {
        let repository = RecordingStarredRepository(
            firstPageResults: [
                .success(snapshot(items: [item(id: "existing")], canLoadMore: true)),
                .failure(StarredViewModelTestError.transport)
            ]
        )
        let viewModel = StarredViewModel(repository: repository)

        await viewModel.loadInitialIfNeeded()
        await viewModel.refresh()

        XCTAssertEqual(viewModel.state, .loaded)
        XCTAssertEqual(viewModel.items.map(\.id), ["existing"])
        XCTAssertEqual(viewModel.refreshErrorMessage, "お気に入りを更新できませんでした。")
    }

    func testNextPageSuccessAppendsItemsInRepositoryOrder() async {
        let repository = RecordingStarredRepository(
            firstPageResults: [
                .success(snapshot(items: [item(id: "first")], canLoadMore: true))
            ],
            nextPageResults: [
                .success(snapshot(items: [item(id: "first"), item(id: "second")], canLoadMore: false))
            ]
        )
        let viewModel = StarredViewModel(repository: repository)

        await viewModel.loadInitialIfNeeded()
        await viewModel.loadNextPageIfNeeded(currentItemID: "first")

        XCTAssertEqual(viewModel.items.map(\.id), ["first", "second"])
        XCTAssertFalse(viewModel.canLoadMore)
        let calls = await repository.calls()
        XCTAssertEqual(calls, [.firstPage(limit: nil), .nextPage])
    }

    func testNextPageFailurePreservesExistingItemsAndShowsRetryableError() async {
        let repository = RecordingStarredRepository(
            firstPageResults: [
                .success(snapshot(items: [item(id: "first")], canLoadMore: true))
            ],
            nextPageResults: [
                .failure(StarredViewModelTestError.transport),
                .success(snapshot(items: [item(id: "first"), item(id: "second")], canLoadMore: false))
            ]
        )
        let viewModel = StarredViewModel(repository: repository)

        await viewModel.loadInitialIfNeeded()
        await viewModel.loadNextPageIfNeeded(currentItemID: "first")

        XCTAssertEqual(viewModel.items.map(\.id), ["first"])
        XCTAssertEqual(viewModel.nextPageErrorMessage, "続きを読み込めませんでした。")

        await viewModel.retryNextPage()

        XCTAssertEqual(viewModel.items.map(\.id), ["first", "second"])
        XCTAssertNil(viewModel.nextPageErrorMessage)
    }

    func testUnstarSuccessRemovesItemFromStarredList() async {
        let repository = RecordingStarredRepository(
            firstPageResults: [
                .success(snapshot(items: [item(id: "target"), item(id: "other")], canLoadMore: false))
            ]
        )
        let itemRepository = MockItemRepository()
        let viewModel = StarredViewModel(
            repository: repository,
            itemRepository: itemRepository,
            accessToken: "test-access-token"
        )

        await viewModel.loadInitialIfNeeded()
        await viewModel.toggleStar(id: "target")

        XCTAssertEqual(viewModel.items.map(\.id), ["other"])
        XCTAssertEqual(viewModel.state, .loaded)
        XCTAssertEqual(
            itemRepository.stateUpdates,
            [
                MockItemStateUpdate(
                    itemID: "target",
                    request: ItemStateUpdateRequest(isRead: nil, isStarred: false)
                )
            ]
        )
    }

    func testUnstarFailureRestoresItemAndShowsNonBlockingError() async {
        let repository = RecordingStarredRepository(
            firstPageResults: [
                .success(snapshot(items: [item(id: "target"), item(id: "other")], canLoadMore: false))
            ]
        )
        let itemRepository = MockItemRepository(stateUpdateFailure: StarredViewModelTestError.transport)
        let viewModel = StarredViewModel(
            repository: repository,
            itemRepository: itemRepository,
            accessToken: "test-access-token"
        )

        await viewModel.loadInitialIfNeeded()
        await viewModel.toggleStar(id: "target")

        XCTAssertEqual(viewModel.items.map(\.id), ["target", "other"])
        XCTAssertEqual(viewModel.state, .loaded)
        XCTAssertEqual(viewModel.starMutationErrorMessage, "スターを更新できませんでした。")
        let target = viewModel.items[0]
        XCTAssertTrue(viewModel.descriptor(for: target).isStarred)
    }

    func testArticleDetailUnstarStateChangeRemovesVisibleItem() async {
        let repository = RecordingStarredRepository(
            firstPageResults: [
                .success(snapshot(items: [item(id: "target"), item(id: "other")], canLoadMore: false))
            ]
        )
        let viewModel = StarredViewModel(repository: repository)

        await viewModel.loadInitialIfNeeded()
        viewModel.handleItemStateChange(ItemStateChange(itemID: "target", isRead: nil, isStarred: false))

        XCTAssertEqual(viewModel.items.map(\.id), ["other"])
        XCTAssertEqual(viewModel.state, .loaded)
    }

    func testDescriptorDerivesCardPresentationWithoutMutatingAPIDate() throws {
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-06-08T10:30:00Z"))
        let starredItem = item(
            id: "target",
            summary: "  Summary  ",
            publishedAt: "2026-06-08T08:30:00Z",
            isRead: false,
            hatebuCount: 12,
            hatebuFetchedAt: "2026-06-08T09:00:00Z"
        )
        let descriptor = StarredItemCardDescriptor(item: starredItem, now: now)

        XCTAssertEqual(descriptor.relativeDate, "2時間前")
        XCTAssertEqual(descriptor.summary, "Summary")
        XCTAssertEqual(descriptor.opacity, 1)
        XCTAssertTrue(descriptor.isStarred)
        XCTAssertEqual(descriptor.hatebuState, .available(12))
        XCTAssertEqual(descriptor.linkURL, URL(string: "https://example.com/target"))
        XCTAssertEqual(starredItem.publishedAt, "2026-06-08T08:30:00Z")
    }

    func testDescriptorSeparatesSelectionStarAndOpenLinkIntents() throws {
        let descriptor = StarredItemCardDescriptor(item: item(id: "action"))
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
    ) -> StarredItemPaginationSnapshot {
        StarredItemPaginationSnapshot(
            items: items,
            nextCursor: canLoadMore ? "next" : nil,
            canLoadMore: canLoadMore,
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
        isStarred: Bool = true,
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

private enum StarredViewModelTestError: Error {
    case transport
}

private enum StarredRepositoryCall: Equatable {
    case firstPage(limit: Int?)
    case nextPage
}

private actor RecordingStarredRepository: FeedRepository {
    private var recordedCalls: [StarredRepositoryCall] = []
    private var firstPageResults: [Result<StarredItemPaginationSnapshot, Error>]
    private var nextPageResults: [Result<StarredItemPaginationSnapshot, Error>]

    init(
        firstPageResults: [Result<StarredItemPaginationSnapshot, Error>],
        nextPageResults: [Result<StarredItemPaginationSnapshot, Error>] = []
    ) {
        self.firstPageResults = firstPageResults
        self.nextPageResults = nextPageResults
    }

    func calls() -> [StarredRepositoryCall] {
        recordedCalls
    }

    func subscriptions() async throws -> [Feed] {
        []
    }

    func registerFeed(url: String) async throws -> RegisteredFeed {
        throw StarredItemRepositoryError.paginationUnsupported
    }

    func crossFeedItems() async throws -> [FeedItem] {
        []
    }

    func loadStarredItemsFirstPage(limit: Int?) async throws -> StarredItemPaginationSnapshot {
        recordedCalls.append(.firstPage(limit: limit))
        return try nextResult(from: &firstPageResults)
    }

    func loadStarredItemsNextPage() async throws -> StarredItemPaginationSnapshot {
        recordedCalls.append(.nextPage)
        return try nextResult(from: &nextPageResults)
    }

    private func nextResult(
        from results: inout [Result<StarredItemPaginationSnapshot, Error>]
    ) throws -> StarredItemPaginationSnapshot {
        guard !results.isEmpty else {
            throw StarredViewModelTestError.transport
        }

        return try results.removeFirst().get()
    }
}
