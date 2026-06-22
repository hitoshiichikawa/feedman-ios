import Foundation

struct NotificationArticleTarget: Equatable, Identifiable {
    let itemID: String

    init(itemID: String) {
        self.itemID = itemID.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var id: String {
        itemID
    }
}

enum NotificationArticleTargetRejectionReason: Error, Equatable {
    case unsupportedDeepLink
    case emptyItemID
    case conflictingItemID(deepLinkItemID: String, itemID: String)
}

enum NotificationArticleTargetResolution: Equatable {
    case target(NotificationArticleTarget)
    case rejected(NotificationArticleTargetRejectionReason)
    case ignored
}

struct NotificationArticleTargetParser {
    func resolve(userInfo: [AnyHashable: Any]) -> NotificationArticleTargetResolution {
        let payload = notificationData(from: userInfo)
        let deepLinkValue = stringValue(for: "deep_link", in: payload)
        let itemIDValue = stringValue(for: "item_id", in: payload)

        guard deepLinkValue != nil || itemIDValue != nil else {
            return .ignored
        }

        let fallbackItemID = itemIDValue?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let fallbackItemID, fallbackItemID.isEmpty {
            return .rejected(.emptyItemID)
        }

        if let deepLinkValue {
            switch itemID(fromDeepLink: deepLinkValue) {
            case let .success(deepLinkItemID):
                if let fallbackItemID, fallbackItemID != deepLinkItemID {
                    return .rejected(
                        .conflictingItemID(
                            deepLinkItemID: deepLinkItemID,
                            itemID: fallbackItemID
                        )
                    )
                }
                return .target(NotificationArticleTarget(itemID: deepLinkItemID))

            case let .failure(reason):
                return .rejected(reason)
            }
        }

        guard let fallbackItemID else {
            return .ignored
        }

        return .target(NotificationArticleTarget(itemID: fallbackItemID))
    }

    private func notificationData(from userInfo: [AnyHashable: Any]) -> [String: Any] {
        if let data = userInfo["data"] as? [String: Any] {
            return data
        }

        if let data = userInfo["data"] as? [AnyHashable: Any] {
            return stringKeyedDictionary(from: data)
        }

        return stringKeyedDictionary(from: userInfo)
    }

    private func stringKeyedDictionary(from source: [AnyHashable: Any]) -> [String: Any] {
        var result: [String: Any] = [:]
        for (key, value) in source {
            guard let key = key as? String else {
                continue
            }
            result[key] = value
        }
        return result
    }

    private func stringValue(for key: String, in payload: [String: Any]) -> String? {
        payload[key] as? String
    }

    private func itemID(fromDeepLink rawValue: String) -> Result<String, NotificationArticleTargetRejectionReason> {
        guard let url = URL(string: rawValue),
              url.scheme == "feedman",
              url.host == "items"
        else {
            return .failure(.unsupportedDeepLink)
        }

        let itemID = url.path
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .removingPercentEncoding?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard !itemID.isEmpty else {
            return .failure(.emptyItemID)
        }

        guard url.pathComponents.count == 2 else {
            return .failure(.unsupportedDeepLink)
        }

        return .success(itemID)
    }
}

@MainActor
final class NotificationArticleNavigationBridge {
    static let shared = NotificationArticleNavigationBridge()

    private var handler: (([AnyHashable: Any]) -> Void)?
    private var pendingUserInfos: [[AnyHashable: Any]] = []

    private init() {}

    func configure(handler: @escaping ([AnyHashable: Any]) -> Void) {
        self.handler = handler
        let pendingUserInfos = self.pendingUserInfos
        self.pendingUserInfos = []
        for userInfo in pendingUserInfos {
            handler(userInfo)
        }
    }

    func reset() {
        handler = nil
        pendingUserInfos = []
    }

    func handle(userInfo: [AnyHashable: Any]) {
        guard let handler else {
            pendingUserInfos.append(userInfo)
            return
        }

        handler(userInfo)
    }
}
