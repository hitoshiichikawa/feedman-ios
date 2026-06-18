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

    func testInitialLoadShowsLoadingWhileRepositoryIsInFlight() async {
        let repository = SuspendedStarredRepository(
            firstPageResult: snapshot(items: [item(id: "loaded")], canLoadMore: false)
        )
        let viewModel = StarredViewModel(repository: repository)

        let loadTask = Task { @MainActor in
            await viewModel.loadInitialIfNeeded()
        }
        await repository.waitForCallCount(1)

        XCTAssertEqual(viewModel.state, .loading)
        XCTAssertEqual(viewModel.items, [])

        await repository.resumeFirstPage()
        await loadTask.value

        XCTAssertEqual(viewModel.state, .loaded)
        XCTAssertEqual(viewModel.items.map(\.id), ["loaded"])
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

        XCTAssertEqual(
            viewModel.state,
            .failed(message: "お気に入りを読み込めませんでした。", isAuthRequired: false)
        )
        XCTAssertEqual(viewModel.items, [])

        await viewModel.retryInitialLoad()

        XCTAssertEqual(viewModel.state, .loaded)
        XCTAssertEqual(viewModel.items.map(\.id), ["recovered"])
        let calls = await repository.calls()
        XCTAssertEqual(calls, [.firstPage(limit: nil), .firstPage(limit: nil)])
    }

    func testInitialLoadAuthRequiredCallsBoundaryAndShowsAuthFailure() async {
        let repository = RecordingStarredRepository(
            firstPageResults: [
                .failure(authRequiredError())
            ]
        )
        var authRequiredCount = 0
        let viewModel = StarredViewModel(repository: repository, onAuthRequired: {
            authRequiredCount += 1
        })

        await viewModel.loadInitialIfNeeded()

        XCTAssertEqual(authRequiredCount, 1)
        XCTAssertEqual(
            viewModel.state,
            .failed(
                message: "認証の有効期限が切れました。もう一度ログインしてください。",
                isAuthRequired: true
            )
        )
        XCTAssertEqual(viewModel.items, [])
        XCTAssertFalse(viewModel.canLoadMore)
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
        XCTAssertTrue(viewModel.canLoadMore)
        XCTAssertEqual(viewModel.refreshErrorMessage, "お気に入りを更新できませんでした。")
    }

    func testRefreshAuthRequiredDoesNotTreatExistingItemsAsCurrentSuccess() async {
        let repository = RecordingStarredRepository(
            firstPageResults: [
                .success(snapshot(items: [item(id: "existing")], canLoadMore: true)),
                .failure(authRequiredError())
            ]
        )
        var authRequiredCount = 0
        let viewModel = StarredViewModel(repository: repository, onAuthRequired: {
            authRequiredCount += 1
        })

        await viewModel.loadInitialIfNeeded()
        await viewModel.refresh()

        XCTAssertEqual(authRequiredCount, 1)
        XCTAssertEqual(
            viewModel.state,
            .failed(
                message: "認証の有効期限が切れました。もう一度ログインしてください。",
                isAuthRequired: true
            )
        )
        XCTAssertEqual(viewModel.items.map(\.id), ["existing"])
        XCTAssertNil(viewModel.refreshErrorMessage)
        XCTAssertFalse(viewModel.canLoadMore)
    }

    func testRefreshAuthRequiredDoesNotLeavePreviousEmptyStateVisible() async {
        let repository = RecordingStarredRepository(
            firstPageResults: [
                .failure(authRequiredError())
            ]
        )
        var authRequiredCount = 0
        let viewModel = StarredViewModel(
            repository: repository,
            onAuthRequired: {
                authRequiredCount += 1
            },
            state: .empty
        )

        await viewModel.refresh()

        XCTAssertEqual(authRequiredCount, 1)
        XCTAssertEqual(
            viewModel.state,
            .failed(
                message: "認証の有効期限が切れました。もう一度ログインしてください。",
                isAuthRequired: true
            )
        )
        XCTAssertEqual(viewModel.items, [])
        XCTAssertFalse(viewModel.canLoadMore)
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
        XCTAssertEqual(viewModel.state, .loaded)
        XCTAssertTrue(viewModel.canLoadMore)
        XCTAssertEqual(viewModel.nextPageErrorMessage, "続きを読み込めませんでした。")

        await viewModel.retryNextPage()

        XCTAssertEqual(viewModel.items.map(\.id), ["first", "second"])
        XCTAssertNil(viewModel.nextPageErrorMessage)
        let calls = await repository.calls()
        XCTAssertEqual(calls, [.firstPage(limit: nil), .nextPage, .nextPage])
    }

    func testNextPageAuthRequiredCallsBoundaryAndShowsAuthFailure() async {
        let repository = RecordingStarredRepository(
            firstPageResults: [
                .success(snapshot(items: [item(id: "first")], canLoadMore: true))
            ],
            nextPageResults: [
                .failure(authRequiredError())
            ]
        )
        var authRequiredCount = 0
        let viewModel = StarredViewModel(repository: repository, onAuthRequired: {
            authRequiredCount += 1
        })

        await viewModel.loadInitialIfNeeded()
        await viewModel.loadNextPageIfNeeded(currentItemID: "first")

        XCTAssertEqual(authRequiredCount, 1)
        XCTAssertEqual(
            viewModel.state,
            .failed(
                message: "認証の有効期限が切れました。もう一度ログインしてください。",
                isAuthRequired: true
            )
        )
        XCTAssertEqual(viewModel.items.map(\.id), ["first"])
        XCTAssertNil(viewModel.nextPageErrorMessage)
        XCTAssertFalse(viewModel.canLoadMore)
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
                .success(snapshot(items: [item(id: "before"), item(id: "target"), item(id: "after")], canLoadMore: false))
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

        XCTAssertEqual(viewModel.items.map(\.id), ["before", "target", "after"])
        XCTAssertEqual(viewModel.state, .loaded)
        XCTAssertEqual(viewModel.starMutationErrorMessage, "スターを更新できませんでした。")
        let target = viewModel.items[1]
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

    private func authRequiredError() -> FeedmanAPIError {
        FeedmanAPIError.authRequired(
            AuthRequiredContext(
                reason: .missingRefreshHook,
                statusCode: 401,
                underlyingError: nil
            )
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

private actor SuspendedStarredRepository: FeedRepository {
    private var recordedCalls: [StarredRepositoryCall] = []
    private let firstPageResult: StarredItemPaginationSnapshot
    private var firstPageContinuations: [CheckedContinuation<StarredItemPaginationSnapshot, Error>] = []
    private var callCountWaiters: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []

    init(firstPageResult: StarredItemPaginationSnapshot) {
        self.firstPageResult = firstPageResult
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
        record(.firstPage(limit: limit))
        return try await withCheckedThrowingContinuation { continuation in
            firstPageContinuations.append(continuation)
        }
    }

    func loadStarredItemsNextPage() async throws -> StarredItemPaginationSnapshot {
        record(.nextPage)
        throw StarredItemRepositoryError.paginationUnsupported
    }

    private func record(_ call: StarredRepositoryCall) {
        recordedCalls.append(call)
        let currentCallCount = recordedCalls.count
        let readyWaiters = callCountWaiters.filter { currentCallCount >= $0.count }
        callCountWaiters.removeAll { currentCallCount >= $0.count }
        readyWaiters.forEach { $0.continuation.resume() }
    }
}
