import XCTest
@testable import Feedman

final class AppShellStateTests: XCTestCase {
    func testDefaultRouteIsTimelineAndDrawerIsClosed() {
        let state = AppShellState()

        XCTAssertEqual(state.currentRoute, .timeline)
        XCTAssertEqual(state.title, "すべての新着")
        XCTAssertEqual(state.drawerSelection, .timeline)
        XCTAssertNil(state.activePresentation)
        XCTAssertEqual(state.themeOverride, .system)
        XCTAssertFalse(state.isDrawerOpen)
    }

    func testDismissDrawerKeepsCurrentRoute() {
        var state = AppShellState(currentRoute: .starred)

        state.openDrawer()
        state.dismissDrawer()

        XCTAssertEqual(state.currentRoute, .starred)
        XCTAssertEqual(state.title, "お気に入り")
        XCTAssertEqual(state.drawerSelection, .starred)
        XCTAssertFalse(state.isDrawerOpen)
    }

    func testSelectingDrawerRouteClosesDrawerAndUpdatesRoute() {
        var state = AppShellState()

        state.openDrawer()
        state.selectRoute(.starred)

        XCTAssertEqual(state.currentRoute, .starred)
        XCTAssertEqual(state.title, "お気に入り")
        XCTAssertEqual(state.drawerSelection, .starred)
        XCTAssertFalse(state.isDrawerOpen)
    }

    func testSelectingFeedRouteCarriesStableIdentifierSeparatelyFromTitle() {
        var state = AppShellState()

        state.openDrawer()
        state.selectRoute(.feed(id: "publickey", title: "Publickey"))

        XCTAssertEqual(state.currentRoute, .feed(id: "publickey", title: "Publickey"))
        XCTAssertEqual(state.title, "Publickey")
        XCTAssertEqual(state.drawerSelection, .feed(id: "publickey"))
        XCTAssertFalse(state.isDrawerOpen)
    }

    func testFeedRouteWithEmptyTitleUsesSafeFallbackTitle() {
        let state = AppShellState(currentRoute: .feed(id: "missing-feed", title: ""))

        XCTAssertEqual(state.title, "フィード")
        XCTAssertEqual(state.drawerSelection, .feed(id: "missing-feed"))
    }

    func testSelectingCurrentRouteStillClosesDrawerWithoutChangingRoute() {
        var state = AppShellState(currentRoute: .account, isDrawerOpen: true)

        state.selectRoute(.account)

        XCTAssertEqual(state.currentRoute, .account)
        XCTAssertEqual(state.title, "アカウント")
        XCTAssertEqual(state.drawerSelection, .account)
        XCTAssertFalse(state.isDrawerOpen)
    }

    func testActivatingSearchUsesExplicitRouteAndClosesDrawer() {
        var state = AppShellState(currentRoute: .starred, isDrawerOpen: true)

        state.activateSearch()

        XCTAssertEqual(state.currentRoute, .search)
        XCTAssertEqual(state.title, "検索")
        XCTAssertEqual(state.drawerSelection, .search)
        XCTAssertNil(state.activePresentation)
        XCTAssertFalse(state.isDrawerOpen)
    }

    func testActivatingSearchFromSearchKeepsSingleRouteAndClearsPresentation() {
        var state = AppShellState(currentRoute: .search, activePresentation: .account)

        state.activateSearch()

        XCTAssertEqual(state.currentRoute, .search)
        XCTAssertNil(state.activePresentation)
        XCTAssertFalse(state.isDrawerOpen)
    }

    func testPresentingAccountClosesDrawerAndUsesSinglePresentationState() {
        var state = AppShellState(isDrawerOpen: true)

        state.presentAccount()

        XCTAssertEqual(state.currentRoute, .timeline)
        XCTAssertEqual(state.activePresentation, .account)
        XCTAssertFalse(state.isDrawerOpen)
    }

    func testPresentingFeedRegistrationClosesDrawerAndReplacesPresentationState() {
        var state = AppShellState(isDrawerOpen: true, activePresentation: .account)

        state.presentFeedRegistration()

        XCTAssertEqual(state.currentRoute, .timeline)
        XCTAssertEqual(state.activePresentation, .feedRegistration)
        XCTAssertFalse(state.isDrawerOpen)
    }

    func testPresentingArticleDetailStoresSelectedInputAndClosesDrawer() {
        var state = AppShellState(currentRoute: .search, isDrawerOpen: true)
        let input = ArticleDetailSheetInput(
            id: "item-47",
            summary: ArticleDetailSummary(id: "item-47", title: "Search Result")
        )

        let didPresent = state.presentArticleDetail(input)

        XCTAssertTrue(didPresent)
        XCTAssertEqual(state.currentRoute, .search)
        XCTAssertEqual(state.activePresentation, .articleDetail(input))
        XCTAssertFalse(state.isDrawerOpen)
    }

    func testInvalidArticleDetailInputDoesNotPresentBrokenSheet() {
        var state = AppShellState(currentRoute: .search)

        let didPresent = state.presentArticleDetail(ArticleDetailSheetInput(id: "   "))

        XCTAssertFalse(didPresent)
        XCTAssertNil(state.activePresentation)
    }

    func testPresentingSubscriptionSettingsClosesDrawerAndCarriesFeed() {
        var state = AppShellState(isDrawerOpen: true)
        let feed = Feed(
            id: "feed-a",
            subscriptionID: "sub-a",
            title: "Feed A",
            unreadCount: 1,
            status: .active,
            fetchIntervalMinutes: 60
        )

        state.presentSubscriptionSettings(feed: feed)

        XCTAssertEqual(state.activePresentation, .subscriptionSettings(feed))
        XCTAssertFalse(state.isDrawerOpen)
    }

    func testSelectedFeedRouteFallsBackToTimelineWhenRemoved() {
        var state = AppShellState(currentRoute: .feed(id: "feed-a", title: "Feed A"))

        state.selectTimelineIfCurrentFeedWasRemoved(feedID: "feed-a")

        XCTAssertEqual(state.currentRoute, .timeline)
    }

    func testDismissPresentationClearsActivePresentationOnly() {
        var state = AppShellState(currentRoute: .starred, activePresentation: .feedRegistration)

        state.dismissPresentation()

        XCTAssertEqual(state.currentRoute, .starred)
        XCTAssertNil(state.activePresentation)
    }

    func testSelectingRouteClearsPendingArticleDetailPresentation() {
        let input = ArticleDetailSheetInput(id: "item-47")
        var state = AppShellState(currentRoute: .search, activePresentation: .articleDetail(input))

        state.selectRoute(.timeline)

        XCTAssertEqual(state.currentRoute, .timeline)
        XCTAssertNil(state.activePresentation)
    }

    func testApplyingItemStateChangeKeepsLatestConfirmedChange() {
        var state = AppShellState(currentRoute: .search)
        let change = ItemStateChange(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000047")!,
            itemID: "item-47",
            isRead: true,
            isStarred: false
        )

        state.applyItemStateChange(change)

        XCTAssertEqual(state.itemStateChange, change)
    }

    @MainActor
    func testSearchResultOpenLinkCoordinatorOpensURLMarksReadAndDoesNotSelectDetail() async throws {
        let repository = AppShellSearchResultRecordingItemRepository(updateResult: .success(()))
        let descriptor = SearchResultRowDescriptor(hit: searchHit(id: "item-47", isRead: false))
        let request = try XCTUnwrap(descriptor.openLinkRequest)
        var openedURLs: [URL] = []
        var itemStateChanges: [ItemStateChange] = []
        var failures: [AppShellSearchResultOpenLinkFailure] = []
        var selectedInputs: [ArticleDetailSheetInput] = []

        let coordinator = AppShellSearchResultOpenLinkCoordinator(
            itemRepository: repository,
            accessToken: " access-token ",
            openURL: { url in
                openedURLs.append(url)
            },
            onItemStateChange: { change in
                itemStateChanges.append(change)
            },
            onFailure: { failure in
                failures.append(failure)
            }
        )

        await performSearchResultOpenLinkAction(
            descriptor: descriptor,
            onSelectItem: { input in
                selectedInputs.append(input)
            },
            onOpenLink: { request in
                await coordinator.open(request)
            }
        )

        XCTAssertTrue(selectedInputs.isEmpty)
        XCTAssertEqual(openedURLs, [try XCTUnwrap(URL(string: "https://example.com/item-47"))])
        let stateUpdateCalls = await repository.stateUpdateCalls()
        XCTAssertEqual(
            stateUpdateCalls,
            [
                AppShellSearchResultStateUpdateCall(
                    itemID: "item-47",
                    request: ItemStateUpdateRequest(isRead: true, isStarred: nil),
                    accessToken: "access-token"
                )
            ]
        )
        XCTAssertEqual(itemStateChanges.count, 1)
        XCTAssertEqual(itemStateChanges.first?.itemID, "item-47")
        XCTAssertEqual(itemStateChanges.first?.isRead, true)
        XCTAssertNil(itemStateChanges.first?.isStarred)
        XCTAssertTrue(failures.isEmpty)
        XCTAssertEqual(request.itemID, "item-47")
    }

    @MainActor
    func testSearchResultOpenLinkCoordinatorDoesNotApplyReadStateWhenReadMarkingFails() async throws {
        let repository = AppShellSearchResultRecordingItemRepository(
            updateResult: .failure(AppShellSearchResultTestError.transport)
        )
        let request = SearchResultOpenLinkRequest(
            itemID: "item-47",
            url: try XCTUnwrap(URL(string: "https://example.com/item-47"))
        )
        let viewModel = GlobalSearchViewModel(
            state: .results(
                query: "Swift",
                hits: [searchHit(id: "item-47", isRead: false)]
            ),
            repository: RecordingAppShellSearchRepository()
        )
        var shellState = AppShellState(currentRoute: .search)
        var openedURLs: [URL] = []
        var failures: [AppShellSearchResultOpenLinkFailure] = []

        await AppShellSearchResultOpenLinkCoordinator(
            itemRepository: repository,
            accessToken: "access-token",
            openURL: { url in
                openedURLs.append(url)
            },
            onItemStateChange: { change in
                shellState.applyItemStateChange(change)
                viewModel.applyItemStateChange(change)
            },
            onFailure: { failure in
                failures.append(failure)
            }
        )
        .open(request)

        XCTAssertEqual(openedURLs, [request.url])
        let stateUpdateCalls = await repository.stateUpdateCalls()
        XCTAssertEqual(
            stateUpdateCalls,
            [
                AppShellSearchResultStateUpdateCall(
                    itemID: "item-47",
                    request: ItemStateUpdateRequest(isRead: true, isStarred: nil),
                    accessToken: "access-token"
                )
            ]
        )
        XCTAssertNil(shellState.itemStateChange)
        XCTAssertEqual(failures, [.readMarkingFailed])
        guard case let .results(_, hits) = viewModel.state else {
            return XCTFail("Expected results state")
        }
        XCTAssertEqual(hits.first?.isRead, false)
    }

    func testThemeOverrideCyclesThroughSystemDarkAndLight() {
        var state = AppShellState()

        state.toggleThemeOverride()
        XCTAssertEqual(state.themeOverride, .dark)

        state.toggleThemeOverride()
        XCTAssertEqual(state.themeOverride, .light)

        state.toggleThemeOverride()
        XCTAssertEqual(state.themeOverride, .system)
    }

    func testThemeOverrideDoesNotChangeRouteOrDrawerState() {
        var state = AppShellState(currentRoute: .feed(id: "zenn", title: "Zenn"), isDrawerOpen: true)

        state.toggleThemeOverride()

        XCTAssertEqual(state.currentRoute, .feed(id: "zenn", title: "Zenn"))
        XCTAssertTrue(state.isDrawerOpen)
        XCTAssertEqual(state.themeOverride, .dark)
    }

    private func searchHit(id: String, isRead: Bool?) -> ItemSearchHit {
        ItemSearchHit(
            id: id,
            feedID: "feed-\(id)",
            feedTitle: "Feed \(id)",
            faviconURL: nil,
            title: "Title \(id)",
            summary: "Summary \(id)",
            link: "https://example.com/\(id)",
            publishedAt: "2026-06-08T08:30:00Z",
            isDateEstimated: false,
            isRead: isRead,
            isStarred: false,
            hatebuCount: nil,
            author: nil
        )
    }

    @MainActor
    private func performSearchResultOpenLinkAction(
        descriptor: SearchResultRowDescriptor,
        onSelectItem: (ArticleDetailSheetInput) -> Void,
        onOpenLink: (SearchResultOpenLinkRequest) async -> Void
    ) async {
        _ = onSelectItem
        var request: SearchResultOpenLinkRequest?
        descriptor.openLink { openLinkRequest in
            request = openLinkRequest
        }

        if let request {
            await onOpenLink(request)
        }
    }
}

private struct AppShellSearchResultStateUpdateCall: Equatable {
    let itemID: String
    let request: ItemStateUpdateRequest
    let accessToken: String
}

private enum AppShellSearchResultTestError: Error {
    case transport
}

private actor AppShellSearchResultRecordingItemRepository: ItemRepository {
    private let updateResult: Result<Void, Error>
    private var recordedStateUpdateCalls: [AppShellSearchResultStateUpdateCall] = []

    init(updateResult: Result<Void, Error>) {
        self.updateResult = updateResult
    }

    func stateUpdateCalls() -> [AppShellSearchResultStateUpdateCall] {
        recordedStateUpdateCalls
    }

    func itemDetail(id: String, accessToken: String) async throws -> ItemDetail {
        throw AppShellSearchResultTestError.transport
    }

    func updateItemState(
        id: String,
        request: ItemStateUpdateRequest,
        accessToken: String
    ) async throws {
        recordedStateUpdateCalls.append(
            AppShellSearchResultStateUpdateCall(
                itemID: id,
                request: request,
                accessToken: accessToken
            )
        )
        try updateResult.get()
    }
}

private actor RecordingAppShellSearchRepository: SearchRepository {
    func searchItems(query: String, scope: SearchScope) async throws -> [ItemSearchHit] {
        []
    }
}
