import XCTest
@testable import Feedman

final class SubscriptionActionRepositoryTests: XCTestCase {
    private let baseURL = URL(string: "https://api.example.com")!

    func testUpdateSubscriptionSettingsSendsPUTBodyAndBearerToken() async throws {
        let transport = RecordingSubscriptionActionTransport()
        transport.enqueue(data: Data(), statusCode: 204)
        let repository = makeRepository(transport: transport)

        try await repository.updateSubscriptionSettings(
            subscriptionID: "sub-123",
            request: SubscriptionSettingsRequest(fetchIntervalMinutes: 30)
        )

        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.httpMethod, "PUT")
        XCTAssertEqual(request.url?.path, "/api/subscriptions/sub-123/settings")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer access-token")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")

        let body = try XCTUnwrap(request.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(Set(json.keys), ["fetch_interval_minutes"])
        XCTAssertEqual((json["fetch_interval_minutes"] as? NSNumber)?.intValue, 30)
    }

    func testResumeSubscriptionSendsPOSTWithBearerTokenAndNoBody() async throws {
        let transport = RecordingSubscriptionActionTransport()
        transport.enqueue(data: Data(), statusCode: 204)
        let repository = makeRepository(transport: transport)

        try await repository.resumeSubscription(subscriptionID: "sub-123")

        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.path, "/api/subscriptions/sub-123/resume")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer access-token")
        XCTAssertNil(request.value(forHTTPHeaderField: "Content-Type"))
        XCTAssertNil(request.httpBody)
    }

    func testManualFetchSubscriptionSendsPOSTWithBearerTokenAndNoBody() async throws {
        let transport = RecordingSubscriptionActionTransport()
        transport.enqueue(data: Data(), statusCode: 204)
        let repository = makeRepository(transport: transport)

        try await repository.manualFetchSubscription(subscriptionID: "sub-123")

        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.path, "/api/subscriptions/sub-123/fetch")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer access-token")
        XCTAssertNil(request.value(forHTTPHeaderField: "Content-Type"))
        XCTAssertNil(request.httpBody)
    }

    func testManualFetchSubscriptionTreatsAny2xxAsSuccessWithoutBody() async throws {
        let transport = RecordingSubscriptionActionTransport()
        transport.enqueue(data: Data(), statusCode: 202)
        let repository = makeRepository(transport: transport)

        try await repository.manualFetchSubscription(subscriptionID: "sub-123")

        XCTAssertEqual(transport.requests.count, 1)
    }

    func testManualFetchSubscriptionPreservesCooldownErrorMetadata() async throws {
        let transport = RecordingSubscriptionActionTransport()
        transport.enqueue(
            data: Data("""
            {
              "error": {
                "code": "FEED_COOLDOWN",
                "message": "cooldown",
                "category": "rate_limit",
                "action": "retry_later",
                "details": {
                  "retry_after_seconds": 120
                }
              }
            }
            """.utf8),
            statusCode: 429,
            headers: ["Retry-After": "180"]
        )
        let repository = makeRepository(transport: transport)

        do {
            try await repository.manualFetchSubscription(subscriptionID: "sub-123")
            XCTFail("Expected FeedmanAPIError.feedmanError")
        } catch FeedmanAPIError.feedmanError(let context) {
            XCTAssertEqual(context.statusCode, 429)
            XCTAssertEqual(context.code, "FEED_COOLDOWN")
            XCTAssertEqual(context.retryAfterSeconds, 120)
            XCTAssertEqual(context.retryAfter, "180")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testUnsubscribeSendsDELETEWithBearerTokenAndNoBody() async throws {
        let transport = RecordingSubscriptionActionTransport()
        transport.enqueue(data: Data(), statusCode: 204)
        let repository = makeRepository(transport: transport)

        try await repository.unsubscribe(subscriptionID: "sub-123")

        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.httpMethod, "DELETE")
        XCTAssertEqual(request.url?.path, "/api/subscriptions/sub-123")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer access-token")
        XCTAssertNil(request.value(forHTTPHeaderField: "Content-Type"))
        XCTAssertNil(request.httpBody)
    }

    private func makeRepository(transport: RecordingSubscriptionActionTransport) -> APIClientFeedRepository {
        APIClientFeedRepository(
            apiClient: APIClient(baseURL: baseURL, transport: transport),
            accessTokenProvider: {
                "access-token"
            }
        )
    }
}

private final class RecordingSubscriptionActionTransport: APITransport, @unchecked Sendable {
    private(set) var requests: [URLRequest] = []
    private var queuedResults: [(Data, Int, [String: String]?)] = []

    func enqueue(
        data: Data,
        statusCode: Int,
        headers: [String: String]? = nil
    ) {
        queuedResults.append((data, statusCode, headers))
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        requests.append(request)
        guard !queuedResults.isEmpty else {
            throw URLError(.badServerResponse)
        }

        let (data, statusCode, headers) = queuedResults.removeFirst()
        let response = HTTPURLResponse(
            url: request.url ?? URL(string: "https://api.example.com")!,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: headers
        )!
        return (data, response)
    }
}
