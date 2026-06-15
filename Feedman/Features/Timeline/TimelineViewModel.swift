import Combine
import Foundation

enum TimelineViewState: Equatable {
    case idle
    case loading
    case loaded
    case empty
    case failed(message: String)
}

struct TimelineCardDescriptor: Equatable {
    let item: ItemSummary
    let relativeDate: String

    init(
        item: ItemSummary,
        now: Date = Date()
    ) {
        self.item = item
        relativeDate = TimelineRelativeDateFormatter.string(
            from: item.publishedAt,
            isEstimated: item.isDateEstimated,
            now: now
        )
    }

    var id: String {
        item.id
    }

    var sourceMetadata: ArticleSourceMetadata {
        ArticleSourceMetadata(
            feedTitle: item.feedTitle,
            faviconURL: item.feedFaviconURL,
            relativeDate: relativeDate
        )
    }

    var title: String {
        item.title
    }

    var summary: String? {
        item.summary?.nilIfBlank
    }

    var opacity: Double {
        item.isRead ? 0.55 : 1
    }

    var isStarred: Bool {
        item.isStarred
    }

    var hatebuState: ArticleHatebuCountState {
        ArticleHatebuCountState(
            count: item.hatebuCount,
            isFetched: item.hatebuFetchedAt?.nilIfBlank != nil
        )
    }

    var linkURL: URL? {
        guard
            let url = URL(string: item.link),
            let scheme = url.scheme?.lowercased(),
            ["http", "https"].contains(scheme)
        else {
            return nil
        }

        return url
    }

    var accessibilityLabel: String {
        [item.feedTitle, item.title, relativeDate]
            .filter { !$0.isEmpty }
            .joined(separator: "、")
    }

    func select(_ action: (String) -> Void) {
        action(item.id)
    }

    func toggleStar(_ action: (String) -> Void) {
        action(item.id)
    }

    func openLink(_ action: (URL) -> Void) {
        guard let linkURL else {
            return
        }
        action(linkURL)
    }
}

@MainActor
final class TimelineViewModel: ObservableObject {
    @Published private(set) var state: TimelineViewState
    @Published private(set) var items: [ItemSummary]
    @Published private(set) var canLoadMore: Bool
    @Published private(set) var isLoadingNextPage: Bool
    @Published private(set) var nextPageErrorMessage: String?
    @Published private(set) var refreshErrorMessage: String?
    @Published private(set) var selectedItemID: String?

    private var repository: (any FeedRepository)?
    private var isLoadingFirstPage = false
    private var localStarOverrides: [String: Bool] = [:]

    init(
        repository: (any FeedRepository)? = nil,
        state: TimelineViewState = .idle,
        items: [ItemSummary] = [],
        canLoadMore: Bool = false
    ) {
        self.repository = repository
        self.state = state
        self.items = items
        self.canLoadMore = canLoadMore
        isLoadingNextPage = false
        nextPageErrorMessage = nil
        refreshErrorMessage = nil
        selectedItemID = nil
    }

    func configure(repository: any FeedRepository) {
        if self.repository == nil {
            self.repository = repository
        }
    }

    func loadInitialIfNeeded() async {
        guard state == .idle else {
            return
        }

        await loadFirstPage(preservingExistingItems: false)
    }

    func retryInitialLoad() async {
        await loadFirstPage(preservingExistingItems: false)
    }

    func refresh() async {
        await loadFirstPage(preservingExistingItems: !items.isEmpty)
    }

    func loadNextPageIfNeeded(currentItemID: String? = nil) async {
        guard canLoadMore, !isLoadingFirstPage, !isLoadingNextPage else {
            return
        }

        if let currentItemID, !isPaginationTriggerItem(id: currentItemID) {
            return
        }

        guard let repository else {
            applyNextPageFailure()
            return
        }

        isLoadingNextPage = true
        nextPageErrorMessage = nil

        do {
            let snapshot = try await repository.loadCrossFeedNextPage()
            apply(snapshot: snapshot)
        } catch {
            applyNextPageFailure()
        }

        isLoadingNextPage = false
    }

    func retryNextPage() async {
        await loadNextPageIfNeeded()
    }

    func selectItem(id: String) {
        selectedItemID = id
    }

    func toggleStar(id: String) {
        guard let index = items.firstIndex(where: { $0.id == id }) else {
            return
        }

        let item = items[index]
        let isStarred = !item.isStarred
        localStarOverrides[id] = isStarred
        items[index] = item.updatingStarredState(isStarred)
    }

    func descriptor(for item: ItemSummary, now: Date = Date()) -> TimelineCardDescriptor {
        TimelineCardDescriptor(item: item, now: now)
    }

    private func loadFirstPage(preservingExistingItems: Bool) async {
        guard !isLoadingFirstPage, !isLoadingNextPage else {
            return
        }

        guard let repository else {
            applyFirstPageFailure(preservingExistingItems: preservingExistingItems)
            return
        }

        isLoadingFirstPage = true
        nextPageErrorMessage = nil
        refreshErrorMessage = nil
        if !preservingExistingItems {
            state = .loading
        }

        do {
            let snapshot = try await repository.loadCrossFeedFirstPage(limit: nil)
            apply(snapshot: snapshot)
        } catch {
            applyFirstPageFailure(preservingExistingItems: preservingExistingItems)
        }

        isLoadingFirstPage = false
    }

    private func apply(snapshot: CrossFeedPaginationSnapshot) {
        items = snapshot.items.map { item in
            guard let isStarred = localStarOverrides[item.id] else {
                return item
            }
            return item.updatingStarredState(isStarred)
        }
        canLoadMore = snapshot.canLoadMore
        state = items.isEmpty ? .empty : .loaded
    }

    private func applyFirstPageFailure(preservingExistingItems: Bool) {
        if preservingExistingItems, !items.isEmpty {
            refreshErrorMessage = "タイムラインを更新できませんでした。"
            state = .loaded
        } else {
            items = []
            canLoadMore = false
            state = .failed(message: "タイムラインを読み込めませんでした。")
        }
    }

    private func applyNextPageFailure() {
        nextPageErrorMessage = "続きを読み込めませんでした。"
    }

    private func isPaginationTriggerItem(id: String) -> Bool {
        let triggerIDs = items.suffix(5).map(\.id)
        return triggerIDs.contains(id)
    }
}

private extension ItemSummary {
    func updatingStarredState(_ isStarred: Bool) -> ItemSummary {
        ItemSummary(
            id: id,
            feedID: feedID,
            feedTitle: feedTitle,
            feedFaviconURL: feedFaviconURL,
            title: title,
            summary: summary,
            link: link,
            publishedAt: publishedAt,
            isDateEstimated: isDateEstimated,
            isRead: isRead,
            isStarred: isStarred,
            hatebuCount: hatebuCount,
            hatebuFetchedAt: hatebuFetchedAt,
            author: author
        )
    }
}

enum TimelineRelativeDateFormatter {
    static func string(
        from rfc3339String: String,
        isEstimated: Bool,
        now: Date = Date()
    ) -> String {
        guard let date = parseRFC3339(rfc3339String) else {
            return isEstimated ? "推定 \(rfc3339String)" : rfc3339String
        }

        let interval = max(0, Int(now.timeIntervalSince(date)))
        let text: String
        if interval < 60 {
            text = "たった今"
        } else if interval < 60 * 60 {
            text = "\(interval / 60)分前"
        } else if interval < 60 * 60 * 24 {
            text = "\(interval / 60 / 60)時間前"
        } else if interval < 60 * 60 * 24 * 7 {
            text = "\(interval / 60 / 60 / 24)日前"
        } else {
            text = absoluteDateString(from: date)
        }

        return isEstimated ? "推定 \(text)" : text
    }

    private static func parseRFC3339(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) {
            return date
        }

        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }

    private static func absoluteDateString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy/MM/dd"
        return formatter.string(from: date)
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
