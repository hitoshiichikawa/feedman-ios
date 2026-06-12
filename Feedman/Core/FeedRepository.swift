import Foundation

protocol FeedRepository {
    func subscriptions() async throws -> [Feed]
    func crossFeedItems() async throws -> [FeedItem]
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

struct MockFeedRepository: FeedRepository {
    func subscriptions() async throws -> [Feed] {
        [
            Feed(id: "publickey", title: "Publickey", unreadCount: 12, status: .active),
            Feed(id: "zenn", title: "Zenn トレンド", unreadCount: 5, status: .active),
            Feed(id: "qiita", title: "Qiita 人気の記事", unreadCount: 14, status: .stopped(message: "手動で停止しました")),
            Feed(id: "swift-blog", title: "Swift Blog", unreadCount: 0, status: .error(message: "前回の取得に失敗しました"))
        ]
    }

    func crossFeedItems() async throws -> [FeedItem] {
        [
            FeedItem(
                id: "item-1",
                feedID: "publickey",
                feedTitle: "Publickey",
                title: "Goの新しいイテレータが安定版に、range-over-funcの実用例まとめ",
                summary: "range-over-func が GA となり、独自コレクションのイテレートが書きやすくなった。",
                link: URL(string: "https://example.com/articles/1")!,
                publishedAt: "2026-06-08T08:30:00Z",
                isRead: false,
                isStarred: false,
                hatebuCount: 142
            ),
            FeedItem(
                id: "item-2",
                feedID: "zenn",
                feedTitle: "Zenn トレンド",
                title: "個人開発のSaaSを1年運用して分かったコスト最適化の勘所",
                summary: "小さく始めて計測しながら削る、という当たり前を徹底した結果を共有する。",
                link: URL(string: "https://example.com/articles/2")!,
                publishedAt: "2026-06-08T06:45:00Z",
                isRead: true,
                isStarred: true,
                hatebuCount: 64
            )
        ]
    }
}
