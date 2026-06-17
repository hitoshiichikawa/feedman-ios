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
            httpVersion: "HTTP/1.1",
            headerFields: nil
        )!
        return (data, response)
    }
}
