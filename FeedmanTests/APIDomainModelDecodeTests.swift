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

    func testFeedRegistrationResponseDecodesFlatFeedResponse() throws {
        let response = try decode(FeedRegistrationResponse.self, fixture: "feed_registration_response")

        XCTAssertEqual(response.id, "feed-registered")
        XCTAssertEqual(response.feedURL, "https://example.com/feed.xml")
        XCTAssertEqual(response.siteURL, "https://example.com")
        XCTAssertEqual(response.title, "Registered Feed")
        XCTAssertEqual(response.fetchStatus, "active")
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

    func testSearchItemsResponseDecodesWrapperMetadata() throws {
        let data = Data(
            """
            {
              "items": [
                {
                  "id": "search-1",
                  "feed_id": "feed-1",
                  "feed_title": "Search Feed",
                  "favicon_url": null,
                  "title": "Search Title",
                  "summary": "Search summary",
                  "link": "https://example.com/search-1",
                  "published_at": "2026-06-08T08:30:00Z",
                  "is_date_estimated": false,
                  "is_read": false,
                  "is_starred": false,
                  "hatebu_count": 3,
                  "author": null
                }
              ],
              "next_cursor": "cursor-next",
              "has_more": true
            }
            """.utf8
        )

        let response = try decoder.decode(SearchItemsResponse.self, from: data)

        XCTAssertEqual(response.items.map(\.id), ["search-1"])
        XCTAssertEqual(response.nextCursor, "cursor-next")
        XCTAssertTrue(response.hasMore)
    }

    func testFeedScopedItemSummaryDecodesWithoutFeedMetadata() throws {
        let data = Data(
            """
            {
              "id": "item-1",
              "feed_id": "feed-1",
              "title": "Feed item",
              "summary": null,
              "link": "https://example.com/item-1",
              "published_at": "2026-06-08T08:30:00Z",
              "is_date_estimated": false,
              "is_read": false,
              "is_starred": false,
              "hatebu_count": null,
              "hatebu_fetched_at": null,
              "author": null
            }
            """.utf8
        )

        let item = try decoder.decode(ItemSummary.self, from: data)

        XCTAssertEqual(item.feedTitle, "")
        XCTAssertNil(item.feedFaviconURL)
        XCTAssertEqual(item.title, "Feed item")
    }

    func testItemDetailDecodesWithoutFeedMetadata() throws {
        let data = Data(
            """
            {
              "id": "item-1",
              "feed_id": "feed-1",
              "title": "Detail item",
              "summary": null,
              "content": "<p>body</p>",
              "link": "https://example.com/item-1",
              "published_at": "2026-06-08T08:30:00Z",
              "is_date_estimated": false,
              "is_read": false,
              "is_starred": false,
              "hatebu_count": null,
              "hatebu_fetched_at": null,
              "author": null
            }
            """.utf8
        )

        let detail = try decoder.decode(ItemDetail.self, from: data)

        XCTAssertEqual(detail.feedTitle, "")
        XCTAssertNil(detail.feedFaviconURL)
        XCTAssertEqual(detail.content, "<p>body</p>")
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
