import Foundation

struct Feed: Identifiable, Equatable {
    let id: String
    let title: String
    let unreadCount: Int
    let status: FeedStatus
}

enum FeedStatus: Equatable {
    case active
    case stopped(message: String)
    case error(message: String)
}

struct FeedItem: Identifiable, Equatable {
    let id: String
    let feedID: String
    let feedTitle: String
    let title: String
    let summary: String
    let link: URL
    let publishedAt: String
    var isRead: Bool
    var isStarred: Bool
    let hatebuCount: Int?
}

