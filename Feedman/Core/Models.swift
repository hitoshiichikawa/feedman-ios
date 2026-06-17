import Foundation

struct Feed: Identifiable, Equatable {
    let id: String
    let subscriptionID: String?
    let title: String
    let unreadCount: Int
    let status: FeedStatus
    let faviconURL: String?
    let fetchIntervalMinutes: Int?

    init(
        id: String,
        subscriptionID: String? = nil,
        title: String,
        unreadCount: Int,
        status: FeedStatus,
        faviconURL: String? = nil,
        fetchIntervalMinutes: Int? = nil
    ) {
        self.id = id
        self.subscriptionID = subscriptionID
        self.title = title
        self.unreadCount = unreadCount
        self.status = status
        self.faviconURL = faviconURL
        self.fetchIntervalMinutes = fetchIntervalMinutes
    }
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

struct ItemStateChange: Identifiable, Equatable {
    let id: UUID
    let itemID: String
    let isRead: Bool?
    let isStarred: Bool?

    init(
        id: UUID = UUID(),
        itemID: String,
        isRead: Bool? = nil,
        isStarred: Bool? = nil
    ) {
        self.id = id
        self.itemID = itemID
        self.isRead = isRead
        self.isStarred = isStarred
    }
}
