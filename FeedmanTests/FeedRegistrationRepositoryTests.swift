import XCTest
@testable import Feedman

final class FeedRegistrationRepositoryTests: XCTestCase {
    private let baseURL = URL(string: "https://api.example.com")!

    func testRegisterFeedPostsURLWithBearerTokenAndMapsResponse() async throws {
        let transport = RecordingFeedRegistrationTransport()
        transport.enqueueSuccess(data: try fixtureData(named: "feed_registration_response"))
        let repository = makeRepository(transport: transport)

        let registeredFeed = try await repository.registerFeed(url: "https://example.com/feed.xml")

        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.url?.path, "/api/feeds")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer access-token")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")

        let body = try XCTUnwrap(request.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: String])
        XCTAssertEqual(json, ["url": "https://example.com/feed.xml"])

        XCTAssertNil(registeredFeed.subscriptionID)
        XCTAssertEqual(registeredFeed.feedID, "feed-registered")
        XCTAssertEqual(registeredFeed.title, "Registered Feed")
        XCTAssertEqual(registeredFeed.faviconURL, nil)
        XCTAssertEqual(
            registeredFeed.drawerFeed,
            Feed(
                id: "feed-registered",
                subscriptionID: nil,
                title: "Registered Feed",
                unreadCount: 0,
                status: .active,
                fetchIntervalMinutes: nil
            )
        )
    }

    func testRegisterFeedAcceptsSuccessfulNoContentResponse() async throws {
        let transport = RecordingFeedRegistrationTransport()
        transport.enqueueSuccess(data: Data(), statusCode: 204)
        let repository = makeRepository(transport: transport)

        let registeredFeed = try await repository.registerFeed(url: "https://example.com/feed.xml")

        XCTAssertNil(registeredFeed.subscriptionID)
        XCTAssertEqual(registeredFeed.feedID, "https://example.com/feed.xml")
        XCTAssertEqual(registeredFeed.title, "https://example.com/feed.xml")
        XCTAssertEqual(registeredFeed.feedURL, "https://example.com/feed.xml")
        XCTAssertEqual(transport.requests.count, 1)
    }

    func testRegisterFeedPreservesDuplicateErrorContext() async throws {
        let transport = RecordingFeedRegistrationTransport()
        transport.enqueueFeedmanError(
            statusCode: 409,
            code: "DUPLICATE_SUBSCRIPTION",
            category: "conflict"
        )
        let repository = makeRepository(transport: transport)

        do {
            _ = try await repository.registerFeed(url: "https://example.com/feed.xml")
            XCTFail("Expected duplicate feedman error")
        } catch FeedmanAPIError.feedmanError(let context) {
            XCTAssertEqual(context.statusCode, 409)
            XCTAssertEqual(context.code, "DUPLICATE_SUBSCRIPTION")
            XCTAssertEqual(context.category, "conflict")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testRegisterFeedPreservesInvalidURLErrorContext() async throws {
        let transport = RecordingFeedRegistrationTransport()
        transport.enqueueFeedmanError(
            statusCode: 400,
            code: "INVALID_FEED_URL",
            category: "validation"
        )
        let repository = makeRepository(transport: transport)

        do {
            _ = try await repository.registerFeed(url: "not a url")
            XCTFail("Expected invalid URL feedman error")
        } catch FeedmanAPIError.feedmanError(let context) {
            XCTAssertEqual(context.statusCode, 400)
            XCTAssertEqual(context.code, "INVALID_FEED_URL")
            XCTAssertEqual(context.category, "validation")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testRegisterFeedPreservesRateLimitRetryMetadata() async throws {
        let transport = RecordingFeedRegistrationTransport()
        transport.enqueueFeedmanError(
            statusCode: 429,
            code: "FEED_COOLDOWN",
            category: "rate_limit",
            retryAfterSeconds: 120
        )
        let repository = makeRepository(transport: transport)

        do {
            _ = try await repository.registerFeed(url: "https://example.com/feed.xml")
            XCTFail("Expected rate limit feedman error")
        } catch FeedmanAPIError.feedmanError(let context) {
            XCTAssertEqual(context.statusCode, 429)
            XCTAssertEqual(context.code, "FEED_COOLDOWN")
            XCTAssertEqual(context.category, "rate_limit")
            XCTAssertEqual(context.retryAfterSeconds, 120)
            XCTAssertEqual(context.retryAfter, "120")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    private func makeRepository(transport: RecordingFeedRegistrationTransport) -> APIClientFeedRepository {
        APIClientFeedRepository(
            apiClient: APIClient(baseURL: baseURL, transport: transport),
            accessTokenProvider: {
                "access-token"
            }
        )
    }

    private func fixtureData(named name: String) throws -> Data {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: name, withExtension: "json"))
        return try Data(contentsOf: url)
    }
}

private final class RecordingFeedRegistrationTransport: APITransport, @unchecked Sendable {
    private enum Result {
        case success(Data, statusCode: Int)
        case feedmanError(statusCode: Int, code: String, category: String, retryAfterSeconds: Int?)
    }

    private(set) var requests: [URLRequest] = []
    private var results: [Result] = []

    func enqueueSuccess(data: Data, statusCode: Int = 200) {
        results.append(.success(data, statusCode: statusCode))
    }

    func enqueueFeedmanError(
        statusCode: Int,
        code: String,
        category: String,
        retryAfterSeconds: Int? = nil
    ) {
        results.append(
            .feedmanError(
                statusCode: statusCode,
                code: code,
                category: category,
                retryAfterSeconds: retryAfterSeconds
            )
        )
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        requests.append(request)

        guard !results.isEmpty else {
            throw URLError(.badServerResponse)
        }

        switch results.removeFirst() {
        case let .success(data, statusCode):
            return (data, httpResponse(statusCode: statusCode, request: request))
        case let .feedmanError(statusCode, code, category, retryAfterSeconds):
            let data = Data(
                """
                {
                  "error": {
                    "code": "\(code)",
                    "message": "Registration failed.",
                    "category": "\(category)",
                    "action": "fix_request"\(retryDetails(retryAfterSeconds))
                  }
                }
                """.utf8
            )
            let headers = retryAfterSeconds.map { ["Retry-After": String($0)] }
            return (data, httpResponse(statusCode: statusCode, request: request, headers: headers))
        }
    }

    private func retryDetails(_ seconds: Int?) -> String {
        guard let seconds else {
            return ""
        }

        return #", "details": { "retry_after_seconds": \#(seconds) }"#
    }

    private func httpResponse(
        statusCode: Int,
        request: URLRequest,
        headers: [String: String]? = nil
    ) -> HTTPURLResponse {
        HTTPURLResponse(
            url: request.url ?? URL(string: "https://api.example.com")!,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: headers
        )!
    }
}
