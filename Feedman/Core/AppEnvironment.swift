import Foundation

@MainActor
final class AppEnvironment: ObservableObject {
    let feedRepository: FeedRepository

    init(feedRepository: FeedRepository) {
        self.feedRepository = feedRepository
    }

    static let preview = AppEnvironment(feedRepository: MockFeedRepository())
}

