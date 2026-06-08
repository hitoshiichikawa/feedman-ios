import XCTest
@testable import Feedman

final class APIDomainModelDecodeTests: XCTestCase {
    private let decoder = JSONDecoder()

    func testItemSummaryDecodesNullableFaviconAndRFC3339Strings() throws {
        let item = try decode(ItemSummary.self, fixture: "item_summary_nullable_favicon")

        XCTAssertEqual(item.feedFaviconURL, nil)
        XCTAssertEqual(item.publishedAt, "2026-06-08T08:30:00Z")
        XCTAssertEqual(item.hatebuFetchedAt, "2026-06-08T08:35:00Z")
        XCTAssertTrue(item.isStarred)
    }

    func testSubscriptionDecodesFeedStatusAndUnreadCount() throws {
        let subscription = try decode(Subscription.self, fixture: "subscription_error_status")

        XCTAssertEqual(subscription.feedStatus, .error)
        XCTAssertEqual(subscription.unreadCount, 0)
        XCTAssertEqual(subscription.errorMessage, "404 Not Found")
        XCTAssertEqual(subscription.feedFaviconURL, "data:image/png;base64,iVBORw0KGgo=")
    }

    func testItemSearchHitDecodesNullablePublishedAtAndFaviconURL() throws {
        let hit = try decode(ItemSearchHit.self, fixture: "item_search_hit_nullable")

        XCTAssertNil(hit.publishedAt)
        XCTAssertNil(hit.faviconURL)
        XCTAssertEqual(hit.feedTitle, "Zenn Trends")
    }

    func testPaginatedResponseDecodesTerminalCursorState() throws {
        let response = try decode(
            CursorPaginatedResponse<ItemSummary>.self,
            fixture: "paginated_items_end"
        )

        XCTAssertEqual(response.items.count, 1)
        XCTAssertNil(response.nextCursor)
        XCTAssertFalse(response.hasMore)
    }

    func testCrossFeedResponseDecodesSinceTimeAsString() throws {
        let response = try decode(CrossFeedItemsResponse.self, fixture: "cross_feed_items_since_time")

        XCTAssertEqual(response.sinceTime, "2026-06-08T10:30:00Z")
        XCTAssertEqual(response.nextCursor, "cursor-next-page")
        XCTAssertTrue(response.hasMore)
    }

    func testFeedmanErrorDecodesDetails() throws {
        let response = try decode(FeedmanErrorResponse.self, fixture: "feedman_error_cooldown")

        XCTAssertEqual(response.error.code, "FEED_COOLDOWN")
        XCTAssertEqual(response.error.message, "Feed fetch is cooling down.")
        XCTAssertEqual(response.error.category, "rate_limit")
        XCTAssertEqual(response.error.action, "retry_later")
        XCTAssertEqual(response.error.details?["retry_after_seconds"]?.intValue, 120)
        XCTAssertEqual(response.error.details?["feed_id"]?.stringValue, "feed-publickey")
    }

    private func decode<T: Decodable>(_ type: T.Type, fixture name: String) throws -> T {
        let data = try fixtureData(named: name)
        return try decoder.decode(T.self, from: data)
    }

    private func fixtureData(named name: String) throws -> Data {
        let bundle = Bundle(for: Self.self)
        let url = try XCTUnwrap(bundle.url(forResource: name, withExtension: "json"))
        return try Data(contentsOf: url)
    }
}
