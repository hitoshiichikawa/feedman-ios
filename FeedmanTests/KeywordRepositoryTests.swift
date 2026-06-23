import XCTest
@testable import Feedman

final class KeywordRepositoryTests: XCTestCase {
    private let baseURL = URL(string: "https://api.example.com")!

    func testKeywordResponseDecodesCanonicalFieldsAndUnknownScope() throws {
        let response = try JSONDecoder().decode(
            KeywordResponse.self,
            from: Data(
                """
                {
                  "id": "keyword-1",
                  "term": "SwiftUI",
                  "scope": "summary",
                  "enabled": true,
                  "hits": 7
                }
                """.utf8
            )
        )

        XCTAssertEqual(response.id, "keyword-1")
        XCTAssertEqual(response.term, "SwiftUI")
        XCTAssertEqual(response.scope, "summary")
        XCTAssertTrue(response.enabled)
        XCTAssertEqual(response.hits, 7)
    }

    func testKeywordCreateRequestEncodesTitleScopeAndEnabled() throws {
        let request = KeywordCreateRequest(term: "SwiftUI", enabled: true)
        let data = try JSONEncoder().encode(request)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(json["term"] as? String, "SwiftUI")
        XCTAssertEqual(json["scope"] as? String, "title")
        XCTAssertEqual(json["enabled"] as? Bool, true)
    }

    func testKeywordUpdateRequestEncodesOnlyMutableNonNilFields() throws {
        let termData = try JSONEncoder().encode(KeywordUpdateRequest(term: "Swift", enabled: nil))
        let termJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: termData) as? [String: Any])
        XCTAssertEqual(termJSON.keys.sorted(), ["term"])
        XCTAssertEqual(termJSON["term"] as? String, "Swift")

        let enabledData = try JSONEncoder().encode(KeywordUpdateRequest(term: nil, enabled: false))
        let enabledJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: enabledData) as? [String: Any])
        XCTAssertEqual(enabledJSON.keys.sorted(), ["enabled"])
        XCTAssertEqual(enabledJSON["enabled"] as? Bool, false)
    }

    func testKeywordsGetsBareArrayWithBearer() async throws {
        let transport = KeywordRecordingTransport()
        transport.enqueueSuccess(data: keywordListData())
        let repository = APIClientKeywordRepository(apiClient: APIClient(baseURL: baseURL, transport: transport))

        let keywords = try await repository.keywords(accessToken: "access-1")

        XCTAssertEqual(keywords.map(\.id), ["keyword-1", "keyword-2"])
        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.url?.path, "/api/keywords")
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer access-1")
        XCTAssertNil(request.httpBody)
    }

    func testKeywordsAcceptsWrappedItemsResponseAtRepositoryBoundary() async throws {
        let transport = KeywordRecordingTransport()
        transport.enqueueSuccess(
            data: Data(#"{"items":[{"id":"keyword-1","term":"SwiftUI","scope":"title","enabled":true,"hits":3}]}"#.utf8)
        )
        let repository = APIClientKeywordRepository(apiClient: APIClient(baseURL: baseURL, transport: transport))

        let keywords = try await repository.keywords(accessToken: "access-1")

        XCTAssertEqual(keywords, [KeywordResponse(id: "keyword-1", term: "SwiftUI", scope: "title", enabled: true, hits: 3)])
    }

    func testCreateKeywordPostsRequestBodyWithBearer() async throws {
        let transport = KeywordRecordingTransport()
        transport.enqueueSuccess(data: keywordData(id: "keyword-3", term: "Combine", enabled: true, hits: 0))
        let repository = APIClientKeywordRepository(apiClient: APIClient(baseURL: baseURL, transport: transport))

        let keyword = try await repository.createKeyword(
            KeywordCreateRequest(term: "Combine", enabled: true),
            accessToken: "access-1"
        )

        XCTAssertEqual(keyword.id, "keyword-3")
        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.url?.path, "/api/keywords")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer access-1")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        let json = try bodyJSON(from: request)
        XCTAssertEqual(json["term"] as? String, "Combine")
        XCTAssertEqual(json["scope"] as? String, "title")
        XCTAssertEqual(json["enabled"] as? Bool, true)
    }

    func testUpdateKeywordPatchesOnlyEditedTermWithBearer() async throws {
        let transport = KeywordRecordingTransport()
        transport.enqueueSuccess(data: keywordData(id: "keyword-1", term: "Swift", enabled: true, hits: 4))
        let repository = APIClientKeywordRepository(apiClient: APIClient(baseURL: baseURL, transport: transport))

        let keyword = try await repository.updateKeyword(
            id: "keyword-1",
            request: KeywordUpdateRequest(term: "Swift", enabled: nil),
            accessToken: "access-1"
        )

        XCTAssertEqual(keyword.term, "Swift")
        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.url?.path, "/api/keywords/keyword-1")
        XCTAssertEqual(request.httpMethod, "PATCH")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer access-1")
        let json = try bodyJSON(from: request)
        XCTAssertEqual(json.keys.sorted(), ["term"])
        XCTAssertEqual(json["term"] as? String, "Swift")
    }

    func testToggleKeywordPatchesOnlyEditedEnabledWithBearer() async throws {
        let transport = KeywordRecordingTransport()
        transport.enqueueSuccess(data: keywordData(id: "keyword-1", term: "SwiftUI", enabled: false, hits: 4))
        let repository = APIClientKeywordRepository(apiClient: APIClient(baseURL: baseURL, transport: transport))

        let keyword = try await repository.updateKeyword(
            id: "keyword-1",
            request: KeywordUpdateRequest(term: nil, enabled: false),
            accessToken: "access-1"
        )

        XCTAssertFalse(keyword.enabled)
        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.url?.path, "/api/keywords/keyword-1")
        XCTAssertEqual(request.httpMethod, "PATCH")
        let json = try bodyJSON(from: request)
        XCTAssertEqual(json.keys.sorted(), ["enabled"])
        XCTAssertEqual(json["enabled"] as? Bool, false)
    }

    func testDeleteKeywordDeletesWithBearer() async throws {
        let transport = KeywordRecordingTransport()
        transport.enqueueSuccess(data: Data(), statusCode: 204)
        let repository = APIClientKeywordRepository(apiClient: APIClient(baseURL: baseURL, transport: transport))

        try await repository.deleteKeyword(id: "keyword-1", accessToken: "access-1")

        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.url?.path, "/api/keywords/keyword-1")
        XCTAssertEqual(request.httpMethod, "DELETE")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer access-1")
        XCTAssertNil(request.httpBody)
    }

    func testKeywordRepositoryDelegatesExpiredTokenRefreshToAPIClient() async throws {
        let transport = KeywordRecordingTransport()
        transport.enqueueFeedmanError(statusCode: 401, code: "ACCESS_TOKEN_EXPIRED", category: "auth")
        transport.enqueueSuccess(data: keywordListData())
        let refreshHook = KeywordRefreshHook(accessToken: "access-2")
        let repository = APIClientKeywordRepository(
            apiClient: APIClient(
                baseURL: baseURL,
                transport: transport,
                accessTokenRefreshHook: {
                    await refreshHook.refresh()
                }
            )
        )

        let keywords = try await repository.keywords(accessToken: "access-1")

        XCTAssertEqual(keywords.count, 2)
        let refreshCallCount = await refreshHook.callCount
        XCTAssertEqual(refreshCallCount, 1)
        XCTAssertEqual(
            transport.requests.map { $0.value(forHTTPHeaderField: "Authorization") },
            ["Bearer access-1", "Bearer access-2"]
        )
    }

    func testKeywordRepositoryPreservesFeedmanAPIErrorContext() async throws {
        let transport = KeywordRecordingTransport()
        transport.enqueueFeedmanError(statusCode: 409, code: "DUPLICATE_KEYWORD", category: "conflict")
        let repository = APIClientKeywordRepository(apiClient: APIClient(baseURL: baseURL, transport: transport))

        do {
            _ = try await repository.createKeyword(KeywordCreateRequest(term: "Swift", enabled: true), accessToken: "access-1")
            XCTFail("Expected FeedmanAPIError.feedmanError")
        } catch FeedmanAPIError.feedmanError(let context) {
            XCTAssertEqual(context.statusCode, 409)
            XCTAssertEqual(context.code, "DUPLICATE_KEYWORD")
            XCTAssertEqual(context.category, "conflict")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testDisabledKeywordRepositoryFailsWithoutNetworkDependency() async throws {
        let repository = DisabledKeywordRepository()

        do {
            _ = try await repository.keywords(accessToken: "access-1")
            XCTFail("Expected keyword notifications disabled error")
        } catch KeywordRepositoryError.keywordNotificationsDisabled {
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testMockKeywordRepositoryMutatesDeterministically() async throws {
        let repository = MockKeywordRepository(keywords: [
            KeywordResponse(id: "keyword-1", term: "SwiftUI", scope: "title", enabled: true, hits: 3)
        ])

        let created = try await repository.createKeyword(KeywordCreateRequest(term: "Combine", enabled: true), accessToken: "access-1")
        let toggled = try await repository.updateKeyword(
            id: created.id,
            request: KeywordUpdateRequest(term: nil, enabled: false),
            accessToken: "access-1"
        )
        try await repository.deleteKeyword(id: "keyword-1", accessToken: "access-1")
        let keywords = try await repository.keywords(accessToken: "access-1")

        XCTAssertEqual(created.term, "Combine")
        XCTAssertFalse(toggled.enabled)
        XCTAssertEqual(keywords, [toggled])
        XCTAssertEqual(repository.recordedOperations.count, 4)
    }

    private func keywordListData() -> Data {
        Data(
            """
            [
              {"id":"keyword-1","term":"SwiftUI","scope":"title","enabled":true,"hits":3},
              {"id":"keyword-2","term":"iOS","scope":"title","enabled":false,"hits":0}
            ]
            """.utf8
        )
    }

    private func keywordData(id: String, term: String, enabled: Bool, hits: Int) -> Data {
        Data(
            """
            {"id":"\(id)","term":"\(term)","scope":"title","enabled":\(enabled),"hits":\(hits)}
            """.utf8
        )
    }

    private func bodyJSON(from request: URLRequest) throws -> [String: Any] {
        let body = try XCTUnwrap(request.httpBody)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
    }
}

private final class KeywordRecordingTransport: APITransport, @unchecked Sendable {
    private enum Result {
        case success(Data, Int)
        case feedmanError(statusCode: Int, code: String, category: String)
    }

    private(set) var requests: [URLRequest] = []
    private var results: [Result] = []

    func enqueueSuccess(data: Data, statusCode: Int = 200) {
        results.append(.success(data, statusCode))
    }

    func enqueueFeedmanError(statusCode: Int, code: String, category: String) {
        results.append(.feedmanError(statusCode: statusCode, code: code, category: category))
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        requests.append(request)
        guard !results.isEmpty else {
            throw URLError(.badServerResponse)
        }

        switch results.removeFirst() {
        case let .success(data, statusCode):
            return (data, httpResponse(statusCode: statusCode, request: request))
        case let .feedmanError(statusCode, code, category):
            let data = Data(
                """
                {
                  "error": {
                    "code": "\(code)",
                    "message": "Keyword operation failed.",
                    "category": "\(category)",
                    "action": "fix_request"
                  }
                }
                """.utf8
            )
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

private actor KeywordRefreshHook {
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
