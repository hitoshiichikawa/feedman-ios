import Foundation

enum SearchScope: Equatable {
    case global
    case feed(id: String)
}

protocol SearchRepository {
    func searchItemsPage(
        query: String,
        scope: SearchScope,
        cursor: String?,
        limit: Int?
    ) async throws -> SearchItemsResponse
}

extension SearchRepository {
    func searchItems(query: String, scope: SearchScope) async throws -> [ItemSearchHit] {
        try await searchItemsPage(
            query: query,
            scope: scope,
            cursor: nil,
            limit: nil
        ).items
    }
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

    func searchItemsPage(
        query: String,
        scope: SearchScope,
        cursor: String?,
        limit: Int?
    ) async throws -> SearchItemsResponse {
        switch scope {
        case .global:
            return try await searchItemsPage(query: query, feedID: nil, cursor: cursor, limit: limit)
        case .feed(let feedID):
            return try await searchItemsPage(query: query, feedID: feedID, cursor: cursor, limit: limit)
        }
    }

    func searchItemsPage(
        query: String,
        cursor: String? = nil,
        limit: Int? = nil
    ) async throws -> SearchItemsResponse {
        try await searchItemsPage(query: query, scope: .global, cursor: cursor, limit: limit)
    }

    func searchItemsPage(
        query: String,
        feedID: String?,
        cursor: String? = nil,
        limit: Int? = nil
    ) async throws -> SearchItemsResponse {
        let normalizedLimit = CrossFeedPageLimit.normalized(limit)
        var queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "limit", value: String(normalizedLimit))
        ]

        if let cursor {
            queryItems.append(URLQueryItem(name: "cursor", value: cursor))
        }

        if let feedID {
            queryItems.append(URLQueryItem(name: "feed_id", value: feedID))
        }

        return try await apiClient.send(
            SearchItemsResponse.self,
            path: "/api/items/search",
            queryItems: queryItems,
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
        defaultResponse: MockSearchRepositoryResponse = .success(MockSearchRepository.defaultHits)
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
        try await searchItemsPage(query: query, scope: scope, cursor: nil, limit: nil).items
    }

    func searchItemsPage(
        query: String,
        scope: SearchScope,
        cursor: String?,
        limit: Int?
    ) async throws -> SearchItemsResponse {
        calls.append(MockSearchRepositoryCall(query: query, scope: scope))

        switch responsesByQuery[query] ?? defaultResponse {
        case .success(let hits):
            return SearchItemsResponse(items: hits, nextCursor: nil, hasMore: false)
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
