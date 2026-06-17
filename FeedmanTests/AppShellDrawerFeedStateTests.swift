import SwiftUI
import UIKit
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

    func testRefreshAfterFeedRegistrationReloadsSubscriptionsAndUsesRepositoryResult() async {
        let repositoryFeeds = [
            Feed(id: "feed-a", title: "Feed A", unreadCount: 1, status: .active),
            Feed(id: "feed-registered", subscriptionID: "sub-registered", title: "Registered Feed", unreadCount: 5, status: .active, fetchIntervalMinutes: 60),
            Feed(id: "feed-c", title: "Feed C", unreadCount: 0, status: .stopped(message: "paused"))
        ]
        let repository = ScriptedFeedRepository(results: [.success(repositoryFeeds)])
        let viewModel = AppShellDrawerFeedViewModel(sectionState: .loaded(feeds: [
            Feed(id: "feed-a", title: "Feed A", unreadCount: 1, status: .active)
        ]))

        await viewModel.refreshSubscriptionsAfterFeedRegistration(Self.registeredFeed, repository: repository)

        XCTAssertEqual(viewModel.sectionState, .loaded(feeds: repositoryFeeds))
        XCTAssertEqual(viewModel.route(for: repositoryFeeds[1]), .feed(id: "feed-registered", title: "Registered Feed"))
        let loadCallCount = await repository.callCount
        XCTAssertEqual(loadCallCount, 1)
    }

    func testRefreshAfterFeedRegistrationFailureKeepsRegisteredFeedWithGuidance() async {
        let existingFeeds = [
            Feed(id: "feed-a", title: "Feed A", unreadCount: 1, status: .active)
        ]
        let repository = ScriptedFeedRepository(results: [.failure(StubError.failed)])
        let viewModel = AppShellDrawerFeedViewModel(sectionState: .loaded(feeds: existingFeeds))

        await viewModel.refreshSubscriptionsAfterFeedRegistration(Self.registeredFeed, repository: repository)

        XCTAssertEqual(
            viewModel.sectionState,
            .failed(
                message: "フィードは登録されましたが、一覧を更新できませんでした",
                feeds: existingFeeds + [Self.registeredFeed.drawerFeed]
            )
        )
    }

    func testRetryAfterPostRegistrationRefreshFailureReloadsSubscriptionsAgain() async {
        let repositoryFeeds = [
            Feed(id: "feed-registered", subscriptionID: "sub-registered", title: "Registered Feed", unreadCount: 2, status: .active, fetchIntervalMinutes: 60)
        ]
        let repository = ScriptedFeedRepository(results: [
            .failure(StubError.failed),
            .success(repositoryFeeds)
        ])
        let viewModel = AppShellDrawerFeedViewModel()

        await viewModel.refreshSubscriptionsAfterFeedRegistration(Self.registeredFeed, repository: repository)
        XCTAssertEqual(
            viewModel.sectionState,
            .failed(
                message: "フィードは登録されましたが、一覧を更新できませんでした",
                feeds: [Self.registeredFeed.drawerFeed]
            )
        )

        await viewModel.loadSubscriptions(repository: repository)

        XCTAssertEqual(viewModel.sectionState, .loaded(feeds: repositoryFeeds))
        let loadCallCount = await repository.callCount
        XCTAssertEqual(loadCallCount, 2)
    }

    func testLatestSubscriptionReloadWinsWhenRegistrationRefreshesOverlap() async throws {
        let repository = ControlledSubscriptionsRepository()
        let viewModel = AppShellDrawerFeedViewModel()
        let firstRegisteredFeed = RegisteredFeed(
            subscriptionID: "sub-first",
            feedID: "feed-first",
            title: "First Feed",
            feedURL: "https://example.com/first.xml",
            siteURL: nil,
            faviconURL: nil,
            fetchIntervalMinutes: 60,
            status: .active,
            unreadCount: 0
        )
        let secondRegisteredFeed = RegisteredFeed(
            subscriptionID: "sub-second",
            feedID: "feed-second",
            title: "Second Feed",
            feedURL: "https://example.com/second.xml",
            siteURL: nil,
            faviconURL: nil,
            fetchIntervalMinutes: 60,
            status: .active,
            unreadCount: 0
        )
        let latestFeeds = [
            Feed(id: "feed-second", subscriptionID: "sub-second", title: "Second Feed", unreadCount: 8, status: .active, fetchIntervalMinutes: 60)
        ]

        let firstTask = Task {
            await viewModel.refreshSubscriptionsAfterFeedRegistration(firstRegisteredFeed, repository: repository)
        }
        try await waitUntil { repository.pendingCallCount == 1 }

        let secondTask = Task {
            await viewModel.refreshSubscriptionsAfterFeedRegistration(secondRegisteredFeed, repository: repository)
        }
        try await waitUntil { repository.pendingCallCount == 2 }

        repository.completeCall(at: 1, with: .success(latestFeeds))
        await secondTask.value
        XCTAssertEqual(viewModel.sectionState, .loaded(feeds: latestFeeds))

        repository.completeCall(
            at: 0,
            with: .success([
                Feed(id: "feed-first", subscriptionID: "sub-first", title: "First Feed", unreadCount: 1, status: .active, fetchIntervalMinutes: 60)
            ])
        )
        await firstTask.value

        XCTAssertEqual(viewModel.sectionState, .loaded(feeds: latestFeeds))
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

    func testAuthenticatedTimelineStartupDoesNotUseLegacyCrossFeedItems() async {
        let subscriptionsLoaded = expectation(description: "AppShell loads drawer subscriptions")
        let firstPageLoaded = expectation(description: "Timeline loads first cross-feed page")
        let legacyCrossFeedItemsLoaded = expectation(description: "AppShell must not load legacy cross-feed items")
        legacyCrossFeedItemsLoaded.isInverted = true

        let repository = RecordingAppShellTimelineStartupRepository(
            subscriptionsLoaded: subscriptionsLoaded,
            firstPageLoaded: firstPageLoaded,
            legacyCrossFeedItemsLoaded: legacyCrossFeedItemsLoaded
        )
        let environment = AppEnvironment(
            feedRepository: repository,
            authRepository: UnavailableAuthRepository(),
            accountRepository: UnavailableAccountRepository(),
            authBaseURL: URL(string: "https://example.com")!,
            authenticationState: .authenticated(accessToken: "test-access-token")
        )
        let window = UIWindow(frame: UIScreen.main.bounds)

        window.rootViewController = UIHostingController(
            rootView: RootView()
                .environmentObject(environment)
        )
        window.makeKeyAndVisible()

        await fulfillment(of: [subscriptionsLoaded, firstPageLoaded], timeout: 3)
        await fulfillment(of: [legacyCrossFeedItemsLoaded], timeout: 0.3)

        let subscriptionsCallCount = await repository.subscriptionsCallCount()
        let crossFeedItemsCallCount = await repository.crossFeedItemsCallCount()
        let firstPageLimitCalls = await repository.firstPageLimitCalls()

        XCTAssertEqual(subscriptionsCallCount, 1)
        XCTAssertEqual(crossFeedItemsCallCount, 0)
        XCTAssertEqual(firstPageLimitCalls, [Optional<Int>.none])

        window.isHidden = true
        window.rootViewController = nil
    }

    private static let registeredFeed = RegisteredFeed(
        subscriptionID: "sub-registered",
        feedID: "feed-registered",
        title: "Registered Feed",
        feedURL: "https://example.com/feed.xml",
        siteURL: "https://example.com",
        faviconURL: nil,
        fetchIntervalMinutes: 60,
        status: .active,
        unreadCount: 0
    )

    private func waitUntil(
        timeoutNanoseconds: UInt64 = 1_000_000_000,
        condition: @escaping () -> Bool
    ) async throws {
        let start = DispatchTime.now().uptimeNanoseconds

        while DispatchTime.now().uptimeNanoseconds - start < timeoutNanoseconds {
            if condition() {
                return
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        XCTFail("Timed out waiting for condition")
        throw WaitError.timedOut
    }
}

private enum WaitError: Error {
    case timedOut
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

private actor RecordingAppShellTimelineStartupRepository: FeedRepository {
    private let subscriptionsLoaded: XCTestExpectation
    private let firstPageLoaded: XCTestExpectation
    private let legacyCrossFeedItemsLoaded: XCTestExpectation
    private var subscriptionsCalls = 0
    private var crossFeedItemsCalls = 0
    private var firstPageLimits: [Int?] = []

    init(
        subscriptionsLoaded: XCTestExpectation,
        firstPageLoaded: XCTestExpectation,
        legacyCrossFeedItemsLoaded: XCTestExpectation
    ) {
        self.subscriptionsLoaded = subscriptionsLoaded
        self.firstPageLoaded = firstPageLoaded
        self.legacyCrossFeedItemsLoaded = legacyCrossFeedItemsLoaded
    }

    func subscriptionsCallCount() -> Int {
        subscriptionsCalls
    }

    func crossFeedItemsCallCount() -> Int {
        crossFeedItemsCalls
    }

    func firstPageLimitCalls() -> [Int?] {
        firstPageLimits
    }

    func subscriptions() async throws -> [Feed] {
        subscriptionsCalls += 1
        if subscriptionsCalls == 1 {
            subscriptionsLoaded.fulfill()
        }

        return [
            Feed(id: "feed-a", title: "Feed A", unreadCount: 1, status: .active)
        ]
    }

    func crossFeedItems() async throws -> [FeedItem] {
        crossFeedItemsCalls += 1

        legacyCrossFeedItemsLoaded.fulfill()
        return []
    }

    func loadCrossFeedFirstPage(limit: Int?) async throws -> CrossFeedPaginationSnapshot {
        firstPageLimits.append(limit)
        if firstPageLimits.count == 1 {
            firstPageLoaded.fulfill()
        }

        return CrossFeedPaginationSnapshot(
            items: [],
            nextCursor: nil,
            canLoadMore: false,
            sinceTime: nil,
            limit: CrossFeedPageLimit.defaultValue
        )
    }
}

private final class ControlledSubscriptionsRepository: FeedRepository {
    private let lock = NSLock()
    private var nextCallIndex = 0
    private var continuations: [Int: CheckedContinuation<[Feed], Error>] = [:]

    var pendingCallCount: Int {
        withLock {
            continuations.count
        }
    }

    func subscriptions() async throws -> [Feed] {
        let callIndex: Int = withLock {
            let index = nextCallIndex
            nextCallIndex += 1
            return index
        }

        return try await withCheckedThrowingContinuation { continuation in
            withLock {
                continuations[callIndex] = continuation
            }
        }
    }

    func completeCall(at index: Int, with result: Result<[Feed], Error>) {
        let continuation = withLock {
            continuations.removeValue(forKey: index)
        }

        continuation?.resume(with: result)
    }

    func crossFeedItems() async throws -> [FeedItem] {
        []
    }

    private func withLock<T>(_ body: () -> T) -> T {
        lock.lock()
        defer {
            lock.unlock()
        }
        return body()
    }
}
