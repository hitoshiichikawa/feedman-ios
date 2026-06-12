import XCTest
@testable import Feedman

@MainActor
final class AppShellDrawerFeedStateTests: XCTestCase {
    func testMockFeedRepositoryReturnsDrawerFeedDisplayValues() async throws {
        let feeds = try await MockFeedRepository().subscriptions()

        XCTAssertTrue(feeds.contains(Feed(id: "publickey", subscriptionID: "sub-publickey", title: "Publickey", unreadCount: 12, status: .active, fetchIntervalMinutes: 60)))
        XCTAssertTrue(feeds.contains(Feed(id: "qiita", subscriptionID: "sub-qiita", title: "Qiita 人気の記事", unreadCount: 14, status: .stopped(message: "手動で停止しました"), fetchIntervalMinutes: 180)))
        XCTAssertTrue(feeds.contains(Feed(id: "swift-blog", subscriptionID: "sub-swift-blog", title: "Swift Blog", unreadCount: 0, status: .error(message: "前回の取得に失敗しました"), fetchIntervalMinutes: 60)))
    }

    func testLoadSubscriptionsSuccessStoresRepositoryFeeds() async {
        let expectedFeeds = [
            Feed(id: "feed-a", title: "Feed A", unreadCount: 3, status: .active),
            Feed(id: "feed-b", title: "Feed B", unreadCount: 0, status: .stopped(message: "paused"))
        ]
        let viewModel = AppShellDrawerFeedViewModel()

        await viewModel.loadSubscriptions(repository: StubFeedRepository(subscriptionsResult: .success(expectedFeeds)))

        XCTAssertEqual(viewModel.sectionState, .loaded(feeds: expectedFeeds))
        XCTAssertEqual(viewModel.sectionState.feeds.map(\.title), ["Feed A", "Feed B"])
        XCTAssertEqual(viewModel.sectionState.feeds.map(\.unreadCount), [3, 0])
        XCTAssertEqual(viewModel.sectionState.feeds.map(\.status), [.active, .stopped(message: "paused")])
    }

    func testLoadSubscriptionsEmptyPreservesCurrentRouteOutsideFeedSection() async {
        var shellState = AppShellState(currentRoute: .starred, isDrawerOpen: true)
        let viewModel = AppShellDrawerFeedViewModel()

        await viewModel.loadSubscriptions(repository: StubFeedRepository(subscriptionsResult: .success([])))

        XCTAssertEqual(viewModel.sectionState, .empty)
        XCTAssertEqual(shellState.currentRoute, .starred)
        XCTAssertTrue(shellState.isDrawerOpen)

        shellState.selectRoute(.timeline)
        XCTAssertEqual(shellState.currentRoute, .timeline)
        XCTAssertFalse(shellState.isDrawerOpen)
    }

    func testLoadSubscriptionsFailureSurfacesErrorAndKeepsGlobalRoutesUsable() async {
        var shellState = AppShellState(currentRoute: .timeline, isDrawerOpen: true)
        let viewModel = AppShellDrawerFeedViewModel()

        await viewModel.loadSubscriptions(repository: StubFeedRepository(subscriptionsResult: .failure(StubError.failed)))

        XCTAssertEqual(viewModel.sectionState, .failed(message: "フィードを読み込めませんでした", feeds: []))

        shellState.selectRoute(.account)
        XCTAssertEqual(shellState.currentRoute, .account)
        XCTAssertFalse(shellState.isDrawerOpen)
    }

    func testLoadSubscriptionsFailureKeepsAlreadyLoadedFeeds() async {
        let existingFeeds = [
            Feed(id: "feed-a", title: "Feed A", unreadCount: 3, status: .active)
        ]
        let viewModel = AppShellDrawerFeedViewModel(sectionState: .loaded(feeds: existingFeeds))

        await viewModel.loadSubscriptions(repository: StubFeedRepository(subscriptionsResult: .failure(StubError.failed)))

        XCTAssertEqual(viewModel.sectionState, .failed(message: "フィードを読み込めませんでした", feeds: existingFeeds))
    }

    func testRetrySubscriptionsCallsRepositoryAgainAndUpdatesUnreadCounts() async {
        let repository = ScriptedFeedRepository(
            results: [
                .failure(StubError.failed),
                .success([
                    Feed(id: "feed-a", title: "Feed A", unreadCount: 7, status: .active),
                    Feed(id: "feed-b", title: "Feed B", unreadCount: 0, status: .error(message: "failed"))
                ]),
                .success([
                    Feed(id: "feed-a", title: "Feed A", unreadCount: 2, status: .active),
                    Feed(id: "feed-b", title: "Feed B", unreadCount: 4, status: .error(message: "failed"))
                ])
            ]
        )
        let viewModel = AppShellDrawerFeedViewModel()

        await viewModel.loadSubscriptions(repository: repository)
        XCTAssertEqual(viewModel.sectionState, .failed(message: "フィードを読み込めませんでした", feeds: []))

        await viewModel.loadSubscriptions(repository: repository)
        XCTAssertEqual(viewModel.sectionState.feeds.map(\.unreadCount), [7, 0])

        await viewModel.loadSubscriptions(repository: repository)
        XCTAssertEqual(viewModel.sectionState.feeds.map(\.unreadCount), [2, 4])
        let loadCallCount = await repository.callCount
        XCTAssertEqual(loadCallCount, 3)
    }

    func testRouteForFeedUsesStableIdentifierAndTitle() {
        let viewModel = AppShellDrawerFeedViewModel()
        let feed = Feed(id: "stable-id", title: "Display Title", unreadCount: 1, status: .error(message: "failed"))

        XCTAssertEqual(viewModel.route(for: feed), .feed(id: "stable-id", title: "Display Title"))
    }

    func testApplySubscriptionSettingsUpdatesMatchingSubscriptionIDOnly() {
        let viewModel = AppShellDrawerFeedViewModel(sectionState: .loaded(feeds: [
            Feed(id: "feed-a", subscriptionID: "sub-a", title: "Feed A", unreadCount: 1, status: .active, fetchIntervalMinutes: 60),
            Feed(id: "feed-b", subscriptionID: "sub-b", title: "Feed B", unreadCount: 2, status: .active, fetchIntervalMinutes: 30)
        ]))

        viewModel.applySubscriptionSettings(subscriptionID: "sub-b", fetchIntervalMinutes: 180)

        XCTAssertEqual(viewModel.sectionState.feeds.map(\.fetchIntervalMinutes), [60, 180])
    }

    func testApplySubscriptionResumeUpdatesMatchingSubscriptionIDOnly() {
        let viewModel = AppShellDrawerFeedViewModel(sectionState: .loaded(feeds: [
            Feed(id: "feed-a", subscriptionID: "sub-a", title: "Feed A", unreadCount: 1, status: .error(message: "failed"), fetchIntervalMinutes: 60),
            Feed(id: "feed-b", subscriptionID: "sub-b", title: "Feed B", unreadCount: 2, status: .stopped(message: "paused"), fetchIntervalMinutes: 30)
        ]))

        viewModel.applySubscriptionResume(subscriptionID: "sub-a")

        XCTAssertEqual(viewModel.sectionState.feeds.map(\.status), [.active, .stopped(message: "paused")])
    }

    func testRemoveSubscriptionRemovesBySubscriptionIDAndSelectedRouteFallsBackToTimeline() {
        var shellState = AppShellState(currentRoute: .feed(id: "feed-b", title: "Feed B"))
        let viewModel = AppShellDrawerFeedViewModel(sectionState: .loaded(feeds: [
            Feed(id: "feed-a", subscriptionID: "sub-a", title: "Same Title", unreadCount: 1, status: .active, fetchIntervalMinutes: 60),
            Feed(id: "feed-b", subscriptionID: "sub-b", title: "Same Title", unreadCount: 2, status: .active, fetchIntervalMinutes: 30)
        ]))

        let removedFeed = viewModel.removeSubscription(subscriptionID: "sub-b")
        shellState.selectTimelineIfCurrentFeedWasRemoved(feedID: removedFeed?.id ?? "")

        XCTAssertEqual(removedFeed?.id, "feed-b")
        XCTAssertEqual(viewModel.sectionState.feeds.map(\.id), ["feed-a"])
        XCTAssertEqual(shellState.currentRoute, .timeline)
    }

    func testRemoveSubscriptionKeepsUnrelatedSelectedFeedRoute() {
        var shellState = AppShellState(currentRoute: .feed(id: "feed-a", title: "Feed A"))
        let viewModel = AppShellDrawerFeedViewModel(sectionState: .loaded(feeds: [
            Feed(id: "feed-a", subscriptionID: "sub-a", title: "Feed A", unreadCount: 1, status: .active, fetchIntervalMinutes: 60),
            Feed(id: "feed-b", subscriptionID: "sub-b", title: "Feed B", unreadCount: 2, status: .active, fetchIntervalMinutes: 30)
        ]))

        let removedFeed = viewModel.removeSubscription(subscriptionID: "sub-b")
        shellState.selectTimelineIfCurrentFeedWasRemoved(feedID: removedFeed?.id ?? "")

        XCTAssertEqual(shellState.currentRoute, .feed(id: "feed-a", title: "Feed A"))
    }

    func testProductionEnvironmentUsesRealFeedRepository() {
        let environment = AppEnvironment.production(apiBaseURL: URL(string: "https://api.example.com")!)

        XCTAssertTrue(environment.feedRepository is APIClientFeedRepository)
    }

    func testApplyRegisteredFeedAddsFeedForDrawerRefreshBoundary() {
        let viewModel = AppShellDrawerFeedViewModel(sectionState: .loaded(feeds: [
            Feed(id: "feed-a", title: "Feed A", unreadCount: 1, status: .active)
        ]))

        viewModel.applyRegisteredFeed(
            RegisteredFeed(
                subscriptionID: "sub-b",
                feedID: "feed-b",
                title: "Feed B",
                feedURL: "https://example.com/feed.xml",
                siteURL: "https://example.com",
                faviconURL: nil,
                fetchIntervalMinutes: 60,
                status: .active,
                unreadCount: 0
            )
        )

        XCTAssertEqual(viewModel.sectionState, .loaded(feeds: [
            Feed(id: "feed-a", title: "Feed A", unreadCount: 1, status: .active),
            Feed(id: "feed-b", subscriptionID: "sub-b", title: "Feed B", unreadCount: 0, status: .active, fetchIntervalMinutes: 60)
        ]))
    }

    func testApplyRegisteredFeedReplacesExistingFeedByStableFeedID() {
        let viewModel = AppShellDrawerFeedViewModel(sectionState: .loaded(feeds: [
            Feed(id: "feed-a", title: "Old Title", unreadCount: 4, status: .error(message: "failed"))
        ]))

        viewModel.applyRegisteredFeed(
            RegisteredFeed(
                subscriptionID: "sub-a",
                feedID: "feed-a",
                title: "New Title",
                feedURL: "https://example.com/feed.xml",
                siteURL: "https://example.com",
                faviconURL: nil,
                fetchIntervalMinutes: 60,
                status: .active,
                unreadCount: 0
            )
        )

        XCTAssertEqual(viewModel.sectionState, .loaded(feeds: [
            Feed(id: "feed-a", subscriptionID: "sub-a", title: "New Title", unreadCount: 0, status: .active, fetchIntervalMinutes: 60)
        ]))
    }
}

private enum StubError: Error {
    case failed
}

private struct StubFeedRepository: FeedRepository {
    let subscriptionsResult: Result<[Feed], Error>

    func subscriptions() async throws -> [Feed] {
        try subscriptionsResult.get()
    }

    func registerFeed(url: String) async throws -> RegisteredFeed {
        RegisteredFeed(
            subscriptionID: "sub-stub",
            feedID: "feed-stub",
            title: "Stub Feed",
            feedURL: url,
            siteURL: nil,
            faviconURL: nil,
            fetchIntervalMinutes: 60,
            status: .active,
            unreadCount: 0
        )
    }

    func crossFeedItems() async throws -> [FeedItem] {
        []
    }
}

private actor ScriptedFeedRepository: FeedRepository {
    private var results: [Result<[Feed], Error>]
    private(set) var callCount = 0

    init(results: [Result<[Feed], Error>]) {
        self.results = results
    }

    func subscriptions() async throws -> [Feed] {
        callCount += 1
        guard !results.isEmpty else {
            return []
        }
        return try results.removeFirst().get()
    }

    func crossFeedItems() async throws -> [FeedItem] {
        []
    }
}
