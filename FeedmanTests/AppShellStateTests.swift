import XCTest
@testable import Feedman

final class AppShellStateTests: XCTestCase {
    func testDefaultRouteIsTimelineAndDrawerIsClosed() {
        let state = AppShellState()

        XCTAssertEqual(state.currentRoute, .timeline)
        XCTAssertEqual(state.title, "すべての新着")
        XCTAssertEqual(state.drawerSelection, .timeline)
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
}
