import Foundation

protocol FeedRepository {
    func subscriptions() async throws -> [Feed]
    func crossFeedItems() async throws -> [FeedItem]
}

struct MockFeedRepository: FeedRepository {
    func subscriptions() async throws -> [Feed] {
        [
            Feed(id: "publickey", title: "Publickey", unreadCount: 12, status: .active),
            Feed(id: "zenn", title: "Zenn トレンド", unreadCount: 5, status: .active),
            Feed(id: "qiita", title: "Qiita 人気の記事", unreadCount: 14, status: .stopped(message: "手動で停止しました"))
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

