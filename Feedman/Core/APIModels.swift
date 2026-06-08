import Foundation

struct ItemSummary: Codable, Equatable {
    let id: String
    let feedID: String
    let feedTitle: String
    let feedFaviconURL: String?
    let title: String
    let summary: String?
    let link: String
    let publishedAt: String
    let isDateEstimated: Bool
    let isRead: Bool
    let isStarred: Bool
    let hatebuCount: Int?
    let hatebuFetchedAt: String?
    let author: String?

    enum CodingKeys: String, CodingKey {
        case id
        case feedID = "feed_id"
        case feedTitle = "feed_title"
        case feedFaviconURL = "feed_favicon_url"
        case title
        case summary
        case link
        case publishedAt = "published_at"
        case isDateEstimated = "is_date_estimated"
        case isRead = "is_read"
        case isStarred = "is_starred"
        case hatebuCount = "hatebu_count"
        case hatebuFetchedAt = "hatebu_fetched_at"
        case author
    }
}

struct ItemDetail: Codable, Equatable {
    let id: String
    let feedID: String
    let feedTitle: String
    let feedFaviconURL: String?
    let title: String
    let summary: String?
    let content: String?
    let link: String
    let publishedAt: String
    let isDateEstimated: Bool
    let isRead: Bool
    let isStarred: Bool
    let hatebuCount: Int?
    let hatebuFetchedAt: String?
    let author: String?

    enum CodingKeys: String, CodingKey {
        case id
        case feedID = "feed_id"
        case feedTitle = "feed_title"
        case feedFaviconURL = "feed_favicon_url"
        case title
        case summary
        case content
        case link
        case publishedAt = "published_at"
        case isDateEstimated = "is_date_estimated"
        case isRead = "is_read"
        case isStarred = "is_starred"
        case hatebuCount = "hatebu_count"
        case hatebuFetchedAt = "hatebu_fetched_at"
        case author
    }
}

struct ItemSearchHit: Codable, Equatable {
    let id: String
    let feedID: String?
    let feedTitle: String
    let faviconURL: String?
    let title: String
    let summary: String?
    let link: String
    let publishedAt: String?
    let isDateEstimated: Bool?
    let isRead: Bool?
    let isStarred: Bool?
    let hatebuCount: Int?
    let author: String?

    enum CodingKeys: String, CodingKey {
        case id
        case feedID = "feed_id"
        case feedTitle = "feed_title"
        case faviconURL = "favicon_url"
        case title
        case summary
        case link
        case publishedAt = "published_at"
        case isDateEstimated = "is_date_estimated"
        case isRead = "is_read"
        case isStarred = "is_starred"
        case hatebuCount = "hatebu_count"
        case author
    }
}

struct Subscription: Codable, Equatable {
    let id: String
    let feedID: String
    let feedTitle: String
    let feedURL: String?
    let siteURL: String?
    let feedFaviconURL: String?
    let fetchIntervalMinutes: Int
    let feedStatus: SubscriptionFeedStatus
    let errorMessage: String?
    let unreadCount: Int

    enum CodingKeys: String, CodingKey {
        case id
        case feedID = "feed_id"
        case feedTitle = "feed_title"
        case feedURL = "feed_url"
        case siteURL = "site_url"
        case feedFaviconURL = "feed_favicon_url"
        case fetchIntervalMinutes = "fetch_interval_minutes"
        case feedStatus = "feed_status"
        case errorMessage = "error_message"
        case unreadCount = "unread_count"
    }
}

enum SubscriptionFeedStatus: String, Codable, Equatable {
    case active
    case stopped
    case error
}

struct CursorPaginatedResponse<Item: Codable & Equatable>: Codable, Equatable {
    let items: [Item]
    let nextCursor: String?
    let hasMore: Bool

    enum CodingKeys: String, CodingKey {
        case items
        case nextCursor = "next_cursor"
        case hasMore = "has_more"
    }
}

struct CrossFeedItemsResponse: Codable, Equatable {
    let items: [ItemSummary]
    let nextCursor: String?
    let hasMore: Bool
    let sinceTime: String

    enum CodingKeys: String, CodingKey {
        case items
        case nextCursor = "next_cursor"
        case hasMore = "has_more"
        case sinceTime = "since_time"
    }
}

struct FeedRegistrationRequest: Codable, Equatable {
    let url: String
}

struct FeedRegistrationResponse: Codable, Equatable {
    let subscription: Subscription
}

struct SubscriptionSettingsRequest: Codable, Equatable {
    let fetchIntervalMinutes: Int?

    enum CodingKeys: String, CodingKey {
        case fetchIntervalMinutes = "fetch_interval_minutes"
    }
}

struct ItemStateUpdateRequest: Codable, Equatable {
    let isRead: Bool?
    let isStarred: Bool?

    enum CodingKeys: String, CodingKey {
        case isRead = "is_read"
        case isStarred = "is_starred"
    }
}

struct UserResponse: Codable, Equatable {
    let id: String
    let email: String
    let name: String?
    let avatarURL: String?

    enum CodingKeys: String, CodingKey {
        case id
        case email
        case name
        case avatarURL = "avatar_url"
    }
}

struct AuthTokenExchangeRequest: Codable, Equatable {
    let authCode: String
    let codeVerifier: String

    enum CodingKeys: String, CodingKey {
        case authCode = "auth_code"
        case codeVerifier = "code_verifier"
    }
}

struct AuthRefreshRequest: Codable, Equatable {
    let refreshToken: String

    enum CodingKeys: String, CodingKey {
        case refreshToken = "refresh_token"
    }
}

struct AuthRevokeRequest: Codable, Equatable {
    let refreshToken: String

    enum CodingKeys: String, CodingKey {
        case refreshToken = "refresh_token"
    }
}

struct AuthTokenResponse: Codable, Equatable {
    let accessToken: String
    let refreshToken: String
    let tokenType: String
    let expiresIn: Int

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case tokenType = "token_type"
        case expiresIn = "expires_in"
    }
}

struct FeedmanErrorResponse: Codable, Equatable {
    let error: FeedmanErrorBody
}

struct FeedmanErrorBody: Codable, Equatable {
    let code: String
    let message: String
    let category: String
    let action: String
    let details: [String: JSONValue]?
}

enum JSONValue: Codable, Equatable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    var intValue: Int? {
        if case let .int(value) = self {
            return value
        }
        return nil
    }

    var stringValue: String? {
        if case let .string(value) = self {
            return value
        }
        return nil
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int.self) {
            self = .int(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: JSONValue].self))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch self {
        case let .string(value):
            try container.encode(value)
        case let .int(value):
            try container.encode(value)
        case let .double(value):
            try container.encode(value)
        case let .bool(value):
            try container.encode(value)
        case let .object(value):
            try container.encode(value)
        case let .array(value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }
}
