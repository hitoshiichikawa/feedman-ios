import Foundation

protocol FeedRepository {
    func subscriptions() async throws -> [Feed]
    func crossFeedItems() async throws -> [FeedItem]
    func loadCrossFeedFirstPage(limit: Int?) async throws -> CrossFeedPaginationSnapshot
    func loadCrossFeedNextPage() async throws -> CrossFeedPaginationSnapshot
}

protocol ItemRepository {
    func itemDetail(id: String, accessToken: String) async throws -> ItemDetail
    func updateItemState(
        id: String,
        request: ItemStateUpdateRequest,
        accessToken: String
    ) async throws
}

struct FeedmanItemRepository: ItemRepository {
    let apiClient: APIClient

    func itemDetail(id: String, accessToken: String) async throws -> ItemDetail {
        try await apiClient.send(
            ItemDetail.self,
            path: "/api/items/\(id)",
            accessToken: accessToken
        )
    }

    func updateItemState(
        id: String,
        request: ItemStateUpdateRequest,
        accessToken: String
    ) async throws {
        try await apiClient.sendNoContent(
            method: .put,
            path: "/api/items/\(id)/state",
            body: request,
            accessToken: accessToken
        )
    }
}

enum MockItemRepositoryError: Error, Equatable {
    case detailNotFound(id: String)
}

struct MockItemStateUpdate: Equatable {
    let itemID: String
    let request: ItemStateUpdateRequest
}

final class MockItemRepository: ItemRepository {
    private(set) var itemDetails: [String: ItemDetail]
    private(set) var stateUpdates: [MockItemStateUpdate] = []

    var detailFailure: Error?
    var stateUpdateFailure: Error?

    init(
        itemDetails: [String: ItemDetail] = [:],
        detailFailure: Error? = nil,
        stateUpdateFailure: Error? = nil
    ) {
        self.itemDetails = itemDetails
        self.detailFailure = detailFailure
        self.stateUpdateFailure = stateUpdateFailure
    }

    func itemDetail(id: String, accessToken: String) async throws -> ItemDetail {
        if let detailFailure {
            throw detailFailure
        }

        guard let detail = itemDetails[id] else {
            throw MockItemRepositoryError.detailNotFound(id: id)
        }

        return detail
    }

    func updateItemState(
        id: String,
        request: ItemStateUpdateRequest,
        accessToken: String
    ) async throws {
        if let stateUpdateFailure {
            throw stateUpdateFailure
        }

        stateUpdates.append(MockItemStateUpdate(itemID: id, request: request))

        guard let detail = itemDetails[id] else {
            return
        }

        itemDetails[id] = ItemDetail(
            id: detail.id,
            feedID: detail.feedID,
            feedTitle: detail.feedTitle,
            feedFaviconURL: detail.feedFaviconURL,
            title: detail.title,
            summary: detail.summary,
            content: detail.content,
            link: detail.link,
            publishedAt: detail.publishedAt,
            isDateEstimated: detail.isDateEstimated,
            isRead: request.isRead ?? detail.isRead,
            isStarred: request.isStarred ?? detail.isStarred,
            hatebuCount: detail.hatebuCount,
            hatebuFetchedAt: detail.hatebuFetchedAt,
            author: detail.author
        )
    }
}

extension FeedRepository {
    func loadCrossFeedFirstPage(limit: Int? = nil) async throws -> CrossFeedPaginationSnapshot {
        throw CrossFeedRepositoryError.paginationUnsupported
    }

    func loadCrossFeedNextPage() async throws -> CrossFeedPaginationSnapshot {
        throw CrossFeedRepositoryError.paginationUnsupported
    }
}

struct CrossFeedPaginationSnapshot: Equatable {
    let items: [ItemSummary]
    let nextCursor: String?
    let canLoadMore: Bool
    let sinceTime: String?
    let limit: Int
}

enum CrossFeedRepositoryError: Error, Equatable {
    case paginationUnsupported
    case nextPageRequestedBeforeFirstPage
    case loadInProgress
    case invalidItemLink(String)
}

enum CrossFeedPageLimit {
    static let defaultValue = 50
    static let maximumValue = 200

    static func normalized(_ limit: Int?) -> Int {
        guard let limit else {
            return defaultValue
        }

        guard limit > 0 else {
            return defaultValue
        }

        return min(limit, maximumValue)
    }
}

actor APIClientFeedRepository: FeedRepository {
    typealias AccessTokenProvider = @Sendable () async throws -> String

    private let apiClient: APIClient
    private let accessTokenProvider: AccessTokenProvider

    private var paginationState = CursorPaginationState<ItemSummary>()
    private var sessionSinceTime: String?
    private var sessionLimit = CrossFeedPageLimit.defaultValue
    private var isLoadingCrossFeedPage = false

    init(
        apiClient: APIClient,
        accessTokenProvider: @escaping AccessTokenProvider
    ) {
        self.apiClient = apiClient
        self.accessTokenProvider = accessTokenProvider
    }

    func subscriptions() async throws -> [Feed] {
        throw CrossFeedRepositoryError.paginationUnsupported
    }

    func crossFeedItems() async throws -> [FeedItem] {
        let snapshot = try await loadCrossFeedFirstPage(limit: nil)
        return try snapshot.items.map(Self.feedItem(from:))
    }

    func loadCrossFeedFirstPage(limit: Int? = nil) async throws -> CrossFeedPaginationSnapshot {
        try startCrossFeedLoad()
        defer {
            finishCrossFeedLoad()
        }

        paginationState.resetForRefresh()
        sessionSinceTime = nil
        sessionLimit = CrossFeedPageLimit.normalized(limit)

        let response = try await fetchCrossFeedPage(
            cursor: nil,
            sinceTime: nil,
            limit: sessionLimit
        )

        paginationState.applyFirstPage(response)
        sessionSinceTime = response.sinceTime

        return snapshot()
    }

    func loadCrossFeedNextPage() async throws -> CrossFeedPaginationSnapshot {
        guard let sessionSinceTime else {
            throw CrossFeedRepositoryError.nextPageRequestedBeforeFirstPage
        }

        guard paginationState.canLoadMore else {
            return snapshot()
        }

        guard let cursor = paginationState.nextCursor else {
            return snapshot()
        }

        try startCrossFeedLoad()
        defer {
            finishCrossFeedLoad()
        }

        let response = try await fetchCrossFeedPage(
            cursor: cursor,
            sinceTime: sessionSinceTime,
            limit: sessionLimit
        )

        paginationState.appendPage(response)
        return snapshot()
    }

    private func fetchCrossFeedPage(
        cursor: String?,
        sinceTime: String?,
        limit: Int
    ) async throws -> CrossFeedItemsResponse {
        var queryItems = [
            URLQueryItem(name: "limit", value: String(limit))
        ]

        if let cursor {
            queryItems.append(URLQueryItem(name: "cursor", value: cursor))
        }

        if let sinceTime {
            queryItems.append(URLQueryItem(name: "since_time", value: sinceTime))
        }

        return try await apiClient.send(
            CrossFeedItemsResponse.self,
            path: "/api/items/cross-feed",
            queryItems: queryItems,
            accessToken: try await accessTokenProvider()
        )
    }

    private func startCrossFeedLoad() throws {
        if isLoadingCrossFeedPage {
            throw CrossFeedRepositoryError.loadInProgress
        }

        isLoadingCrossFeedPage = true
    }

    private func finishCrossFeedLoad() {
        isLoadingCrossFeedPage = false
    }

    private func snapshot() -> CrossFeedPaginationSnapshot {
        CrossFeedPaginationSnapshot(
            items: paginationState.items,
            nextCursor: paginationState.nextCursor,
            canLoadMore: paginationState.canLoadMore,
            sinceTime: sessionSinceTime,
            limit: sessionLimit
        )
    }

    private static func feedItem(from item: ItemSummary) throws -> FeedItem {
        guard let link = URL(string: item.link) else {
            throw CrossFeedRepositoryError.invalidItemLink(item.link)
        }

        return FeedItem(
            id: item.id,
            feedID: item.feedID,
            feedTitle: item.feedTitle,
            title: item.title,
            summary: item.summary ?? "",
            link: link,
            publishedAt: item.publishedAt,
            isRead: item.isRead,
            isStarred: item.isStarred,
            hatebuCount: item.hatebuCount
        )
    }
}

actor MockFeedRepository: FeedRepository {
    private var paginationState = CursorPaginationState<ItemSummary>()
    private var sessionSinceTime: String?
    private var sessionLimit = CrossFeedPageLimit.defaultValue
    private let pages: [CrossFeedItemsResponse]

    init(pages: [CrossFeedItemsResponse]? = nil) {
        self.pages = pages ?? Self.defaultPages
    }

    func subscriptions() async throws -> [Feed] {
        [
            Feed(id: "publickey", title: "Publickey", unreadCount: 12, status: .active),
            Feed(id: "zenn", title: "Zenn トレンド", unreadCount: 5, status: .active),
            Feed(id: "qiita", title: "Qiita 人気の記事", unreadCount: 14, status: .stopped(message: "手動で停止しました")),
            Feed(id: "swift-blog", title: "Swift Blog", unreadCount: 0, status: .error(message: "前回の取得に失敗しました"))
        ]
    }

    func crossFeedItems() async throws -> [FeedItem] {
        let snapshot = try await loadCrossFeedFirstPage(limit: nil)
        return try snapshot.items.map(Self.feedItem(from:))
    }

    func loadCrossFeedFirstPage(limit: Int? = nil) async throws -> CrossFeedPaginationSnapshot {
        paginationState.resetForRefresh()
        sessionSinceTime = nil
        sessionLimit = CrossFeedPageLimit.normalized(limit)

        let response = pages.first ?? Self.emptyPage
        paginationState.applyFirstPage(response)
        sessionSinceTime = response.sinceTime

        return snapshot()
    }

    func loadCrossFeedNextPage() async throws -> CrossFeedPaginationSnapshot {
        guard sessionSinceTime != nil else {
            throw CrossFeedRepositoryError.nextPageRequestedBeforeFirstPage
        }

        guard paginationState.canLoadMore else {
            return snapshot()
        }

        let pageIndex = min(paginationState.items.isEmpty ? 0 : 1, max(pages.count - 1, 0))
        let response = pages.isEmpty ? Self.emptyPage : pages[pageIndex]
        paginationState.appendPage(response)

        return snapshot()
    }

    private func snapshot() -> CrossFeedPaginationSnapshot {
        CrossFeedPaginationSnapshot(
            items: paginationState.items,
            nextCursor: paginationState.nextCursor,
            canLoadMore: paginationState.canLoadMore,
            sinceTime: sessionSinceTime,
            limit: sessionLimit
        )
    }

    private static func feedItem(from item: ItemSummary) throws -> FeedItem {
        guard let link = URL(string: item.link) else {
            throw CrossFeedRepositoryError.invalidItemLink(item.link)
        }

        return FeedItem(
            id: item.id,
            feedID: item.feedID,
            feedTitle: item.feedTitle,
            title: item.title,
            summary: item.summary ?? "",
            link: link,
            publishedAt: item.publishedAt,
            isRead: item.isRead,
            isStarred: item.isStarred,
            hatebuCount: item.hatebuCount
        )
    }
}

private extension MockFeedRepository {
    static let emptyPage = CrossFeedItemsResponse(
        items: [],
        nextCursor: nil,
        hasMore: false,
        sinceTime: "2026-06-08T10:30:00Z"
    )

    static let defaultPages = [
        CrossFeedItemsResponse(
            items: [
                ItemSummary(
                    id: "item-1",
                    feedID: "publickey",
                    feedTitle: "Publickey",
                    feedFaviconURL: nil,
                    title: "Goの新しいイテレータが安定版に、range-over-funcの実用例まとめ",
                    summary: "range-over-func が GA となり、独自コレクションのイテレートが書きやすくなった。",
                    link: "https://example.com/articles/1",
                    publishedAt: "2026-06-08T08:30:00Z",
                    isDateEstimated: false,
                    isRead: false,
                    isStarred: false,
                    hatebuCount: 142,
                    hatebuFetchedAt: nil,
                    author: nil
                ),
                ItemSummary(
                    id: "item-2",
                    feedID: "zenn",
                    feedTitle: "Zenn トレンド",
                    feedFaviconURL: nil,
                    title: "個人開発のSaaSを1年運用して分かったコスト最適化の勘所",
                    summary: "小さく始めて計測しながら削る、という当たり前を徹底した結果を共有する。",
                    link: "https://example.com/articles/2",
                    publishedAt: "2026-06-08T06:45:00Z",
                    isDateEstimated: false,
                    isRead: true,
                    isStarred: true,
                    hatebuCount: 64,
                    hatebuFetchedAt: nil,
                    author: nil
                )
            ],
            nextCursor: "mock-cursor-2",
            hasMore: true,
            sinceTime: "2026-06-08T10:30:00Z"
        ),
        CrossFeedItemsResponse(
            items: [
                ItemSummary(
                    id: "item-3",
                    feedID: "swift-blog",
                    feedTitle: "Swift Blog",
                    feedFaviconURL: nil,
                    title: "Swift Concurrency の実装メモ",
                    summary: "async/await を使った Repository 実装を整理する。",
                    link: "https://example.com/articles/3",
                    publishedAt: "2026-06-07T11:20:00Z",
                    isDateEstimated: false,
                    isRead: false,
                    isStarred: false,
                    hatebuCount: 21,
                    hatebuFetchedAt: nil,
                    author: nil
                )
            ],
            nextCursor: nil,
            hasMore: false,
            sinceTime: "2026-06-08T10:35:00Z"
        )
    ]
}
