import XCTest
@testable import Feedman

final class AuthRepositoryTests: XCTestCase {
    private let baseURL = URL(string: "https://api.example.com")!

    private func makeRepository(
        transport: RecordingTransport,
        tokenStore: InMemoryTokenStore
    ) -> FeedmanAuthRepository {
        FeedmanAuthRepository(
            apiClient: APIClient(baseURL: baseURL, transport: transport),
            tokenStore: tokenStore
        )
    }

    private func tokenResponseData(refreshToken: String) -> Data {
        Data("""
        {
            "access_token": "jwt-access",
            "refresh_token": "\(refreshToken)",
            "token_type": "Bearer",
            "expires_in": 900
        }
        """.utf8)
    }

    private func feedmanErrorData(code: String) -> Data {
        Data("""
        {
            "error": {
                "code": "\(code)",
                "message": "rejected",
                "category": "auth",
                "action": "reauthenticate"
            }
        }
        """.utf8)
    }

    private func httpResponse(_ statusCode: Int, url: URL) -> HTTPURLResponse {
        HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: nil, headerFields: nil)!
    }

    func testExchangeSuccessSendsContractBodyAndStoresRefreshToken() async throws {
        let transport = RecordingTransport()
        let tokenStore = InMemoryTokenStore()
        transport.enqueue(data: tokenResponseData(refreshToken: "opaque-1"), statusCode: 200)
        let repository = makeRepository(transport: transport, tokenStore: tokenStore)

        let credentials = try await repository.exchangeAuthCode("code-1", codeVerifier: "verifier-1")

        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.url?.path, "/api/auth/token")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
        let body = try XCTUnwrap(request.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: String])
        XCTAssertEqual(json, ["auth_code": "code-1", "code_verifier": "verifier-1"])
        XCTAssertEqual(tokenStore.savedTokens, ["opaque-1"])
        XCTAssertEqual(credentials.accessToken, "jwt-access")
        XCTAssertEqual(credentials.expiresIn, 900)
    }

    func testExchangeFailureSurfacesTypedErrorWithoutStoring() async {
        let transport = RecordingTransport()
        let tokenStore = InMemoryTokenStore()
        transport.enqueue(data: feedmanErrorData(code: "INVALID_GRANT"), statusCode: 400)
        let repository = makeRepository(transport: transport, tokenStore: tokenStore)

        do {
            _ = try await repository.exchangeAuthCode("code-1", codeVerifier: "verifier-1")
            XCTFail("Expected FeedmanAPIError.feedmanError")
        } catch let FeedmanAPIError.feedmanError(context) {
            XCTAssertEqual(context.statusCode, 400)
            XCTAssertEqual(context.code, "INVALID_GRANT")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        XCTAssertTrue(tokenStore.savedTokens.isEmpty)
        XCTAssertEqual(tokenStore.clearCallCount, 0)
    }

    func testRefreshSendsStoredTokenAndStoresRotatedReplacement() async throws {
        let transport = RecordingTransport()
        let tokenStore = InMemoryTokenStore(storedToken: "opaque-old")
        transport.enqueue(data: tokenResponseData(refreshToken: "opaque-new"), statusCode: 200)
        let repository = makeRepository(transport: transport, tokenStore: tokenStore)

        let credentials = try await repository.refreshTokens()

        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.url?.path, "/api/auth/refresh")
        let body = try XCTUnwrap(request.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: String])
        XCTAssertEqual(json, ["refresh_token": "opaque-old"])
        XCTAssertEqual(tokenStore.savedTokens, ["opaque-new"])
        XCTAssertEqual(try tokenStore.loadRefreshToken(), "opaque-new")
        XCTAssertEqual(credentials.refreshToken, "opaque-new")
    }

    func testRefreshWithoutStoredTokenFailsWithoutRequest() async {
        let transport = RecordingTransport()
        let tokenStore = InMemoryTokenStore()
        let repository = makeRepository(transport: transport, tokenStore: tokenStore)

        do {
            _ = try await repository.refreshTokens()
            XCTFail("Expected AuthRepositoryError.missingRefreshToken")
        } catch let error as AuthRepositoryError {
            XCTAssertEqual(error, .missingRefreshToken)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        XCTAssertTrue(transport.requests.isEmpty)
    }

    func testRefreshRejectionLeavesStoredTokenUntouched() async {
        let transport = RecordingTransport()
        let tokenStore = InMemoryTokenStore(storedToken: "opaque-old")
        transport.enqueue(data: feedmanErrorData(code: "INVALID_REFRESH_TOKEN"), statusCode: 401)
        let repository = makeRepository(transport: transport, tokenStore: tokenStore)

        do {
            _ = try await repository.refreshTokens()
            XCTFail("Expected FeedmanAPIError.feedmanError")
        } catch let FeedmanAPIError.feedmanError(context) {
            XCTAssertEqual(context.statusCode, 401)
            XCTAssertEqual(context.code, "INVALID_REFRESH_TOKEN")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        XCTAssertTrue(tokenStore.savedTokens.isEmpty)
        XCTAssertEqual(try? tokenStore.loadRefreshToken(), "opaque-old")
        XCTAssertEqual(tokenStore.clearCallCount, 0)
    }

    func testRevokeSendsBearerAndClearsCredentialsOnNoContent() async throws {
        let transport = RecordingTransport()
        let tokenStore = InMemoryTokenStore(storedToken: "opaque-old")
        transport.enqueue(data: Data(), statusCode: 204)
        let repository = makeRepository(transport: transport, tokenStore: tokenStore)

        try await repository.revokeAndClearCredentials(accessToken: "jwt-access")

        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.url?.path, "/api/auth/revoke")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer jwt-access")
        let body = try XCTUnwrap(request.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: String])
        XCTAssertEqual(json, ["refresh_token": "opaque-old"])
        XCTAssertEqual(tokenStore.clearCallCount, 1)
        XCTAssertNil(try tokenStore.loadRefreshToken())
    }

    func testRevokeFailureKeepsLocalCredentials() async {
        let transport = RecordingTransport()
        let tokenStore = InMemoryTokenStore(storedToken: "opaque-old")
        transport.enqueue(data: feedmanErrorData(code: "INTERNAL"), statusCode: 500)
        let repository = makeRepository(transport: transport, tokenStore: tokenStore)

        do {
            try await repository.revokeAndClearCredentials(accessToken: "jwt-access")
            XCTFail("Expected FeedmanAPIError.feedmanError")
        } catch let FeedmanAPIError.feedmanError(context) {
            XCTAssertEqual(context.statusCode, 500)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        XCTAssertEqual(tokenStore.clearCallCount, 0)
        XCTAssertEqual(try? tokenStore.loadRefreshToken(), "opaque-old")
    }

    func testRevokeWithoutStoredTokenClearsLocallyWithoutRequest() async throws {
        let transport = RecordingTransport()
        let tokenStore = InMemoryTokenStore()
        let repository = makeRepository(transport: transport, tokenStore: tokenStore)

        try await repository.revokeAndClearCredentials(accessToken: "jwt-access")

        XCTAssertTrue(transport.requests.isEmpty)
        XCTAssertEqual(tokenStore.clearCallCount, 1)
    }
}

private final class RecordingTransport: APITransport, @unchecked Sendable {
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

private final class InMemoryTokenStore: TokenStore {
    private(set) var storedToken: String?
    private(set) var savedTokens: [String] = []
    private(set) var clearCallCount = 0

    init(storedToken: String? = nil) {
        self.storedToken = storedToken
    }

    func saveRefreshToken(_ token: String) throws {
        savedTokens.append(token)
        storedToken = token
    }

    func loadRefreshToken() throws -> String? {
        storedToken
    }

    func clearCredentials() throws {
        clearCallCount += 1
        storedToken = nil
    }
}
