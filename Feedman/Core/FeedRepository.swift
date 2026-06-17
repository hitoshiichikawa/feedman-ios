import Foundation

protocol FeedRepository {
    func subscriptions() async throws -> [Feed]
    func registerFeed(url: String) async throws -> RegisteredFeed
    func updateSubscriptionSettings(
        subscriptionID: String,
        request: SubscriptionSettingsRequest
    ) async throws
    func resumeSubscription(subscriptionID: String) async throws
    func unsubscribe(subscriptionID: String) async throws
    func crossFeedItems() async throws -> [FeedItem]
    func loadCrossFeedFirstPage(limit: Int?) async throws -> CrossFeedPaginationSnapshot
    func loadCrossFeedNextPage() async throws -> CrossFeedPaginationSnapshot
    func loadFeedItemsFirstPage(
        feedID: String,
        filter: FeedItemFilter,
        limit: Int?
    ) async throws -> FeedItemPaginationSnapshot
    func loadFeedItemsNextPage() async throws -> FeedItemPaginationSnapshot
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

    func registerFeed(url: String) async throws -> RegisteredFeed {
        throw CrossFeedRepositoryError.paginationUnsupported
    }

    func updateSubscriptionSettings(
        subscriptionID: String,
        request: SubscriptionSettingsRequest
    ) async throws {
        throw CrossFeedRepositoryError.paginationUnsupported
    }

    func resumeSubscription(subscriptionID: String) async throws {
        throw CrossFeedRepositoryError.paginationUnsupported
    }

    func unsubscribe(subscriptionID: String) async throws {
        throw CrossFeedRepositoryError.paginationUnsupported
    }

    func loadFeedItemsFirstPage(
        feedID: String,
        filter: FeedItemFilter = .all,
        limit: Int? = nil
    ) async throws -> FeedItemPaginationSnapshot {
        throw FeedItemRepositoryError.paginationUnsupported
    }

    func loadFeedItemsNextPage() async throws -> FeedItemPaginationSnapshot {
        throw FeedItemRepositoryError.paginationUnsupported
    }
}

struct CrossFeedPaginationSnapshot: Equatable {
    let items: [ItemSummary]
    let nextCursor: String?
    let canLoadMore: Bool
    let sinceTime: String?
    let limit: Int
}

enum FeedItemFilter: String, Equatable, CaseIterable {
    case all
    case unread
    case starred
}

struct FeedItemPaginationSnapshot: Equatable {
    let items: [ItemSummary]
    let nextCursor: String?
    let canLoadMore: Bool
    let feedID: String
    let filter: FeedItemFilter
    let limit: Int
}

enum CrossFeedRepositoryError: Error, Equatable {
    case paginationUnsupported
    case nextPageRequestedBeforeFirstPage
    case loadInProgress
    case invalidItemLink(String)
}

enum FeedItemRepositoryError: Error, Equatable {
    case paginationUnsupported
    case nextPageRequestedBeforeFirstPage
    case loadInProgress
}

struct RegisteredFeed: Equatable {
    let subscriptionID: String
    let feedID: String
    let title: String
    let feedURL: String?
    let siteURL: String?
    let faviconURL: String?
    let fetchIntervalMinutes: Int
    let status: FeedStatus
    let unreadCount: Int

    var drawerFeed: Feed {
        Feed(
            id: feedID,
            subscriptionID: subscriptionID,
            title: title,
            unreadCount: unreadCount,
            status: status,
            faviconURL: faviconURL,
            fetchIntervalMinutes: fetchIntervalMinutes
        )
    }
}

extension RegisteredFeed {
    init(response: FeedRegistrationResponse) {
        self.subscriptionID = response.id
        self.feedID = response.feedID
        self.title = response.feedTitle
        self.feedURL = response.feedURL
        self.siteURL = response.siteURL
        self.faviconURL = response.feedFaviconURL
        self.fetchIntervalMinutes = response.fetchIntervalMinutes
        self.status = FeedStatus(subscriptionStatus: response.feedStatus, message: response.errorMessage)
        self.unreadCount = response.unreadCount
    }
}

private extension FeedStatus {
    init(subscriptionStatus: SubscriptionFeedStatus, message: String?) {
        switch subscriptionStatus {
        case .active:
            self = .active
        case .stopped:
            self = .stopped(message: message ?? "停止中")
        case .error:
            self = .error(message: message ?? "取得エラー")
        }
    }
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

    private struct FeedItemPaginationSession: Equatable {
        let feedID: String
        let filter: FeedItemFilter
        let limit: Int
    }

    private var paginationState = CursorPaginationState<ItemSummary>()
    private var sessionSinceTime: String?
    private var sessionLimit = CrossFeedPageLimit.defaultValue
    private var isLoadingCrossFeedPage = false
    private var feedItemPaginationState = CursorPaginationState<ItemSummary>()
    private var feedItemSession: FeedItemPaginationSession?
    private var isLoadingFeedItemPage = false

    init(
        apiClient: APIClient,
        accessTokenProvider: @escaping AccessTokenProvider
    ) {
        self.apiClient = apiClient
        self.accessTokenProvider = accessTokenProvider
    }

    func subscriptions() async throws -> [Feed] {
        let subscriptions = try await apiClient.send(
            [Subscription].self,
            path: "/api/subscriptions",
            accessToken: try await accessTokenProvider()
        )

        return subscriptions.map(Self.feed(from:))
    }

    func registerFeed(url: String) async throws -> RegisteredFeed {
        let response = try await apiClient.send(
            FeedRegistrationResponse.self,
            method: .post,
            path: "/api/feeds",
            body: FeedRegistrationRequest(url: url),
            accessToken: try await accessTokenProvider()
        )

        return RegisteredFeed(response: response)
    }

    func updateSubscriptionSettings(
        subscriptionID: String,
        request: SubscriptionSettingsRequest
    ) async throws {
        try await apiClient.sendNoContent(
            method: .put,
            path: "/api/subscriptions/\(subscriptionID)/settings",
            body: request,
            accessToken: try await accessTokenProvider()
        )
    }

    func resumeSubscription(subscriptionID: String) async throws {
        try await apiClient.sendNoContent(
            method: .post,
            path: "/api/subscriptions/\(subscriptionID)/resume",
            accessToken: try await accessTokenProvider()
        )
    }

    func unsubscribe(subscriptionID: String) async throws {
        try await apiClient.sendNoContent(
            method: .delete,
            path: "/api/subscriptions/\(subscriptionID)",
            accessToken: try await accessTokenProvider()
        )
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

    func loadFeedItemsFirstPage(
        feedID: String,
        filter: FeedItemFilter = .all,
        limit: Int? = nil
    ) async throws -> FeedItemPaginationSnapshot {
        try startFeedItemLoad()
        defer {
            finishFeedItemLoad()
        }

        feedItemPaginationState.resetForRefresh()
        feedItemSession = nil

        let normalizedLimit = CrossFeedPageLimit.normalized(limit)
        let response = try await fetchFeedItemPage(
            feedID: feedID,
            filter: filter,
            cursor: nil,
            limit: normalizedLimit
        )

        feedItemPaginationState.applyFirstPage(response)
        feedItemSession = FeedItemPaginationSession(
            feedID: feedID,
            filter: filter,
            limit: normalizedLimit
        )

        return feedItemSnapshot()
    }

    func loadFeedItemsNextPage() async throws -> FeedItemPaginationSnapshot {
        guard let feedItemSession else {
            throw FeedItemRepositoryError.nextPageRequestedBeforeFirstPage
        }

        guard feedItemPaginationState.canLoadMore else {
            return feedItemSnapshot()
        }

        guard let cursor = feedItemPaginationState.nextCursor else {
            return feedItemSnapshot()
        }

        try startFeedItemLoad()
        defer {
            finishFeedItemLoad()
        }

        let response = try await fetchFeedItemPage(
            feedID: feedItemSession.feedID,
            filter: feedItemSession.filter,
            cursor: cursor,
            limit: feedItemSession.limit
        )

        feedItemPaginationState.appendPage(response)
        return feedItemSnapshot()
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

    private func fetchFeedItemPage(
        feedID: String,
        filter: FeedItemFilter,
        cursor: String?,
        limit: Int
    ) async throws -> CursorPaginatedResponse<ItemSummary> {
        var queryItems = [
            URLQueryItem(name: "filter", value: filter.rawValue),
            URLQueryItem(name: "limit", value: String(limit))
        ]

        if let cursor {
            queryItems.append(URLQueryItem(name: "cursor", value: cursor))
        }

        return try await apiClient.send(
            CursorPaginatedResponse<ItemSummary>.self,
            path: "/api/feeds/\(feedID)/items",
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

    private func startFeedItemLoad() throws {
        if isLoadingFeedItemPage {
            throw FeedItemRepositoryError.loadInProgress
        }

        isLoadingFeedItemPage = true
    }

    private func finishFeedItemLoad() {
        isLoadingFeedItemPage = false
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

    private func feedItemSnapshot() -> FeedItemPaginationSnapshot {
        let session = feedItemSession ?? FeedItemPaginationSession(
            feedID: "",
            filter: .all,
            limit: CrossFeedPageLimit.defaultValue
        )

        return FeedItemPaginationSnapshot(
            items: feedItemPaginationState.items,
            nextCursor: feedItemPaginationState.nextCursor,
            canLoadMore: feedItemPaginationState.canLoadMore,
            feedID: session.feedID,
            filter: session.filter,
            limit: session.limit
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

    private static func feed(from subscription: Subscription) -> Feed {
        Feed(
            id: subscription.feedID,
            subscriptionID: subscription.id,
            title: subscription.feedTitle,
            unreadCount: max(0, subscription.unreadCount),
            status: feedStatus(from: subscription),
            faviconURL: subscription.feedFaviconURL,
            fetchIntervalMinutes: subscription.fetchIntervalMinutes
        )
    }

    private static func feedStatus(from subscription: Subscription) -> FeedStatus {
        switch subscription.feedStatus {
        case .active:
            return .active
        case .stopped:
            return .stopped(message: subscription.errorMessage ?? "停止中")
        case .error:
            return .error(message: subscription.errorMessage ?? "取得エラー")
        }
    }
}

actor MockFeedRepository: FeedRepository {
    private struct FeedItemPaginationSession: Equatable {
        let feedID: String
        let filter: FeedItemFilter
        let limit: Int
    }

    private var paginationState = CursorPaginationState<ItemSummary>()
    private var sessionSinceTime: String?
    private var sessionLimit = CrossFeedPageLimit.defaultValue
    private var feedItemPaginationState = CursorPaginationState<ItemSummary>()
    private var feedItemSession: FeedItemPaginationSession?
    private let pages: [CrossFeedItemsResponse]
    private var subscriptionFeeds: [Feed]
    private(set) var settingsUpdates: [MockSubscriptionSettingsUpdate] = []
    private(set) var resumedSubscriptionIDs: [String] = []
    private(set) var unsubscribedSubscriptionIDs: [String] = []
    var registrationResult: Result<RegisteredFeed, Error>
    var settingsUpdateResult: Result<Void, Error>
    var resumeResult: Result<Void, Error>
    var unsubscribeResult: Result<Void, Error>
    private(set) var registeredURLs: [String] = []

    init(
        pages: [CrossFeedItemsResponse]? = nil,
        subscriptionFeeds: [Feed]? = nil,
        registrationResult: Result<RegisteredFeed, Error>? = nil,
        settingsUpdateResult: Result<Void, Error> = .success(()),
        resumeResult: Result<Void, Error> = .success(()),
        unsubscribeResult: Result<Void, Error> = .success(())
    ) {
        self.pages = pages ?? Self.defaultPages
        self.subscriptionFeeds = subscriptionFeeds ?? Self.defaultSubscriptionFeeds
        self.registrationResult = registrationResult ?? .success(Self.defaultRegisteredFeed)
        self.settingsUpdateResult = settingsUpdateResult
        self.resumeResult = resumeResult
        self.unsubscribeResult = unsubscribeResult
    }

    func subscriptions() async throws -> [Feed] {
        subscriptionFeeds
    }

    func registerFeed(url: String) async throws -> RegisteredFeed {
        registeredURLs.append(url)

        let registeredFeed = try registrationResult.get()
        upsertSubscription(registeredFeed.drawerFeed)
        return registeredFeed
    }

    func updateSubscriptionSettings(
        subscriptionID: String,
        request: SubscriptionSettingsRequest
    ) async throws {
        settingsUpdates.append(
            MockSubscriptionSettingsUpdate(
                subscriptionID: subscriptionID,
                request: request
            )
        )
        try settingsUpdateResult.get()

        guard let fetchIntervalMinutes = request.fetchIntervalMinutes,
              let index = subscriptionFeeds.firstIndex(where: { $0.subscriptionID == subscriptionID }) else {
            return
        }

        let feed = subscriptionFeeds[index]
        subscriptionFeeds[index] = feed.updating(fetchIntervalMinutes: fetchIntervalMinutes)
    }

    func resumeSubscription(subscriptionID: String) async throws {
        resumedSubscriptionIDs.append(subscriptionID)
        try resumeResult.get()

        guard let index = subscriptionFeeds.firstIndex(where: { $0.subscriptionID == subscriptionID }) else {
            return
        }

        subscriptionFeeds[index] = subscriptionFeeds[index].updating(status: .active)
    }

    func unsubscribe(subscriptionID: String) async throws {
        unsubscribedSubscriptionIDs.append(subscriptionID)
        try unsubscribeResult.get()
        subscriptionFeeds.removeAll { $0.subscriptionID == subscriptionID }
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

    func loadFeedItemsFirstPage(
        feedID: String,
        filter: FeedItemFilter = .all,
        limit: Int? = nil
    ) async throws -> FeedItemPaginationSnapshot {
        let normalizedLimit = CrossFeedPageLimit.normalized(limit)
        let session = FeedItemPaginationSession(
            feedID: feedID,
            filter: filter,
            limit: normalizedLimit
        )

        feedItemPaginationState.resetForRefresh()
        feedItemSession = session
        feedItemPaginationState.applyFirstPage(mockFeedItemPage(for: session, offset: 0))

        return feedItemSnapshot()
    }

    func loadFeedItemsNextPage() async throws -> FeedItemPaginationSnapshot {
        guard let feedItemSession else {
            throw FeedItemRepositoryError.nextPageRequestedBeforeFirstPage
        }

        guard feedItemPaginationState.canLoadMore else {
            return feedItemSnapshot()
        }

        guard
            let cursor = feedItemPaginationState.nextCursor,
            let offset = Int(cursor)
        else {
            return feedItemSnapshot()
        }

        feedItemPaginationState.appendPage(mockFeedItemPage(for: feedItemSession, offset: offset))
        return feedItemSnapshot()
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

    private func feedItemSnapshot() -> FeedItemPaginationSnapshot {
        let session = feedItemSession ?? FeedItemPaginationSession(
            feedID: "",
            filter: .all,
            limit: CrossFeedPageLimit.defaultValue
        )

        return FeedItemPaginationSnapshot(
            items: feedItemPaginationState.items,
            nextCursor: feedItemPaginationState.nextCursor,
            canLoadMore: feedItemPaginationState.canLoadMore,
            feedID: session.feedID,
            filter: session.filter,
            limit: session.limit
        )
    }

    private func mockFeedItemPage(
        for session: FeedItemPaginationSession,
        offset: Int
    ) -> CursorPaginatedResponse<ItemSummary> {
        let filteredItems = Self.defaultFeedSpecificItems
            .filter { item in
                item.feedID == session.feedID && Self.includes(item: item, in: session.filter)
            }
        let safeOffset = min(max(offset, 0), filteredItems.count)
        let pageItems = Array(filteredItems.dropFirst(safeOffset).prefix(session.limit))
        let nextOffset = safeOffset + pageItems.count
        let hasMore = nextOffset < filteredItems.count

        return CursorPaginatedResponse(
            items: pageItems,
            nextCursor: hasMore ? String(nextOffset) : nil,
            hasMore: hasMore
        )
    }

    private static func includes(item: ItemSummary, in filter: FeedItemFilter) -> Bool {
        switch filter {
        case .all:
            return true
        case .unread:
            return !item.isRead
        case .starred:
            return item.isStarred
        }
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

    private func upsertSubscription(_ feed: Feed) {
        if let index = subscriptionFeeds.firstIndex(where: { $0.id == feed.id }) {
            subscriptionFeeds[index] = feed
        } else {
            subscriptionFeeds.append(feed)
        }
    }
}

struct MockSubscriptionSettingsUpdate: Equatable {
    let subscriptionID: String
    let request: SubscriptionSettingsRequest
}

private extension Feed {
    func updating(
        status: FeedStatus? = nil,
        fetchIntervalMinutes: Int? = nil
    ) -> Feed {
        Feed(
            id: id,
            subscriptionID: subscriptionID,
            title: title,
            unreadCount: unreadCount,
            status: status ?? self.status,
            faviconURL: faviconURL,
            fetchIntervalMinutes: fetchIntervalMinutes ?? self.fetchIntervalMinutes
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

    static let defaultSubscriptionFeeds = [
        Feed(id: "publickey", subscriptionID: "sub-publickey", title: "Publickey", unreadCount: 12, status: .active, fetchIntervalMinutes: 60),
        Feed(id: "zenn", subscriptionID: "sub-zenn", title: "Zenn トレンド", unreadCount: 5, status: .active, fetchIntervalMinutes: 30),
        Feed(id: "qiita", subscriptionID: "sub-qiita", title: "Qiita 人気の記事", unreadCount: 14, status: .stopped(message: "手動で停止しました"), fetchIntervalMinutes: 180),
        Feed(id: "swift-blog", subscriptionID: "sub-swift-blog", title: "Swift Blog", unreadCount: 0, status: .error(message: "前回の取得に失敗しました"), fetchIntervalMinutes: 60)
    ]

    static let defaultRegisteredFeed = RegisteredFeed(
        subscriptionID: "sub-example",
        feedID: "feed-example",
        title: "Example Blog",
        feedURL: "https://example.com/feed.xml",
        siteURL: "https://example.com",
        faviconURL: nil,
        fetchIntervalMinutes: 60,
        status: .active,
        unreadCount: 0
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

    static let defaultFeedSpecificItems = [
        ItemSummary(
            id: "publickey-item-1",
            feedID: "publickey",
            feedTitle: "Publickey",
            feedFaviconURL: nil,
            title: "Swift 6.2 の移行計画",
            summary: "Strict concurrency を段階導入するための実装メモ。",
            link: "https://example.com/publickey/1",
            publishedAt: "2026-06-08T09:30:00Z",
            isDateEstimated: false,
            isRead: false,
            isStarred: false,
            hatebuCount: 31,
            hatebuFetchedAt: nil,
            author: nil
        ),
        ItemSummary(
            id: "publickey-item-2",
            feedID: "publickey",
            feedTitle: "Publickey",
            feedFaviconURL: nil,
            title: "iOS アプリの Repository 境界を整理する",
            summary: "APIClient と ViewModel の責務を分ける設計例。",
            link: "https://example.com/publickey/2",
            publishedAt: "2026-06-08T08:10:00Z",
            isDateEstimated: false,
            isRead: true,
            isStarred: true,
            hatebuCount: 18,
            hatebuFetchedAt: nil,
            author: nil
        ),
        ItemSummary(
            id: "publickey-item-3",
            feedID: "publickey",
            feedTitle: "Publickey",
            feedFaviconURL: nil,
            title: "URLSession と Codable の実装パターン",
            summary: "薄い API client を保つための pagination handling。",
            link: "https://example.com/publickey/3",
            publishedAt: "2026-06-07T12:00:00Z",
            isDateEstimated: false,
            isRead: false,
            isStarred: true,
            hatebuCount: 9,
            hatebuFetchedAt: nil,
            author: nil
        ),
        ItemSummary(
            id: "zenn-item-1",
            feedID: "zenn",
            feedTitle: "Zenn トレンド",
            feedFaviconURL: nil,
            title: "SwiftUI の sheet 状態管理",
            summary: "ViewModel と sheet presentation を分離する。",
            link: "https://example.com/zenn/1",
            publishedAt: "2026-06-07T10:45:00Z",
            isDateEstimated: false,
            isRead: false,
            isStarred: false,
            hatebuCount: 44,
            hatebuFetchedAt: nil,
            author: nil
        )
    ]
}
