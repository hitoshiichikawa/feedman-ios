import XCTest
@testable import Feedman

final class SearchRepositoryTests: XCTestCase {
    private let baseURL = URL(string: "https://api.example.com")!

    func testGlobalSearchRequestsEndpointWithQueryScopeAndBearerToken() async throws {
        let transport = RecordingSearchTransport()
        transport.enqueue(hits: [
            hit(id: "hit-1"),
            hit(id: "hit-2")
        ])
        let repository = makeRepository(transport: transport)

        let hits = try await repository.searchItems(
            query: "SwiftUI | 日本語 next page",
            scope: .global
        )

        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.url?.path, "/api/items/search")
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer access-token")
        XCTAssertEqual(queryValue("q", in: request), "SwiftUI | 日本語 next page")
        XCTAssertEqual(queryValue("scope", in: request), "global")
        XCTAssertFalse(try XCTUnwrap(request.url?.absoluteString).contains(" "))
        XCTAssertTrue(try XCTUnwrap(request.url?.absoluteString).contains("%7C"))
        XCTAssertEqual(hits.map(\.id), ["hit-1", "hit-2"])
    }

    func testAuthRequiredErrorPropagatesWithoutEmptyResult() async {
        let transport = RecordingSearchTransport()
        transport.enqueueErrorResponse(statusCode: 401, code: "ACCESS_TOKEN_EXPIRED")
        let repository = makeRepository(transport: transport)

        do {
            _ = try await repository.searchItems(query: "Swift", scope: .global)
            XCTFail("Expected FeedmanAPIError.authRequired")
        } catch FeedmanAPIError.authRequired(let context) {
            XCTAssertEqual(context.reason, .missingRefreshHook)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    private func makeRepository(transport: RecordingSearchTransport) -> APIClientSearchRepository {
        APIClientSearchRepository(
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

    private func hit(id: String) -> ItemSearchHit {
        ItemSearchHit(
            id: id,
            feedID: "feed-\(id)",
            feedTitle: "Feed \(id)",
            faviconURL: nil,
            title: "Title \(id)",
            summary: "Summary \(id)",
            link: "https://example.com/\(id)",
            publishedAt: "2026-06-08T08:30:00Z",
            isDateEstimated: false,
            isRead: false,
            isStarred: false,
            hatebuCount: nil,
            author: nil
        )
    }
}

private final class RecordingSearchTransport: APITransport, @unchecked Sendable {
    private enum Result {
        case response([ItemSearchHit])
        case errorResponse(statusCode: Int, code: String)
    }

    private(set) var requests: [URLRequest] = []
    private var results: [Result] = []
    private let encoder = JSONEncoder()

    func enqueue(hits: [ItemSearchHit]) {
        results.append(.response(hits))
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
        case .response(let hits):
            return (try encoder.encode(hits), httpResponse(statusCode: 200, request: request))
        case let .errorResponse(statusCode, code):
            let data = Data("""
            {
              "error": {
                "code": "\(code)",
                "message": "rejected",
                "category": "auth",
                "action": "login"
              }
            }
            """.utf8)
            return (data, httpResponse(statusCode: statusCode, request: request))
        }
    }

    private func httpResponse(statusCode: Int, request: URLRequest) -> HTTPURLResponse {
        HTTPURLResponse(
            url: request.url!,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
    }
}
