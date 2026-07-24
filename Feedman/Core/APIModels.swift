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

    init(
        id: String,
        feedID: String,
        feedTitle: String,
        feedFaviconURL: String?,
        title: String,
        summary: String?,
        link: String,
        publishedAt: String,
        isDateEstimated: Bool,
        isRead: Bool,
        isStarred: Bool,
        hatebuCount: Int?,
        hatebuFetchedAt: String?,
        author: String?
    ) {
        self.id = id
        self.feedID = feedID
        self.feedTitle = feedTitle
        self.feedFaviconURL = feedFaviconURL
        self.title = title
        self.summary = summary
        self.link = link
        self.publishedAt = publishedAt
        self.isDateEstimated = isDateEstimated
        self.isRead = isRead
        self.isStarred = isStarred
        self.hatebuCount = hatebuCount
        self.hatebuFetchedAt = hatebuFetchedAt
        self.author = author
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        feedID = try container.decode(String.self, forKey: .feedID)
        feedTitle = try container.decodeIfPresent(String.self, forKey: .feedTitle) ?? ""
        feedFaviconURL = try container.decodeIfPresent(String.self, forKey: .feedFaviconURL)
        title = try container.decode(String.self, forKey: .title)
        summary = try container.decodeIfPresent(String.self, forKey: .summary)
        link = try container.decode(String.self, forKey: .link)
        publishedAt = try container.decode(String.self, forKey: .publishedAt)
        isDateEstimated = try container.decode(Bool.self, forKey: .isDateEstimated)
        isRead = try container.decode(Bool.self, forKey: .isRead)
        isStarred = try container.decode(Bool.self, forKey: .isStarred)
        hatebuCount = try container.decodeIfPresent(Int.self, forKey: .hatebuCount)
        hatebuFetchedAt = try container.decodeIfPresent(String.self, forKey: .hatebuFetchedAt)
        author = try container.decodeIfPresent(String.self, forKey: .author)
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

    init(
        id: String,
        feedID: String,
        feedTitle: String,
        feedFaviconURL: String?,
        title: String,
        summary: String?,
        content: String?,
        link: String,
        publishedAt: String,
        isDateEstimated: Bool,
        isRead: Bool,
        isStarred: Bool,
        hatebuCount: Int?,
        hatebuFetchedAt: String?,
        author: String?
    ) {
        self.id = id
        self.feedID = feedID
        self.feedTitle = feedTitle
        self.feedFaviconURL = feedFaviconURL
        self.title = title
        self.summary = summary
        self.content = content
        self.link = link
        self.publishedAt = publishedAt
        self.isDateEstimated = isDateEstimated
        self.isRead = isRead
        self.isStarred = isStarred
        self.hatebuCount = hatebuCount
        self.hatebuFetchedAt = hatebuFetchedAt
        self.author = author
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        feedID = try container.decode(String.self, forKey: .feedID)
        feedTitle = try container.decodeIfPresent(String.self, forKey: .feedTitle) ?? ""
        feedFaviconURL = try container.decodeIfPresent(String.self, forKey: .feedFaviconURL)
        title = try container.decode(String.self, forKey: .title)
        summary = try container.decodeIfPresent(String.self, forKey: .summary)
        content = try container.decodeIfPresent(String.self, forKey: .content)
        link = try container.decode(String.self, forKey: .link)
        publishedAt = try container.decode(String.self, forKey: .publishedAt)
        isDateEstimated = try container.decode(Bool.self, forKey: .isDateEstimated)
        isRead = try container.decode(Bool.self, forKey: .isRead)
        isStarred = try container.decode(Bool.self, forKey: .isStarred)
        hatebuCount = try container.decodeIfPresent(Int.self, forKey: .hatebuCount)
        hatebuFetchedAt = try container.decodeIfPresent(String.self, forKey: .hatebuFetchedAt)
        author = try container.decodeIfPresent(String.self, forKey: .author)
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
        case feedFaviconURL = "favicon_url"
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

struct SearchItemsResponse: Codable, Equatable {
    let items: [ItemSearchHit]
    let nextCursor: String?
    let hasMore: Bool

    var usableNextCursor: String? {
        guard let cursor = nextCursor?.trimmingCharacters(in: .whitespacesAndNewlines),
              !cursor.isEmpty
        else {
            return nil
        }

        return cursor
    }

    var canLoadMore: Bool {
        hasMore && usableNextCursor != nil
    }

    enum CodingKeys: String, CodingKey {
        case items
        case nextCursor = "next_cursor"
        case hasMore = "has_more"
    }
}

struct FeedRegistrationRequest: Codable, Equatable {
    let url: String
}

struct FeedRegistrationResponse: Codable, Equatable {
    let id: String
    let feedURL: String?
    let siteURL: String?
    let title: String
    let fetchStatus: String

    enum CodingKeys: String, CodingKey {
        case id
        case feedURL = "feed_url"
        case siteURL = "site_url"
        case title
        case fetchStatus = "fetch_status"
    }
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
    let username: String?
    let email: String?
    let name: String?
    let avatarURL: String?

    enum CodingKeys: String, CodingKey {
        case id
        case username
        case email
        case name
        case avatarURL = "avatar_url"
    }

    init(
        id: String,
        username: String? = nil,
        email: String?,
        name: String?,
        avatarURL: String?
    ) {
        self.id = id
        self.username = username
        self.email = email
        self.name = name
        self.avatarURL = avatarURL
    }
}

struct PasskeyRegistrationBeginRequest: Codable, Equatable {
    let username: String
    let codeChallenge: String

    enum CodingKeys: String, CodingKey {
        case username
        case codeChallenge = "code_challenge"
    }
}

struct PasskeyAuthenticationBeginRequest: Codable, Equatable {
    let codeChallenge: String

    enum CodingKeys: String, CodingKey {
        case codeChallenge = "code_challenge"
    }
}

struct PasskeyRegistrationFinishRequest: Codable, Equatable {
    let challengeID: String
    let credential: PasskeyCredentialEnvelope

    enum CodingKeys: String, CodingKey {
        case challengeID = "challenge_id"
        case credential
    }
}

struct PasskeyAuthenticationFinishRequest: Codable, Equatable {
    let challengeID: String
    let credential: PasskeyCredentialEnvelope

    enum CodingKeys: String, CodingKey {
        case challengeID = "challenge_id"
        case credential
    }
}

struct PasskeyAddRegistrationFinishRequest: Codable, Equatable {
    let challengeID: String
    let credential: PasskeyCredentialEnvelope

    enum CodingKeys: String, CodingKey {
        case challengeID = "challenge_id"
        case credential
    }
}

struct PasskeyEmptyRequest: Codable, Equatable {}

struct PasskeyRegistrationBeginResponse: Codable, Equatable {
    let challengeID: String
    let options: PasskeyPublicKeyCredentialCreationOptionsEnvelope

    enum CodingKeys: String, CodingKey {
        case challengeID = "challenge_id"
        case options
    }
}

struct PasskeyAuthenticationBeginResponse: Codable, Equatable {
    let challengeID: String
    let options: PasskeyPublicKeyCredentialRequestOptionsEnvelope

    enum CodingKeys: String, CodingKey {
        case challengeID = "challenge_id"
        case options
    }
}

struct PasskeyAddRegistrationBeginResponse: Codable, Equatable {
    let challengeID: String
    let options: PasskeyPublicKeyCredentialCreationOptionsEnvelope

    enum CodingKeys: String, CodingKey {
        case challengeID = "challenge_id"
        case options
    }
}

struct PasskeyRegistrationFinishResponse: Codable, Equatable {
    let userID: String

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
    }
}

struct PasskeyAuthenticationFinishResponse: Codable, Equatable {
    let authCode: String

    enum CodingKeys: String, CodingKey {
        case authCode = "auth_code"
    }
}

struct PasskeyPublicKeyCredentialCreationOptionsEnvelope: Codable, Equatable {
    let publicKey: PasskeyPublicKeyCredentialCreationOptions
}

struct PasskeyPublicKeyCredentialRequestOptionsEnvelope: Codable, Equatable {
    let publicKey: PasskeyPublicKeyCredentialRequestOptions
}

struct PasskeyPublicKeyCredentialCreationOptions: Codable, Equatable {
    let challenge: String
    let rp: PasskeyRelyingParty
    let user: PasskeyUserEntity
    let pubKeyCredParams: [PasskeyPublicKeyCredentialParameter]
    let timeout: Int?
    let excludeCredentials: [PasskeyCredentialDescriptor]?
    let authenticatorSelection: PasskeyAuthenticatorSelectionCriteria?
    let attestation: String?
}

struct PasskeyPublicKeyCredentialRequestOptions: Codable, Equatable {
    let challenge: String
    let rpID: String?
    let timeout: Int?
    let allowCredentials: [PasskeyCredentialDescriptor]?
    let userVerification: String?

    enum CodingKeys: String, CodingKey {
        case challenge
        case rpID = "rpId"
        case timeout
        case allowCredentials
        case userVerification
    }
}

struct PasskeyRelyingParty: Codable, Equatable {
    let id: String?
    let name: String
}

struct PasskeyUserEntity: Codable, Equatable {
    let id: String
    let name: String
    let displayName: String
}

struct PasskeyPublicKeyCredentialParameter: Codable, Equatable {
    let type: String
    let alg: Int
}

struct PasskeyCredentialDescriptor: Codable, Equatable {
    let type: String
    let id: String
    let transports: [String]?

    init(type: String, id: String, transports: [String]? = nil) {
        self.type = type
        self.id = id
        self.transports = transports
    }
}

struct PasskeyAuthenticatorSelectionCriteria: Codable, Equatable {
    let authenticatorAttachment: String?
    let residentKey: String?
    let userVerification: String?
}

struct PasskeyCredentialEnvelope: Codable, Equatable {
    let id: String
    let rawID: String
    let type: String
    let response: PasskeyCredentialResponse

    enum CodingKeys: String, CodingKey {
        case id
        case rawID = "rawId"
        case type
        case response
    }
}

enum PasskeyCredentialResponse: Codable, Equatable {
    case registration(PasskeyRegistrationCredentialResponse)
    case assertion(PasskeyAssertionCredentialResponse)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let registration = try? container.decode(PasskeyRegistrationCredentialResponse.self),
           registration.attestationObject != nil {
            self = .registration(registration)
            return
        }
        self = .assertion(try container.decode(PasskeyAssertionCredentialResponse.self))
    }

    func encode(to encoder: Encoder) throws {
        switch self {
        case .registration(let response):
            try response.encode(to: encoder)
        case .assertion(let response):
            try response.encode(to: encoder)
        }
    }
}

struct PasskeyRegistrationCredentialResponse: Codable, Equatable {
    let clientDataJSON: String
    let attestationObject: String?
    let transports: [String]?

    init(
        clientDataJSON: String,
        attestationObject: String?,
        transports: [String]? = nil
    ) {
        self.clientDataJSON = clientDataJSON
        self.attestationObject = attestationObject
        self.transports = transports
    }
}

struct PasskeyAssertionCredentialResponse: Codable, Equatable {
    let clientDataJSON: String
    let authenticatorData: String
    let signature: String
    let userHandle: String?
}

struct DeviceRegistrationRequest: Codable, Equatable {
    let platform: String
    let pushToken: String

    enum CodingKeys: String, CodingKey {
        case platform
        case pushToken = "push_token"
    }
}

struct DeviceRegistrationResponse: Codable, Equatable {
    let id: String
}

struct KeywordResponse: Codable, Equatable {
    let id: String
    let term: String
    let scope: String
    let enabled: Bool
    let hits: Int
}

struct KeywordCreateRequest: Codable, Equatable {
    let term: String
    let scope: String
    let enabled: Bool

    init(term: String, scope: String = "title", enabled: Bool) {
        self.term = term
        self.scope = scope
        self.enabled = enabled
    }
}

struct KeywordUpdateRequest: Codable, Equatable {
    let term: String?
    let enabled: Bool?
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
