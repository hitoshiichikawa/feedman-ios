import XCTest
@testable import Feedman

final class CrossFeedRepositoryTests: XCTestCase {
    private let baseURL = URL(string: "https://api.example.com")!

    func testFirstPageRequestsCrossFeedWithLimitOnlyAndStoresSinceTime() async throws {
        let transport = RecordingCrossFeedTransport()
        transport.enqueue(response: page(ids: ["item-1"], nextCursor: "cursor-2", hasMore: true, sinceTime: "2026-06-08T10:30:00Z"))
        let repository = makeRepository(transport: transport)

        let snapshot = try await repository.loadCrossFeedFirstPage(limit: nil)

        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.url?.path, "/api/items/cross-feed")
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer access-token")
        XCTAssertEqual(queryValue("limit", in: request), "50")
        XCTAssertNil(queryValue("cursor", in: request))
        XCTAssertNil(queryValue("since_time", in: request))
        XCTAssertEqual(snapshot.items.map(\.id), ["item-1"])
        XCTAssertEqual(snapshot.sinceTime, "2026-06-08T10:30:00Z")
        XCTAssertEqual(snapshot.nextCursor, "cursor-2")
        XCTAssertTrue(snapshot.canLoadMore)
    }

    func testNextPageSendsStoredCursorAndFirstPageSinceTimeThenAppendsItems() async throws {
        let transport = RecordingCrossFeedTransport()
        transport.enqueue(response: page(ids: ["item-1"], nextCursor: "cursor-2", hasMore: true, sinceTime: "2026-06-08T10:30:00Z"))
        transport.enqueue(response: page(ids: ["item-2"], nextCursor: nil, hasMore: false, sinceTime: "2026-06-08T10:35:00Z"))
        let repository = makeRepository(transport: transport)

        _ = try await repository.loadCrossFeedFirstPage(limit: 25)
        let snapshot = try await repository.loadCrossFeedNextPage()

        let request = try XCTUnwrap(transport.requests.last)
        XCTAssertEqual(queryValue("limit", in: request), "25")
        XCTAssertEqual(queryValue("cursor", in: request), "cursor-2")
        XCTAssertEqual(queryValue("since_time", in: request), "2026-06-08T10:30:00Z")
        XCTAssertEqual(snapshot.items.map(\.id), ["item-1", "item-2"])
        XCTAssertEqual(snapshot.sinceTime, "2026-06-08T10:30:00Z")
        XCTAssertFalse(snapshot.canLoadMore)
    }

    func testTerminalPageDoesNotRequestAnotherNextPage() async throws {
        let transport = RecordingCrossFeedTransport()
        transport.enqueue(response: page(ids: ["item-1"], nextCursor: "ignored", hasMore: false, sinceTime: "2026-06-08T10:30:00Z"))
        let repository = makeRepository(transport: transport)

        let firstSnapshot = try await repository.loadCrossFeedFirstPage(limit: nil)
        let nextSnapshot = try await repository.loadCrossFeedNextPage()

        XCTAssertEqual(transport.requests.count, 1)
        XCTAssertEqual(nextSnapshot, firstSnapshot)
        XCTAssertFalse(nextSnapshot.canLoadMore)
    }

    func testNilAndEmptyNextCursorAreTerminal() async throws {
        let nilCursorTransport = RecordingCrossFeedTransport()
        nilCursorTransport.enqueue(response: page(ids: ["item-1"], nextCursor: nil, hasMore: true, sinceTime: "2026-06-08T10:30:00Z"))
        let nilCursorRepository = makeRepository(transport: nilCursorTransport)

        let nilCursorSnapshot = try await nilCursorRepository.loadCrossFeedFirstPage(limit: nil)

        XCTAssertNil(nilCursorSnapshot.nextCursor)
        XCTAssertFalse(nilCursorSnapshot.canLoadMore)

        let emptyCursorTransport = RecordingCrossFeedTransport()
        emptyCursorTransport.enqueue(response: page(ids: ["item-1"], nextCursor: "", hasMore: true, sinceTime: "2026-06-08T10:30:00Z"))
        let emptyCursorRepository = makeRepository(transport: emptyCursorTransport)

        let emptyCursorSnapshot = try await emptyCursorRepository.loadCrossFeedFirstPage(limit: nil)

        XCTAssertNil(emptyCursorSnapshot.nextCursor)
        XCTAssertFalse(emptyCursorSnapshot.canLoadMore)
    }

    func testRefreshStartsNewSessionWithoutOldCursorOrSinceTime() async throws {
        let transport = RecordingCrossFeedTransport()
        transport.enqueue(response: page(ids: ["item-1"], nextCursor: "cursor-old", hasMore: true, sinceTime: "2026-06-08T10:30:00Z"))
        transport.enqueue(response: page(ids: ["item-new"], nextCursor: nil, hasMore: false, sinceTime: "2026-06-08T11:00:00Z"))
        let repository = makeRepository(transport: transport)

        _ = try await repository.loadCrossFeedFirstPage(limit: nil)
        let refreshedSnapshot = try await repository.loadCrossFeedFirstPage(limit: nil)

        let refreshRequest = try XCTUnwrap(transport.requests.last)
        XCTAssertEqual(queryValue("limit", in: refreshRequest), "50")
        XCTAssertNil(queryValue("cursor", in: refreshRequest))
        XCTAssertNil(queryValue("since_time", in: refreshRequest))
        XCTAssertEqual(refreshedSnapshot.items.map(\.id), ["item-new"])
        XCTAssertEqual(refreshedSnapshot.sinceTime, "2026-06-08T11:00:00Z")
    }

    func testInvalidLimitsAreNormalizedDeterministically() async throws {
        let highLimitTransport = RecordingCrossFeedTransport()
        highLimitTransport.enqueue(response: page(ids: ["item-1"], nextCursor: "cursor-2", hasMore: true, sinceTime: "2026-06-08T10:30:00Z"))
        highLimitTransport.enqueue(response: page(ids: ["item-2"], nextCursor: nil, hasMore: false, sinceTime: "2026-06-08T10:35:00Z"))
        let highLimitRepository = makeRepository(transport: highLimitTransport)

        _ = try await highLimitRepository.loadCrossFeedFirstPage(limit: 500)
        _ = try await highLimitRepository.loadCrossFeedNextPage()

        XCTAssertEqual(queryValue("limit", in: try XCTUnwrap(highLimitTransport.requests.first)), "200")
        XCTAssertEqual(queryValue("limit", in: try XCTUnwrap(highLimitTransport.requests.last)), "200")

        let nonPositiveTransport = RecordingCrossFeedTransport()
        nonPositiveTransport.enqueue(response: page(ids: ["item-1"], nextCursor: nil, hasMore: false, sinceTime: "2026-06-08T10:30:00Z"))
        let nonPositiveRepository = makeRepository(transport: nonPositiveTransport)

        _ = try await nonPositiveRepository.loadCrossFeedFirstPage(limit: 0)

        XCTAssertEqual(queryValue("limit", in: try XCTUnwrap(nonPositiveTransport.requests.first)), "50")
    }

    func testNextPageBeforeFirstPageFailsWithoutNetworkRequest() async {
        let transport = RecordingCrossFeedTransport()
        let repository = makeRepository(transport: transport)

        do {
            _ = try await repository.loadCrossFeedNextPage()
            XCTFail("Expected nextPageRequestedBeforeFirstPage")
        } catch CrossFeedRepositoryError.nextPageRequestedBeforeFirstPage {
            XCTAssertTrue(transport.requests.isEmpty)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testNextPageTransportErrorPropagatesAndDoesNotEndPagination() async throws {
        let transport = RecordingCrossFeedTransport()
        transport.enqueue(response: page(ids: ["item-1"], nextCursor: "cursor-2", hasMore: true, sinceTime: "2026-06-08T10:30:00Z"))
        transport.enqueue(error: URLError(.notConnectedToInternet))
        transport.enqueue(response: page(ids: ["item-2"], nextCursor: nil, hasMore: false, sinceTime: "2026-06-08T10:35:00Z"))
        let repository = makeRepository(transport: transport)

        _ = try await repository.loadCrossFeedFirstPage(limit: nil)
        do {
            _ = try await repository.loadCrossFeedNextPage()
            XCTFail("Expected FeedmanAPIError.transportFailed")
        } catch FeedmanAPIError.transportFailed(let underlyingError) {
            XCTAssertEqual((underlyingError as? URLError)?.code, .notConnectedToInternet)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        let recoveredSnapshot = try await repository.loadCrossFeedNextPage()

        XCTAssertEqual(queryValue("cursor", in: try XCTUnwrap(transport.requests.last)), "cursor-2")
        XCTAssertEqual(recoveredSnapshot.items.map(\.id), ["item-1", "item-2"])
    }

    func testAuthRequiredErrorPropagatesWithoutEmptyTerminalState() async {
        let transport = RecordingCrossFeedTransport()
        transport.enqueueErrorResponse(statusCode: 401, code: "ACCESS_TOKEN_EXPIRED")
        let repository = makeRepository(transport: transport)

        do {
            _ = try await repository.loadCrossFeedFirstPage(limit: nil)
            XCTFail("Expected FeedmanAPIError.authRequired")
        } catch FeedmanAPIError.authRequired(let context) {
            XCTAssertEqual(context.reason, .missingRefreshHook)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testSubscriptionsRequestsAuthenticatedEndpointAndMapsDrawerFeeds() async throws {
        let transport = RecordingSubscriptionTransport()
        transport.enqueue(
            subscriptions: [
                subscription(
                    id: "sub-active",
                    feedID: "feed-active",
                    title: "Active Feed",
                    faviconURL: "data:image/png;base64,iVBORw0KGgo=",
                    status: .active,
                    errorMessage: nil,
                    unreadCount: 3
                ),
                subscription(
                    id: "sub-stopped",
                    feedID: "feed-stopped",
                    title: "Stopped Feed",
                    faviconURL: nil,
                    status: .stopped,
                    errorMessage: "manually paused",
                    unreadCount: 0
                ),
                subscription(
                    id: "sub-error",
                    feedID: "feed-error",
                    title: "Error Feed",
                    faviconURL: nil,
                    status: .error,
                    errorMessage: "404 Not Found",
                    unreadCount: 12
                )
            ]
        )
        let repository = makeSubscriptionRepository(transport: transport)

        let feeds = try await repository.subscriptions()

        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.url?.path, "/api/subscriptions")
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer access-token")
        XCTAssertEqual(
            feeds,
            [
                Feed(
                    id: "feed-active",
                    title: "Active Feed",
                    unreadCount: 3,
                    status: .active,
                    faviconURL: "data:image/png;base64,iVBORw0KGgo="
                ),
                Feed(
                    id: "feed-stopped",
                    title: "Stopped Feed",
                    unreadCount: 0,
                    status: .stopped(message: "manually paused")
                ),
                Feed(
                    id: "feed-error",
                    title: "Error Feed",
                    unreadCount: 12,
                    status: .error(message: "404 Not Found")
                )
            ]
        )
    }

    func testSubscriptionsEmptyResponseReturnsEmptyFeeds() async throws {
        let transport = RecordingSubscriptionTransport()
        transport.enqueue(subscriptions: [])
        let repository = makeSubscriptionRepository(transport: transport)

        let feeds = try await repository.subscriptions()

        XCTAssertEqual(feeds, [])
    }

    func testSubscriptionsClampsNegativeUnreadCount() async throws {
        let transport = RecordingSubscriptionTransport()
        transport.enqueue(
            subscriptions: [
                subscription(
                    id: "sub-negative",
                    feedID: "feed-negative",
                    title: "Negative Feed",
                    status: .active,
                    unreadCount: -8
                )
            ]
        )
        let repository = makeSubscriptionRepository(transport: transport)

        let feeds = try await repository.subscriptions()

        XCTAssertEqual(feeds.first?.unreadCount, 0)
    }

    func testSubscriptionsRefreshesExpiredAccessTokenAndRetries() async throws {
        let transport = RecordingSubscriptionTransport()
        transport.enqueueErrorResponse(statusCode: 401, code: "ACCESS_TOKEN_EXPIRED")
        transport.enqueue(
            subscriptions: [
                subscription(
                    id: "sub-retried",
                    feedID: "feed-retried",
                    title: "Retried Feed",
                    status: .active,
                    unreadCount: 1
                )
            ]
        )
        let refreshHook = SubscriptionRefreshHook(refreshedAccessToken: "refreshed-access-token")
        let repository = APIClientFeedRepository(
            apiClient: APIClient(
                baseURL: baseURL,
                transport: transport,
                accessTokenRefreshHook: {
                    try await refreshHook.refresh()
                }
            ),
            accessTokenProvider: {
                "expired-access-token"
            }
        )

        let feeds = try await repository.subscriptions()

        XCTAssertEqual(feeds.map(\.id), ["feed-retried"])
        XCTAssertEqual(await refreshHook.callCount, 1)
        XCTAssertEqual(transport.requests.count, 2)
        XCTAssertEqual(
            transport.requests.first?.value(forHTTPHeaderField: "Authorization"),
            "Bearer expired-access-token"
        )
        XCTAssertEqual(
            transport.requests.last?.value(forHTTPHeaderField: "Authorization"),
            "Bearer refreshed-access-token"
        )
    }

    private func makeRepository(transport: RecordingCrossFeedTransport) -> APIClientFeedRepository {
        APIClientFeedRepository(
            apiClient: APIClient(baseURL: baseURL, transport: transport),
            accessTokenProvider: {
                "access-token"
            }
        )
    }

    private func makeSubscriptionRepository(
        transport: RecordingSubscriptionTransport
    ) -> APIClientFeedRepository {
        APIClientFeedRepository(
            apiClient: APIClient(baseURL: baseURL, transport: transport),
            accessTokenProvider: {
                "access-token"
            }
        )
    }

    private func queryValue(_ name: String, in request: URLRequest) -> String? {
        guard
            let url = request.url,
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else {
            return nil
        }

        return components.queryItems?.first(where: { $0.name == name })?.value
    }

    private func page(
        ids: [String],
        nextCursor: String?,
        hasMore: Bool,
        sinceTime: String
    ) -> CrossFeedItemsResponse {
        CrossFeedItemsResponse(
            items: ids.enumerated().map { offset, id in
                ItemSummary(
                    id: id,
                    feedID: "feed-\(offset + 1)",
                    feedTitle: "Feed \(offset + 1)",
                    feedFaviconURL: nil,
                    title: "Title \(id)",
                    summary: "Summary \(id)",
                    link: "https://example.com/\(id)",
                    publishedAt: "2026-06-08T08:30:00Z",
                    isDateEstimated: false,
                    isRead: false,
                    isStarred: false,
                    hatebuCount: nil,
                    hatebuFetchedAt: nil,
                    author: nil
                )
            },
            nextCursor: nextCursor,
            hasMore: hasMore,
            sinceTime: sinceTime
        )
    }

    private func subscription(
        id: String,
        feedID: String,
        title: String,
        faviconURL: String? = nil,
        status: SubscriptionFeedStatus,
        errorMessage: String? = nil,
        unreadCount: Int
    ) -> Subscription {
        Subscription(
            id: id,
            feedID: feedID,
            feedTitle: title,
            feedURL: "https://example.com/\(feedID).xml",
            siteURL: "https://example.com/\(feedID)",
            feedFaviconURL: faviconURL,
            fetchIntervalMinutes: 60,
            feedStatus: status,
            errorMessage: errorMessage,
            unreadCount: unreadCount
        )
    }
}

private final class RecordingCrossFeedTransport: APITransport, @unchecked Sendable {
    private enum Result {
        case response(CrossFeedItemsResponse)
        case errorResponse(statusCode: Int, code: String)
        case error(Error)
    }

    private(set) var requests: [URLRequest] = []
    private var results: [Result] = []
    private let encoder = JSONEncoder()

    func enqueue(response: CrossFeedItemsResponse) {
        results.append(.response(response))
    }

    func enqueueErrorResponse(statusCode: Int, code: String) {
        results.append(.errorResponse(statusCode: statusCode, code: code))
    }

    func enqueue(error: Error) {
        results.append(.error(error))
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        requests.append(request)

        guard !results.isEmpty else {
            throw URLError(.badServerResponse)
        }

        switch results.removeFirst() {
        case .response(let response):
            let data = try encoder.encode(response)
            return (data, httpResponse(statusCode: 200, request: request))
        case .errorResponse(let statusCode, let code):
            let data = Data("""
            {
              "error": {
                "code": "\(code)",
                "message": "rejected",
                "category": "auth",
                "action": "reauthenticate"
              }
            }
            """.utf8)
            return (data, httpResponse(statusCode: statusCode, request: request))
        case .error(let error):
            throw error
        }
    }

    private func httpResponse(statusCode: Int, request: URLRequest) -> HTTPURLResponse {
        HTTPURLResponse(
            url: request.url ?? URL(string: "https://api.example.com")!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
        )!
    }
}

private final class RecordingSubscriptionTransport: APITransport, @unchecked Sendable {
    private enum Result {
        case subscriptions([Subscription])
        case errorResponse(statusCode: Int, code: String)
    }

    private(set) var requests: [URLRequest] = []
    private var results: [Result] = []
    private let encoder = JSONEncoder()

    func enqueue(subscriptions: [Subscription]) {
        results.append(.subscriptions(subscriptions))
    }

    func enqueueErrorResponse(statusCode: Int, code: String) {
        results.append(.errorResponse(statusCode: statusCode, code: code))
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        requests.append(request)

        guard !results.isEmpty else {
            throw URLError(.badServerResponse)
        }

        switch results.removeFirst() {
        case .subscriptions(let subscriptions):
            let data = try encoder.encode(subscriptions)
            return (data, httpResponse(statusCode: 200, request: request))
        case .errorResponse(let statusCode, let code):
            let data = Data("""
            {
              "error": {
                "code": "\(code)",
                "message": "rejected",
                "category": "auth",
                "action": "reauthenticate"
              }
            }
            """.utf8)
            return (data, httpResponse(statusCode: statusCode, request: request))
        }
    }

    private func httpResponse(statusCode: Int, request: URLRequest) -> HTTPURLResponse {
        HTTPURLResponse(
            url: request.url ?? URL(string: "https://api.example.com")!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
        )!
    }
}

private actor SubscriptionRefreshHook {
    private let refreshedAccessToken: String
    private(set) var callCount = 0

    init(refreshedAccessToken: String) {
        self.refreshedAccessToken = refreshedAccessToken
    }

    func refresh() async throws -> String {
        callCount += 1
        return refreshedAccessToken
    }
}
