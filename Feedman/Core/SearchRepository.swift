import Foundation

enum SearchScope: String, Equatable {
    case global
    case feed
}

protocol SearchRepository {
    func searchItems(query: String, scope: SearchScope) async throws -> [ItemSearchHit]
}

actor APIClientSearchRepository: SearchRepository {
    typealias AccessTokenProvider = @Sendable () async throws -> String

    private let apiClient: APIClient
    private let accessTokenProvider: AccessTokenProvider

    init(
        apiClient: APIClient,
        accessTokenProvider: @escaping AccessTokenProvider
    ) {
        self.apiClient = apiClient
        self.accessTokenProvider = accessTokenProvider
    }

    func searchItems(query: String, scope: SearchScope) async throws -> [ItemSearchHit] {
        try await apiClient.send(
            [ItemSearchHit].self,
            path: "/api/items/search",
            queryItems: [
                URLQueryItem(name: "q", value: query),
                URLQueryItem(name: "scope", value: scope.rawValue)
            ],
            accessToken: try await accessTokenProvider()
        )
    }
}

enum MockSearchRepositoryResponse {
    case success([ItemSearchHit])
    case failure(Error)
}

struct MockSearchRepositoryCall: Equatable {
    let query: String
    let scope: SearchScope
}

actor MockSearchRepository: SearchRepository {
    private(set) var calls: [MockSearchRepositoryCall] = []
    private var responsesByQuery: [String: MockSearchRepositoryResponse]
    private var defaultResponse: MockSearchRepositoryResponse

    init(
        responsesByQuery: [String: MockSearchRepositoryResponse] = [:],
        defaultResponse: MockSearchRepositoryResponse = .success(Self.defaultHits)
    ) {
        self.responsesByQuery = responsesByQuery
        self.defaultResponse = defaultResponse
    }

    func setResponse(_ response: MockSearchRepositoryResponse, for query: String) {
        responsesByQuery[query] = response
    }

    func setDefaultResponse(_ response: MockSearchRepositoryResponse) {
        defaultResponse = response
    }

    func searchItems(query: String, scope: SearchScope) async throws -> [ItemSearchHit] {
        calls.append(MockSearchRepositoryCall(query: query, scope: scope))

        switch responsesByQuery[query] ?? defaultResponse {
        case .success(let hits):
            return hits
        case .failure(let error):
            throw error
        }
    }
}

extension MockSearchRepository {
    static let defaultHits = [
        ItemSearchHit(
            id: "search-1",
            feedID: "publickey",
            feedTitle: "Publickey",
            faviconURL: nil,
            title: "SwiftUI の検索 UI を実装する",
            summary: "横断検索の入力、結果、空状態を SwiftUI で整理する。",
            link: "https://example.com/search-1",
            publishedAt: "2026-06-08T08:30:00Z",
            isDateEstimated: false,
            isRead: false,
            isStarred: false,
            hatebuCount: 42,
            author: nil
        ),
        ItemSearchHit(
            id: "search-2",
            feedID: "zenn",
            feedTitle: "Zenn トレンド",
            faviconURL: nil,
            title: "Repository 境界で API を扱う",
            summary: "ViewModel から URLSession と Bearer token を隠蔽する設計メモ。",
            link: "https://example.com/search-2",
            publishedAt: nil,
            isDateEstimated: nil,
            isRead: false,
            isStarred: true,
            hatebuCount: nil,
            author: "Feedman"
        )
    ]
}
