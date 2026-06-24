import Combine
import Foundation

enum AppShellDrawerFeedSectionState: Equatable {
    case loading(feeds: [Feed])
    case loaded(feeds: [Feed])
    case empty
    case failed(message: String, feeds: [Feed])

    var feeds: [Feed] {
        switch self {
        case let .loading(feeds),
             let .loaded(feeds),
             let .failed(_, feeds):
            return feeds
        case .empty:
            return []
        }
    }
}

@MainActor
final class AppShellDrawerFeedViewModel: ObservableObject {
    @Published private(set) var sectionState: AppShellDrawerFeedSectionState

    private var loadGeneration = 0

    init(sectionState: AppShellDrawerFeedSectionState = .loading(feeds: [])) {
        self.sectionState = sectionState
    }

    func loadSubscriptions(repository: FeedRepository) async {
        loadGeneration += 1
        let generation = loadGeneration
        let currentFeeds = sectionState.feeds
        sectionState = .loading(feeds: currentFeeds)

        do {
            let feeds = try await repository.subscriptions()
            guard generation == loadGeneration else {
                return
            }
            sectionState = feeds.isEmpty ? .empty : .loaded(feeds: feeds)
        } catch {
            guard generation == loadGeneration else {
                return
            }
            sectionState = .failed(message: "フィードを読み込めませんでした", feeds: currentFeeds)
        }
    }

    func refreshSubscriptionsAfterFeedRegistration(
        _ registeredFeed: RegisteredFeed,
        repository: FeedRepository
    ) async {
        loadGeneration += 1
        let generation = loadGeneration
        let optimisticFeeds = feedsByUpsertingRegisteredFeed(registeredFeed, into: sectionState.feeds)
        sectionState = .loading(feeds: optimisticFeeds)

        do {
            let feeds = try await repository.subscriptions()
            guard generation == loadGeneration else {
                return
            }
            sectionState = feeds.isEmpty ? .empty : .loaded(feeds: feeds)
        } catch {
            guard generation == loadGeneration else {
                return
            }
            sectionState = .failed(
                message: "フィードは登録されましたが、一覧を更新できませんでした",
                feeds: optimisticFeeds
            )
        }
    }

    func applyRegisteredFeed(_ registeredFeed: RegisteredFeed) {
        sectionState = .loaded(feeds: feedsByUpsertingRegisteredFeed(registeredFeed, into: sectionState.feeds))
    }

    func applySubscriptionSettings(subscriptionID: String, fetchIntervalMinutes: Int) {
        replaceFeed(subscriptionID: subscriptionID) { feed in
            feed.updating(fetchIntervalMinutes: fetchIntervalMinutes)
        }
    }

    func applySubscriptionResume(subscriptionID: String) {
        replaceFeed(subscriptionID: subscriptionID) { feed in
            feed.updating(status: .active)
        }
    }

    @discardableResult
    func removeSubscription(subscriptionID: String) -> Feed? {
        var feeds = sectionState.feeds
        guard let index = feeds.firstIndex(where: { $0.subscriptionID == subscriptionID }) else {
            return nil
        }

        let removedFeed = feeds.remove(at: index)
        sectionState = feeds.isEmpty ? .empty : .loaded(feeds: feeds)
        return removedFeed
    }

    func route(for feed: Feed) -> AppShellRoute {
        .feed(id: feed.id, title: feed.title)
    }

    private func replaceFeed(subscriptionID: String, transform: (Feed) -> Feed) {
        var feeds = sectionState.feeds
        guard let index = feeds.firstIndex(where: { $0.subscriptionID == subscriptionID }) else {
            return
        }

        feeds[index] = transform(feeds[index])
        sectionState = .loaded(feeds: feeds)
    }

    private func feedsByUpsertingRegisteredFeed(_ registeredFeed: RegisteredFeed, into feeds: [Feed]) -> [Feed] {
        var updatedFeeds = feeds
        guard let drawerFeed = registeredFeed.drawerFeed else {
            return updatedFeeds
        }

        if let index = updatedFeeds.firstIndex(where: { $0.id == drawerFeed.id }) {
            updatedFeeds[index] = drawerFeed
        } else {
            updatedFeeds.append(drawerFeed)
        }

        return updatedFeeds
    }
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
