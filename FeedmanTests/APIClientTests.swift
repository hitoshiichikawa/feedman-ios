import XCTest
@testable import Feedman

final class APIClientTests: XCTestCase {
    func testUnauthenticatedGETBuildsAbsoluteURLAndJSONAcceptHeader() async throws {
        let transport = MockAPITransport(data: successData(), response: httpResponse(url: apiURL("/api/items/cross-feed")))
        let client = makeClient(baseURL: URL(string: "https://api.example.com")!, transport: transport)

        let response = try await client.send(ProbeResponse.self, path: "/api/items/cross-feed")

        XCTAssertEqual(response, ProbeResponse(ok: true))
        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.url?.absoluteString, "https://api.example.com/api/items/cross-feed")
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
        XCTAssertNil(request.value(forHTTPHeaderField: "Content-Type"))
        XCTAssertNil(request.httpBody)
    }

    func testBaseURLCanChangeForSameEndpointPath() async throws {
        let firstTransport = MockAPITransport(data: successData(), response: httpResponse(url: apiURL("/api/items/cross-feed")))
        let secondTransport = MockAPITransport(data: successData(), response: httpResponse(url: apiURL("/api/items/cross-feed")))
        let firstClient = makeClient(baseURL: URL(string: "https://api.example.com")!, transport: firstTransport)
        let secondClient = makeClient(baseURL: URL(string: "https://staging.example.com/")!, transport: secondTransport)

        let _: ProbeResponse = try await firstClient.send(ProbeResponse.self, path: "/api/items/cross-feed")
        let _: ProbeResponse = try await secondClient.send(ProbeResponse.self, path: "/api/items/cross-feed")

        XCTAssertEqual(firstTransport.requests.first?.url?.absoluteString, "https://api.example.com/api/items/cross-feed")
        XCTAssertEqual(secondTransport.requests.first?.url?.absoluteString, "https://staging.example.com/api/items/cross-feed")
    }

    func testQueryItemsAreEncoded() async throws {
        let transport = MockAPITransport(data: successData(), response: httpResponse(url: apiURL("/api/search")))
        let client = makeClient(baseURL: URL(string: "https://api.example.com")!, transport: transport)

        let _: ProbeResponse = try await client.send(
            ProbeResponse.self,
            path: "/api/search",
            queryItems: [
                URLQueryItem(name: "q", value: "SwiftUI | 日本語"),
                URLQueryItem(name: "cursor", value: "next page")
            ]
        )

        let url = try XCTUnwrap(transport.requests.first?.url)
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.queryItems?.first(where: { $0.name == "q" })?.value, "SwiftUI | 日本語")
        XCTAssertEqual(components.queryItems?.first(where: { $0.name == "cursor" })?.value, "next page")
        XCTAssertFalse(url.absoluteString.contains(" "))
        XCTAssertTrue(url.absoluteString.contains("%7C"))
    }

    func testPathQueryItemsAreEncoded() async throws {
        let transport = MockAPITransport(data: successData(), response: httpResponse(url: apiURL("/api/search")))
        let client = makeClient(baseURL: URL(string: "https://api.example.com")!, transport: transport)

        let _: ProbeResponse = try await client.send(ProbeResponse.self, path: "/api/search?q=SwiftUI | 日本語")

        let url = try XCTUnwrap(transport.requests.first?.url)
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.queryItems?.first(where: { $0.name == "q" })?.value, "SwiftUI | 日本語")
        XCTAssertFalse(url.absoluteString.contains(" "))
        XCTAssertTrue(url.absoluteString.contains("%7C"))
    }

    func testAuthenticatedRequestAddsBearerToken() async throws {
        let transport = MockAPITransport(data: successData(), response: httpResponse(url: apiURL("/api/me")))
        let client = makeClient(baseURL: URL(string: "https://api.example.com")!, transport: transport)

        let _: ProbeResponse = try await client.send(ProbeResponse.self, path: "/api/me", accessToken: "test-access-token")

        XCTAssertEqual(
            transport.requests.first?.value(forHTTPHeaderField: "Authorization"),
            "Bearer test-access-token"
        )
    }

    func testJSONBodyRequestSetsContentTypeAndEncodesBody() async throws {
        let transport = MockAPITransport(data: successData(), response: httpResponse(url: apiURL("/api/feeds")))
        let client = makeClient(baseURL: URL(string: "https://api.example.com")!, transport: transport)

        let _: ProbeResponse = try await client.send(
            ProbeResponse.self,
            method: .post,
            path: "/api/feeds",
            body: ProbeRequest(url: "https://example.com/feed.xml")
        )

        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")

        let body = try XCTUnwrap(request.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: String])
        XCTAssertEqual(json["url"], "https://example.com/feed.xml")
    }

    func testSuccessResponseDecodesRequestedType() async throws {
        let data = Data(#"{"token_type":"Bearer","access_token":"access","refresh_token":"refresh","expires_in":3600}"#.utf8)
        let transport = MockAPITransport(data: data, response: httpResponse(url: apiURL("/api/auth/token")))
        let client = makeClient(baseURL: URL(string: "https://api.example.com")!, transport: transport)

        let response = try await client.send(AuthTokenResponse.self, method: .post, path: "/api/auth/token")

        XCTAssertEqual(response.tokenType, "Bearer")
        XCTAssertEqual(response.accessToken, "access")
        XCTAssertEqual(response.refreshToken, "refresh")
        XCTAssertEqual(response.expiresIn, 3600)
    }

    func testNonSuccessFeedmanErrorSurfacesTypedError() async throws {
        let data = Data(
            """
            {
              "error": {
                "code": "VALIDATION_FAILED",
                "message": "Request is invalid.",
                "category": "validation",
                "action": "fix_request"
              }
            }
            """.utf8
        )
        let transport = MockAPITransport(
            data: data,
            response: httpResponse(url: apiURL("/api/feeds"), statusCode: 400)
        )
        let client = makeClient(baseURL: URL(string: "https://api.example.com")!, transport: transport)

        do {
            let _: ProbeResponse = try await client.send(ProbeResponse.self, method: .post, path: "/api/feeds")
            XCTFail("Expected FeedmanAPIError.feedmanError")
        } catch FeedmanAPIError.feedmanError(let context) {
            XCTAssertEqual(context.statusCode, 400)
            XCTAssertEqual(context.code, "VALIDATION_FAILED")
            XCTAssertEqual(context.message, "Request is invalid.")
            XCTAssertEqual(context.category, "validation")
            XCTAssertEqual(context.action, "fix_request")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testFeedCooldownPreservesRetryMetadata() async throws {
        let data = Data(
            """
            {
              "error": {
                "code": "FEED_COOLDOWN",
                "message": "Feed fetch is cooling down.",
                "category": "rate_limit",
                "action": "retry_later",
                "details": {
                  "retry_after_seconds": 120
                }
              }
            }
            """.utf8
        )
        let transport = MockAPITransport(
            data: data,
            response: httpResponse(
                url: apiURL("/api/feeds/feed-publickey/refresh"),
                statusCode: 429,
                headers: ["Retry-After": "120"]
            )
        )
        let client = makeClient(baseURL: URL(string: "https://api.example.com")!, transport: transport)

        do {
            let _: ProbeResponse = try await client.send(ProbeResponse.self, method: .post, path: "/api/feeds/feed-publickey/refresh")
            XCTFail("Expected FeedmanAPIError.feedmanError")
        } catch FeedmanAPIError.feedmanError(let context) {
            XCTAssertEqual(context.statusCode, 429)
            XCTAssertEqual(context.code, "FEED_COOLDOWN")
            XCTAssertEqual(context.retryAfter, "120")
            XCTAssertEqual(context.retryAfterSeconds, 120)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testMalformedErrorResponseSurfacesTypedFailure() async throws {
        let data = Data("not-json".utf8)
        let transport = MockAPITransport(
            data: data,
            response: httpResponse(url: apiURL("/api/feeds"), statusCode: 502)
        )
        let client = makeClient(baseURL: URL(string: "https://api.example.com")!, transport: transport)

        do {
            let _: ProbeResponse = try await client.send(ProbeResponse.self, path: "/api/feeds")
            XCTFail("Expected FeedmanAPIError.malformedErrorResponse")
        } catch FeedmanAPIError.malformedErrorResponse(let context) {
            XCTAssertEqual(context.statusCode, 502)
            XCTAssertEqual(context.body, data)
            XCTAssertTrue(context.underlyingError is DecodingError)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testNonHTTPResponseSurfacesTypedFailure() async throws {
        let response = URLResponse(
            url: apiURL("/api/items/cross-feed"),
            mimeType: "application/json",
            expectedContentLength: 0,
            textEncodingName: nil
        )
        let transport = MockAPITransport(data: successData(), response: response)
        let client = makeClient(baseURL: URL(string: "https://api.example.com")!, transport: transport)

        do {
            let _: ProbeResponse = try await client.send(ProbeResponse.self, path: "/api/items/cross-feed")
            XCTFail("Expected FeedmanAPIError.nonHTTPResponse")
        } catch FeedmanAPIError.nonHTTPResponse(let response) {
            XCTAssertEqual(response.url?.absoluteString, "https://api.example.com/api/items/cross-feed")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testTransportThrownErrorSurfacesUnderlyingError() async throws {
        let transport = MockAPITransport(error: URLError(.notConnectedToInternet))
        let client = makeClient(baseURL: URL(string: "https://api.example.com")!, transport: transport)

        do {
            let _: ProbeResponse = try await client.send(ProbeResponse.self, path: "/api/items/cross-feed")
            XCTFail("Expected FeedmanAPIError.transportFailed")
        } catch FeedmanAPIError.transportFailed(let underlyingError) {
            XCTAssertEqual((underlyingError as? URLError)?.code, .notConnectedToInternet)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testAuthenticated401RefreshesOnceAndRetriesWithNewBearerToken() async throws {
        let transport = MockAPITransport(
            results: [
                .success((feedmanErrorData(code: "ACCESS_TOKEN_EXPIRED"), httpResponse(url: apiURL("/api/me"), statusCode: 401))),
                .success((successData(), httpResponse(url: apiURL("/api/me"))))
            ]
        )
        let refreshHook = MockAccessTokenRefreshHook(result: .success("refreshed-access-token"))
        let client = makeClient(baseURL: URL(string: "https://api.example.com")!, transport: transport) {
            try await refreshHook.refresh()
        }

        let response = try await client.send(ProbeResponse.self, path: "/api/me", accessToken: "expired-access-token")

        XCTAssertEqual(response, ProbeResponse(ok: true))
        let refreshCallCount = await refreshHook.numberOfCalls()
        XCTAssertEqual(refreshCallCount, 1)
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

    func testAuthenticated401WithoutRefreshHookSurfacesAuthRequired() async throws {
        let transport = MockAPITransport(
            data: feedmanErrorData(code: "ACCESS_TOKEN_EXPIRED"),
            response: httpResponse(url: apiURL("/api/me"), statusCode: 401)
        )
        let client = makeClient(baseURL: URL(string: "https://api.example.com")!, transport: transport)

        do {
            let _: ProbeResponse = try await client.send(ProbeResponse.self, path: "/api/me", accessToken: "expired-access-token")
            XCTFail("Expected FeedmanAPIError.authRequired")
        } catch FeedmanAPIError.authRequired(let context) {
            XCTAssertEqual(context.reason, .missingRefreshHook)
            XCTAssertEqual(context.statusCode, 401)
            XCTAssertTrue(context.underlyingError is FeedmanAPIError)
            XCTAssertEqual(transport.requests.count, 1)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testRefreshFailureSurfacesAuthRequiredWithoutRetry() async throws {
        let transport = MockAPITransport(
            data: feedmanErrorData(code: "ACCESS_TOKEN_EXPIRED"),
            response: httpResponse(url: apiURL("/api/me"), statusCode: 401)
        )
        let refreshHook = MockAccessTokenRefreshHook(result: .failure(AuthRepositoryError.missingRefreshToken))
        let client = makeClient(baseURL: URL(string: "https://api.example.com")!, transport: transport) {
            try await refreshHook.refresh()
        }

        do {
            let _: ProbeResponse = try await client.send(ProbeResponse.self, path: "/api/me", accessToken: "expired-access-token")
            XCTFail("Expected FeedmanAPIError.authRequired")
        } catch FeedmanAPIError.authRequired(let context) {
            XCTAssertEqual(context.reason, .refreshFailed)
            XCTAssertEqual(context.statusCode, 401)
            XCTAssertTrue(context.underlyingError is AuthRepositoryError)
            let refreshCallCount = await refreshHook.numberOfCalls()
            XCTAssertEqual(refreshCallCount, 1)
            XCTAssertEqual(transport.requests.count, 1)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testRetried401SurfacesAuthRequiredWithoutSecondRefresh() async throws {
        let transport = MockAPITransport(
            results: [
                .success((feedmanErrorData(code: "ACCESS_TOKEN_EXPIRED"), httpResponse(url: apiURL("/api/me"), statusCode: 401))),
                .success((feedmanErrorData(code: "ACCESS_TOKEN_REJECTED"), httpResponse(url: apiURL("/api/me"), statusCode: 401)))
            ]
        )
        let refreshHook = MockAccessTokenRefreshHook(result: .success("refreshed-access-token"))
        let client = makeClient(baseURL: URL(string: "https://api.example.com")!, transport: transport) {
            try await refreshHook.refresh()
        }

        do {
            let _: ProbeResponse = try await client.send(ProbeResponse.self, path: "/api/me", accessToken: "expired-access-token")
            XCTFail("Expected FeedmanAPIError.authRequired")
        } catch FeedmanAPIError.authRequired(let context) {
            XCTAssertEqual(context.reason, .retryUnauthorized)
            XCTAssertEqual(context.statusCode, 401)
            XCTAssertTrue(context.underlyingError is FeedmanAPIError)
            let refreshCallCount = await refreshHook.numberOfCalls()
            XCTAssertEqual(refreshCallCount, 1)
            XCTAssertEqual(transport.requests.count, 2)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testUnauthenticated401DoesNotRefreshAndSurfacesFeedmanError() async throws {
        let transport = MockAPITransport(
            data: feedmanErrorData(code: "UNAUTHENTICATED"),
            response: httpResponse(url: apiURL("/api/auth/token"), statusCode: 401)
        )
        let refreshHook = MockAccessTokenRefreshHook(result: .success("unused-access-token"))
        let client = makeClient(baseURL: URL(string: "https://api.example.com")!, transport: transport) {
            try await refreshHook.refresh()
        }

        do {
            let _: ProbeResponse = try await client.send(ProbeResponse.self, path: "/api/auth/token")
            XCTFail("Expected FeedmanAPIError.feedmanError")
        } catch FeedmanAPIError.feedmanError(let context) {
            XCTAssertEqual(context.statusCode, 401)
            XCTAssertEqual(context.code, "UNAUTHENTICATED")
            let refreshCallCount = await refreshHook.numberOfCalls()
            XCTAssertEqual(refreshCallCount, 0)
            XCTAssertEqual(transport.requests.count, 1)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testAuthenticatedNon401ErrorDoesNotRefreshAndPreservesFeedmanError() async throws {
        let transport = MockAPITransport(
            data: feedmanErrorData(code: "FEED_COOLDOWN", category: "rate_limit", action: "retry_later"),
            response: httpResponse(url: apiURL("/api/feeds/feed-publickey/refresh"), statusCode: 429, headers: ["Retry-After": "120"])
        )
        let refreshHook = MockAccessTokenRefreshHook(result: .success("unused-access-token"))
        let client = makeClient(baseURL: URL(string: "https://api.example.com")!, transport: transport) {
            try await refreshHook.refresh()
        }

        do {
            let _: ProbeResponse = try await client.send(
                ProbeResponse.self,
                method: .post,
                path: "/api/feeds/feed-publickey/refresh",
                accessToken: "valid-access-token"
            )
            XCTFail("Expected FeedmanAPIError.feedmanError")
        } catch FeedmanAPIError.feedmanError(let context) {
            XCTAssertEqual(context.statusCode, 429)
            XCTAssertEqual(context.code, "FEED_COOLDOWN")
            XCTAssertEqual(context.retryAfter, "120")
            let refreshCallCount = await refreshHook.numberOfCalls()
            XCTAssertEqual(refreshCallCount, 0)
            XCTAssertEqual(transport.requests.count, 1)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testConcurrentAuthenticated401SharesInFlightRefresh() async throws {
        let transport = MockAPITransport(
            results: [
                .success((feedmanErrorData(code: "ACCESS_TOKEN_EXPIRED"), httpResponse(url: apiURL("/api/me"), statusCode: 401))),
                .success((feedmanErrorData(code: "ACCESS_TOKEN_EXPIRED"), httpResponse(url: apiURL("/api/me"), statusCode: 401))),
                .success((successData(), httpResponse(url: apiURL("/api/me")))),
                .success((successData(), httpResponse(url: apiURL("/api/me"))))
            ]
        )
        let refreshHook = ControlledAccessTokenRefreshHook()
        let client = makeClient(baseURL: URL(string: "https://api.example.com")!, transport: transport) {
            try await refreshHook.refresh()
        }

        let firstTask = Task {
            try await client.send(ProbeResponse.self, path: "/api/me", accessToken: "expired-access-token")
        }
        let secondTask = Task {
            try await client.send(ProbeResponse.self, path: "/api/me", accessToken: "expired-access-token")
        }

        let didStartSharedRefresh = try await waitUntil {
            let refreshCalls = await refreshHook.numberOfCalls()
            return transport.requests.count == 2 && refreshCalls == 1
        }
        if !didStartSharedRefresh {
            await refreshHook.succeed(with: "shared-refreshed-access-token")
            XCTFail("Timed out waiting for shared refresh")
            return
        }

        await refreshHook.succeed(with: "shared-refreshed-access-token")

        let firstResponse = try await firstTask.value
        let secondResponse = try await secondTask.value

        XCTAssertEqual(firstResponse, ProbeResponse(ok: true))
        XCTAssertEqual(secondResponse, ProbeResponse(ok: true))
        let refreshCallCount = await refreshHook.numberOfCalls()
        XCTAssertEqual(refreshCallCount, 1)
        XCTAssertEqual(transport.requests.count, 4)
        XCTAssertEqual(
            transport.requests.suffix(2).map { $0.value(forHTTPHeaderField: "Authorization") },
            ["Bearer shared-refreshed-access-token", "Bearer shared-refreshed-access-token"]
        )
    }

    private func makeClient(
        baseURL: URL,
        transport: APITransport,
        accessTokenRefreshHook: APIClient.AccessTokenRefreshHook? = nil
    ) -> APIClient {
        APIClient(baseURL: baseURL, transport: transport, accessTokenRefreshHook: accessTokenRefreshHook)
    }

    private func apiURL(_ path: String) -> URL {
        URL(string: "https://api.example.com\(path)")!
    }

    private func successData() -> Data {
        Data(#"{"ok":true}"#.utf8)
    }

    private func feedmanErrorData(
        code: String,
        category: String = "auth",
        action: String = "login"
    ) -> Data {
        Data(
            """
            {
              "error": {
                "code": "\(code)",
                "message": "Authentication is required.",
                "category": "\(category)",
                "action": "\(action)"
              }
            }
            """.utf8
        )
    }

    private func waitUntil(
        timeoutNanoseconds: UInt64 = 1_000_000_000,
        condition: @escaping () async -> Bool
    ) async throws -> Bool {
        let start = DispatchTime.now().uptimeNanoseconds

        while DispatchTime.now().uptimeNanoseconds - start < timeoutNanoseconds {
            if await condition() {
                return true
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        return false
    }

    private func httpResponse(
        url: URL,
        statusCode: Int = 200,
        headers: [String: String]? = nil
    ) -> HTTPURLResponse {
        HTTPURLResponse(
            url: url,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: headers
        )!
    }
}

private final class MockAPITransport: APITransport {
    private let queue = DispatchQueue(label: "MockAPITransport")
    private var results: [Result<(Data, URLResponse), Error>]
    private var storedRequests: [URLRequest] = []

    var requests: [URLRequest] {
        queue.sync {
            storedRequests
        }
    }

    init(data: Data, response: URLResponse) {
        self.results = [.success((data, response))]
    }

    init(error: Error) {
        self.results = [.failure(error)]
    }

    init(results: [Result<(Data, URLResponse), Error>]) {
        self.results = results
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        let result: Result<(Data, URLResponse), Error> = queue.sync {
            storedRequests.append(request)
            if results.count > 1 {
                return results.removeFirst()
            } else {
                return results[0]
            }
        }

        return try result.get()
    }
}

private actor MockAccessTokenRefreshHook {
    enum RefreshResult {
        case success(String)
        case failure(Error)
    }

    private let result: RefreshResult
    private var callCount = 0

    init(result: RefreshResult) {
        self.result = result
    }

    func refresh() async throws -> String {
        callCount += 1

        switch result {
        case .success(let accessToken):
            return accessToken
        case .failure(let error):
            throw error
        }
    }

    func numberOfCalls() -> Int {
        callCount
    }
}

private actor ControlledAccessTokenRefreshHook {
    private var callCount = 0
    private var continuation: CheckedContinuation<String, Error>?

    func refresh() async throws -> String {
        callCount += 1

        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
        }
    }

    func succeed(with accessToken: String) {
        continuation?.resume(returning: accessToken)
        continuation = nil
    }

    func numberOfCalls() -> Int {
        callCount
    }
}

private struct ProbeResponse: Decodable, Equatable {
    let ok: Bool
}

private struct ProbeRequest: Encodable {
    let url: String
}
