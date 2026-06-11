import XCTest
@testable import Feedman

@MainActor
final class AppShellDrawerFeedStateTests: XCTestCase {
    func testMockFeedRepositoryReturnsDrawerFeedDisplayValues() async throws {
        let feeds = try await MockFeedRepository().subscriptions()

        XCTAssertTrue(feeds.contains(Feed(id: "publickey", title: "Publickey", unreadCount: 12, status: .active)))
        XCTAssertTrue(feeds.contains(Feed(id: "qiita", title: "Qiita 人気の記事", unreadCount: 14, status: .stopped(message: "手動で停止しました"))))
        XCTAssertTrue(feeds.contains(Feed(id: "swift-blog", title: "Swift Blog", unreadCount: 0, status: .error(message: "前回の取得に失敗しました"))))
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

    func testRouteForFeedUsesStableIdentifierAndTitle() {
        let viewModel = AppShellDrawerFeedViewModel()
        let feed = Feed(id: "stable-id", title: "Display Title", unreadCount: 1, status: .error(message: "failed"))

        XCTAssertEqual(viewModel.route(for: feed), .feed(id: "stable-id", title: "Display Title"))
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

    func crossFeedItems() async throws -> [FeedItem] {
        []
    }
}
