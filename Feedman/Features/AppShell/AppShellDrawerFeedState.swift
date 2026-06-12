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

    init(sectionState: AppShellDrawerFeedSectionState = .loading(feeds: [])) {
        self.sectionState = sectionState
    }

    func loadSubscriptions(repository: FeedRepository) async {
        let currentFeeds = sectionState.feeds
        sectionState = .loading(feeds: currentFeeds)

        do {
            let feeds = try await repository.subscriptions()
            sectionState = feeds.isEmpty ? .empty : .loaded(feeds: feeds)
        } catch {
            sectionState = .failed(message: "フィードを読み込めませんでした", feeds: currentFeeds)
        }
    }

    func applyRegisteredFeed(_ registeredFeed: RegisteredFeed) {
        var feeds = sectionState.feeds
        let drawerFeed = registeredFeed.drawerFeed

        if let index = feeds.firstIndex(where: { $0.id == drawerFeed.id }) {
            feeds[index] = drawerFeed
        } else {
            feeds.append(drawerFeed)
        }

        sectionState = .loaded(feeds: feeds)
    }

    func route(for feed: Feed) -> AppShellRoute {
        .feed(id: feed.id, title: feed.title)
    }
}
