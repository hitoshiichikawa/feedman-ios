import Foundation
import XCTest
@testable import Feedman

final class ItemRepositoryTests: XCTestCase {
    private let baseURL = URL(string: "https://api.example.com")!

    func testItemDetailSendsAuthenticatedGETAndReturnsDetail() async throws {
        let transport = ItemRepositoryRecordingTransport()
        transport.enqueue(data: itemDetailData(), statusCode: 200)
        let repository = makeRepository(transport: transport)

        let detail = try await repository.itemDetail(id: "item-123", accessToken: "test-access-token")

        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.url?.path, "/api/items/item-123")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-access-token")
        XCTAssertEqual(detail.content, "<p>本文 HTML</p>")
        XCTAssertEqual(detail.publishedAt, "2026-06-08T08:30:00Z")
        XCTAssertEqual(detail.hatebuFetchedAt, "2026-06-08T08:35:00Z")
        XCTAssertNil(detail.feedFaviconURL)
        XCTAssertFalse(detail.isRead)
        XCTAssertTrue(detail.isStarred)
    }

    func testReadOnlyStateUpdateSendsPartialPUTBodyAndAcceptsNoContent() async throws {
        let transport = ItemRepositoryRecordingTransport()
        transport.enqueue(data: Data(), statusCode: 204)
        let repository = makeRepository(transport: transport)

        try await repository.updateItemState(
            id: "item-123",
            request: ItemStateUpdateRequest(isRead: true, isStarred: nil),
            accessToken: "test-access-token"
        )

        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.httpMethod, "PUT")
        XCTAssertEqual(request.url?.path, "/api/items/item-123/state")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-access-token")
        let json = try requestBodyJSON(request)
        XCTAssertEqual(Set(json.keys), ["is_read"])
        XCTAssertEqual(boolValue(json["is_read"]), true)
    }

    func testStarOnlyStateUpdateSendsPartialPUTBodyAndIgnoresSuccessfulBody() async throws {
        let transport = ItemRepositoryRecordingTransport()
        transport.enqueue(data: Data(#"{"ignored":true}"#.utf8), statusCode: 200)
        let repository = makeRepository(transport: transport)

        try await repository.updateItemState(
            id: "item-123",
            request: ItemStateUpdateRequest(isRead: nil, isStarred: false),
            accessToken: "test-access-token"
        )

        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.httpMethod, "PUT")
        XCTAssertEqual(request.url?.path, "/api/items/item-123/state")
        let json = try requestBodyJSON(request)
        XCTAssertEqual(Set(json.keys), ["is_starred"])
        XCTAssertEqual(boolValue(json["is_starred"]), false)
    }

    func testCombinedStateUpdateSendsBothRequestedFields() async throws {
        let transport = ItemRepositoryRecordingTransport()
        transport.enqueue(data: Data(), statusCode: 204)
        let repository = makeRepository(transport: transport)

        try await repository.updateItemState(
            id: "item-123",
            request: ItemStateUpdateRequest(isRead: false, isStarred: true),
            accessToken: "test-access-token"
        )

        let request = try XCTUnwrap(transport.requests.first)
        let json = try requestBodyJSON(request)
        XCTAssertEqual(Set(json.keys), ["is_read", "is_starred"])
        XCTAssertEqual(boolValue(json["is_read"]), false)
        XCTAssertEqual(boolValue(json["is_starred"]), true)
    }

    func testItemDetailPreservesFeedmanErrorContext() async {
        let transport = ItemRepositoryRecordingTransport()
        transport.enqueue(data: feedmanErrorData(code: "ITEM_NOT_FOUND"), statusCode: 404)
        let repository = makeRepository(transport: transport)

        do {
            _ = try await repository.itemDetail(id: "missing-item", accessToken: "test-access-token")
            XCTFail("Expected FeedmanAPIError.feedmanError")
        } catch let FeedmanAPIError.feedmanError(context) {
            XCTAssertEqual(context.statusCode, 404)
            XCTAssertEqual(context.code, "ITEM_NOT_FOUND")
            XCTAssertEqual(context.category, "validation")
            XCTAssertEqual(context.action, "fix_request")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testStateUpdatePreservesFeedmanErrorContext() async {
        let transport = ItemRepositoryRecordingTransport()
        transport.enqueue(data: feedmanErrorData(code: "INVALID_STATE"), statusCode: 400)
        let repository = makeRepository(transport: transport)

        do {
            try await repository.updateItemState(
                id: "item-123",
                request: ItemStateUpdateRequest(isRead: true, isStarred: nil),
                accessToken: "test-access-token"
            )
            XCTFail("Expected FeedmanAPIError.feedmanError")
        } catch let FeedmanAPIError.feedmanError(context) {
            XCTAssertEqual(context.statusCode, 400)
            XCTAssertEqual(context.code, "INVALID_STATE")
            XCTAssertEqual(context.category, "validation")
            XCTAssertEqual(context.action, "fix_request")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testMockItemRepositoryReturnsConfiguredDetail() async throws {
        let detail = makeItemDetail(id: "item-123", isRead: false, isStarred: true)
        let repository = MockItemRepository(itemDetails: ["item-123": detail])

        let returnedDetail = try await repository.itemDetail(id: "item-123", accessToken: "unused-token")

        XCTAssertEqual(returnedDetail, detail)
    }

    func testMockItemRepositoryMissingDetailFailsDeterministically() async {
        let repository = MockItemRepository()

        do {
            _ = try await repository.itemDetail(id: "missing-item", accessToken: "unused-token")
            XCTFail("Expected MockItemRepositoryError.detailNotFound")
        } catch let MockItemRepositoryError.detailNotFound(id) {
            XCTAssertEqual(id, "missing-item")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testMockItemRepositoryRecordsAndMutatesOnlyRequestedStateFields() async throws {
        let detail = makeItemDetail(id: "item-123", isRead: false, isStarred: true)
        let repository = MockItemRepository(itemDetails: ["item-123": detail])

        try await repository.updateItemState(
            id: "item-123",
            request: ItemStateUpdateRequest(isRead: true, isStarred: nil),
            accessToken: "unused-token"
        )

        XCTAssertEqual(
            repository.stateUpdates,
            [MockItemStateUpdate(itemID: "item-123", request: ItemStateUpdateRequest(isRead: true, isStarred: nil))]
        )
        XCTAssertEqual(repository.itemDetails["item-123"]?.isRead, true)
        XCTAssertEqual(repository.itemDetails["item-123"]?.isStarred, true)
    }

    func testMockItemRepositoryConfiguredStateFailureDoesNotRecordSuccess() async {
        let repository = MockItemRepository(stateUpdateFailure: StubItemRepositoryError.failed)

        do {
            try await repository.updateItemState(
                id: "item-123",
                request: ItemStateUpdateRequest(isRead: true, isStarred: nil),
                accessToken: "unused-token"
            )
            XCTFail("Expected StubItemRepositoryError.failed")
        } catch let error as StubItemRepositoryError {
            XCTAssertEqual(error, .failed)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        XCTAssertTrue(repository.stateUpdates.isEmpty)
    }

    private func makeRepository(transport: ItemRepositoryRecordingTransport) -> FeedmanItemRepository {
        FeedmanItemRepository(apiClient: APIClient(baseURL: baseURL, transport: transport))
    }

    private func requestBodyJSON(_ request: URLRequest) throws -> [String: Any] {
        let body = try XCTUnwrap(request.httpBody)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
    }

    private func boolValue(_ value: Any?) -> Bool? {
        (value as? NSNumber)?.boolValue
    }

    private func itemDetailData() -> Data {
        Data(
            """
            {
              "id": "item-123",
              "feed_id": "feed-123",
              "feed_title": "Feed Title",
              "feed_favicon_url": null,
              "title": "Article Title",
              "summary": "Summary",
              "content": "<p>本文 HTML</p>",
              "link": "https://example.com/articles/123",
              "published_at": "2026-06-08T08:30:00Z",
              "is_date_estimated": false,
              "is_read": false,
              "is_starred": true,
              "hatebu_count": 42,
              "hatebu_fetched_at": "2026-06-08T08:35:00Z",
              "author": "Author"
            }
            """.utf8
        )
    }

    private func feedmanErrorData(code: String) -> Data {
        Data(
            """
            {
              "error": {
                "code": "\(code)",
                "message": "Request is invalid.",
                "category": "validation",
                "action": "fix_request"
              }
            }
            """.utf8
        )
    }

    private func makeItemDetail(
        id: String,
        isRead: Bool,
        isStarred: Bool
    ) -> ItemDetail {
        ItemDetail(
            id: id,
            feedID: "feed-123",
            feedTitle: "Feed Title",
            feedFaviconURL: "data:image/png;base64,iVBORw0KGgo=",
            title: "Article Title",
            summary: "Summary",
            content: "<p>本文 HTML</p>",
            link: "https://example.com/articles/123",
            publishedAt: "2026-06-08T08:30:00Z",
            isDateEstimated: false,
            isRead: isRead,
            isStarred: isStarred,
            hatebuCount: 42,
            hatebuFetchedAt: "2026-06-08T08:35:00Z",
            author: "Author"
        )
    }
}

private final class ItemRepositoryRecordingTransport: APITransport, @unchecked Sendable {
    private(set) var requests: [URLRequest] = []
    private var queuedResults: [(Data, Int)] = []

    func enqueue(data: Data, statusCode: Int) {
        queuedResults.append((data, statusCode))
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        requests.append(request)
        guard !queuedResults.isEmpty else {
            throw URLError(.badServerResponse)
        }

        let (data, statusCode) = queuedResults.removeFirst()
        let response = HTTPURLResponse(
            url: request.url ?? URL(string: "https://api.example.com")!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
        )!
        return (data, response)
    }
}

private enum StubItemRepositoryError: Error, Equatable {
    case failed
}
