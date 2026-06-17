import XCTest
@testable import Feedman

final class AccountRepositoryTests: XCTestCase {
    private let baseURL = URL(string: "https://api.example.com")!

    func testCurrentUserRequestsAuthMeWithBearerToken() async throws {
        let transport = AccountRecordingTransport()
        transport.enqueue(data: currentUserData(name: "You", email: "you@example.com"), statusCode: 200)
        let repository = FeedmanAccountRepository(
            apiClient: APIClient(baseURL: baseURL, transport: transport)
        )

        let user = try await repository.currentUser(accessToken: "access-1")

        XCTAssertEqual(user.id, "user-1")
        XCTAssertEqual(user.name, "You")
        XCTAssertEqual(user.email, "you@example.com")

        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.url?.path, "/auth/me")
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer access-1")
        XCTAssertNil(request.httpBody)
    }

    func testCurrentUserDelegatesExpiredTokenRefreshToAPIClient() async throws {
        let transport = AccountRecordingTransport()
        transport.enqueue(data: feedmanErrorData(code: "ACCESS_TOKEN_EXPIRED"), statusCode: 401)
        transport.enqueue(data: currentUserData(name: "You", email: "you@example.com"), statusCode: 200)
        let refreshHook = AccountRefreshHook(accessToken: "access-2")
        let repository = FeedmanAccountRepository(
            apiClient: APIClient(
                baseURL: baseURL,
                transport: transport,
                accessTokenRefreshHook: {
                    await refreshHook.refresh()
                }
            )
        )

        let user = try await repository.currentUser(accessToken: "access-1")

        XCTAssertEqual(user.email, "you@example.com")
        let awaitedCallCount1 = await refreshHook.callCount
        XCTAssertEqual(awaitedCallCount1, 1)
        XCTAssertEqual(transport.requests.count, 2)
        XCTAssertEqual(
            transport.requests.first?.value(forHTTPHeaderField: "Authorization"),
            "Bearer access-1"
        )
        XCTAssertEqual(
            transport.requests.last?.value(forHTTPHeaderField: "Authorization"),
            "Bearer access-2"
        )
    }

    func testDeleteCurrentUserRequestsUsersMeWithBearerToken() async throws {
        let transport = AccountRecordingTransport()
        transport.enqueue(data: Data(), statusCode: 204)
        let repository = FeedmanAccountRepository(
            apiClient: APIClient(baseURL: baseURL, transport: transport)
        )

        try await repository.deleteCurrentUser(accessToken: "access-1")

        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.url?.path, "/api/users/me")
        XCTAssertEqual(request.httpMethod, "DELETE")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer access-1")
        XCTAssertNil(request.httpBody)
    }

    func testDeleteCurrentUserTreatsAnyTwoHundredResponseAsSuccess() async throws {
        let transport = AccountRecordingTransport()
        transport.enqueue(data: Data(#"{"ok":true}"#.utf8), statusCode: 200)
        let repository = FeedmanAccountRepository(
            apiClient: APIClient(baseURL: baseURL, transport: transport)
        )

        try await repository.deleteCurrentUser(accessToken: "access-1")

        XCTAssertEqual(transport.requests.count, 1)
    }

    func testUserResponseDecodesAuthMeContractFields() throws {
        let data = currentUserData(name: nil, email: nil, avatarURL: "https://example.com/avatar.png")

        let response = try JSONDecoder().decode(UserResponse.self, from: data)

        XCTAssertEqual(response.id, "user-1")
        XCTAssertNil(response.email)
        XCTAssertNil(response.name)
        XCTAssertEqual(response.avatarURL, "https://example.com/avatar.png")
    }

    private func currentUserData(
        name: String?,
        email: String?,
        avatarURL: String? = nil
    ) -> Data {
        var fields = [
            #""id": "user-1""#
        ]
        if let email {
            fields.append(#""email": "\#(email)""#)
        }
        if let name {
            fields.append(#""name": "\#(name)""#)
        } else {
            fields.append(#""name": null"#)
        }
        if let avatarURL {
            fields.append(#""avatar_url": "\#(avatarURL)""#)
        } else {
            fields.append(#""avatar_url": null"#)
        }
        return Data("{\(fields.joined(separator: ","))}".utf8)
    }

    private func feedmanErrorData(code: String) -> Data {
        Data(
            """
            {
              "error": {
                "code": "\(code)",
                "message": "Authentication is required.",
                "category": "auth",
                "action": "login"
              }
            }
            """.utf8
        )
    }
}

private final class AccountRecordingTransport: APITransport, @unchecked Sendable {
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

private actor AccountRefreshHook {
    private let accessToken: String
    private(set) var callCount = 0

    init(accessToken: String) {
        self.accessToken = accessToken
    }

    func refresh() -> String {
        callCount += 1
        return accessToken
    }
}
