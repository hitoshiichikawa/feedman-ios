import XCTest
@testable import Feedman

final class CursorPaginationStateTests: XCTestCase {
    func testInitialStateStartsEmptyWithoutCursorAndAllowsLoading() {
        let state = CursorPaginationState<String>()

        XCTAssertTrue(state.items.isEmpty)
        XCTAssertNil(state.nextCursor)
        XCTAssertTrue(state.canLoadMore)
    }

    func testFirstPageWithNextCursorAccumulatesItemsAndPublishesCursor() {
        var state = CursorPaginationState<String>()

        state.applyFirstPage(TestPage(items: ["first", "second"], nextCursor: "cursor-2", hasMore: true))

        XCTAssertEqual(state.items, ["first", "second"])
        XCTAssertEqual(state.nextCursor, "cursor-2")
        XCTAssertTrue(state.canLoadMore)
    }

    func testAdditionalPageAppendsItemsAfterExistingItems() {
        var state = CursorPaginationState<String>()
        state.applyFirstPage(TestPage(items: ["first"], nextCursor: "cursor-2", hasMore: true))

        state.appendPage(TestPage(items: ["second", "third"], nextCursor: "cursor-3", hasMore: true))

        XCTAssertEqual(state.items, ["first", "second", "third"])
        XCTAssertEqual(state.nextCursor, "cursor-3")
        XCTAssertTrue(state.canLoadMore)
    }

    func testHasMoreFalseMarksTerminalAndClearsCursor() {
        var state = CursorPaginationState<String>()

        state.applyFirstPage(TestPage(items: ["first"], nextCursor: "cursor-ignored", hasMore: false))

        XCTAssertEqual(state.items, ["first"])
        XCTAssertNil(state.nextCursor)
        XCTAssertFalse(state.canLoadMore)
    }

    func testNilNextCursorMarksTerminalAndClearsCursor() {
        var state = CursorPaginationState<String>()

        state.applyFirstPage(TestPage(items: ["first"], nextCursor: nil, hasMore: true))

        XCTAssertEqual(state.items, ["first"])
        XCTAssertNil(state.nextCursor)
        XCTAssertFalse(state.canLoadMore)
    }

    func testEmptyNextCursorMarksTerminalAndClearsCursor() {
        var state = CursorPaginationState<String>()

        state.applyFirstPage(TestPage(items: ["first"], nextCursor: "", hasMore: true))

        XCTAssertEqual(state.items, ["first"])
        XCTAssertNil(state.nextCursor)
        XCTAssertFalse(state.canLoadMore)
    }

    func testRefreshResetClearsItemsAndCursorAndRestoresCanLoadMore() {
        var state = CursorPaginationState<String>()
        state.applyFirstPage(TestPage(items: ["old"], nextCursor: nil, hasMore: false))

        state.resetForRefresh()

        XCTAssertTrue(state.items.isEmpty)
        XCTAssertNil(state.nextCursor)
        XCTAssertTrue(state.canLoadMore)
    }

    func testRefreshedFirstPageDoesNotKeepItemsBeforeReset() {
        var state = CursorPaginationState<String>()
        state.applyFirstPage(TestPage(items: ["old"], nextCursor: "cursor-2", hasMore: true))

        state.resetForRefresh()
        state.applyFirstPage(TestPage(items: ["new"], nextCursor: nil, hasMore: false))

        XCTAssertEqual(state.items, ["new"])
        XCTAssertNil(state.nextCursor)
        XCTAssertFalse(state.canLoadMore)
    }

    func testCursorPaginatedResponseCanUpdateGenericState() {
        var state = CursorPaginationState<String>()
        let response = CursorPaginatedResponse(items: ["first"], nextCursor: "cursor-2", hasMore: true)

        state.applyFirstPage(response)

        XCTAssertEqual(state.items, ["first"])
        XCTAssertEqual(state.nextCursor, "cursor-2")
        XCTAssertTrue(state.canLoadMore)
    }
}

private struct TestPage<Item>: CursorPaginatedPage {
    let items: [Item]
    let nextCursor: String?
    let hasMore: Bool
}
