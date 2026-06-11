import Foundation

protocol CursorPaginatedPage {
    associatedtype Item

    var items: [Item] { get }
    var nextCursor: String? { get }
    var hasMore: Bool { get }
}

struct CursorPaginationState<Item> {
    private(set) var items: [Item]
    private(set) var nextCursor: String?
    private(set) var canLoadMore: Bool

    init(
        items: [Item] = [],
        nextCursor: String? = nil,
        canLoadMore: Bool = true
    ) {
        self.items = items
        self.nextCursor = nextCursor
        self.canLoadMore = canLoadMore
    }

    mutating func applyFirstPage<Page: CursorPaginatedPage>(_ page: Page) where Page.Item == Item {
        items = page.items
        updateCursor(nextCursor: page.nextCursor, hasMore: page.hasMore)
    }

    mutating func appendPage<Page: CursorPaginatedPage>(_ page: Page) where Page.Item == Item {
        items.append(contentsOf: page.items)
        updateCursor(nextCursor: page.nextCursor, hasMore: page.hasMore)
    }

    mutating func resetForRefresh() {
        items = []
        nextCursor = nil
        canLoadMore = true
    }

    private mutating func updateCursor(nextCursor: String?, hasMore: Bool) {
        guard hasMore, let nextCursor, !nextCursor.isEmpty else {
            self.nextCursor = nil
            canLoadMore = false
            return
        }

        self.nextCursor = nextCursor
        canLoadMore = true
    }
}

extension CursorPaginationState: Equatable where Item: Equatable {}

extension CursorPaginatedResponse: CursorPaginatedPage {}

extension CrossFeedItemsResponse: CursorPaginatedPage {}
