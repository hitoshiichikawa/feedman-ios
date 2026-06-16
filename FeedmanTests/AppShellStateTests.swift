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
