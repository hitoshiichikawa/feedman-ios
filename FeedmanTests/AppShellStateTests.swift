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
}
