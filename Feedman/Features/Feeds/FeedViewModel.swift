import Combine
import Foundation

enum FeedViewState: Equatable {
    case idle
    case loading
    case loaded
    case empty
    case failed(message: String)
}

struct FeedStatusBannerDescriptor: Equatable {
    let message: String
    let style: FeedmanToast.Style
    let actionLabel: String

    init?(status: FeedStatus) {
        switch status {
        case .active:
            return nil
        case .stopped(let message):
            self.message = message.nilIfBlank ?? "フィードの取得が停止しています"
            style = .warning
        case .error(let message):
            self.message = message.nilIfBlank ?? "フィードの取得に失敗しています"
            style = .error
        }

        actionLabel = "再開"
    }
}

struct FeedRefreshFeedbackDescriptor: Equatable {
    let message: String
    let style: FeedmanToast.Style
}

struct FeedItemCardDescriptor: Equatable {
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

    var title: String {
        item.title
    }

    var summary: String? {
        item.summary?.nilIfBlank
    }

    var sourceMetadata: ArticleSourceMetadata {
        ArticleSourceMetadata(
            feedTitle: item.feedTitle,
            faviconURL: item.feedFaviconURL,
            relativeDate: relativeDate
        )
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
final class FeedViewModel: ObservableObject {
    @Published private(set) var state: FeedViewState
    @Published private(set) var items: [ItemSummary]
    @Published private(set) var canLoadMore: Bool
    @Published private(set) var isLoadingNextPage: Bool
    @Published private(set) var nextPageErrorMessage: String?
    @Published private(set) var selectedItemID: String?
    @Published private(set) var requestedResumeFeedID: String?
    @Published private(set) var currentFeedID: String?
    @Published private(set) var filter: FeedItemFilter
    @Published private(set) var isRefreshing: Bool
    @Published private(set) var refreshFeedback: FeedRefreshFeedbackDescriptor?

    private struct Session: Equatable {
        let feedID: String
        let filter: FeedItemFilter
    }

    private var repository: (any FeedRepository)?
    private var isLoadingFirstPage = false
    private var loadingFirstPageSession: Session?
    private var pendingFirstPageSession: Session?
    private var localStarOverrides: [String: Bool] = [:]

    init(
        repository: (any FeedRepository)? = nil,
        state: FeedViewState = .idle,
        items: [ItemSummary] = [],
        canLoadMore: Bool = false,
        currentFeedID: String? = nil,
        filter: FeedItemFilter = .all
    ) {
        self.repository = repository
        self.state = state
        self.items = items
        self.canLoadMore = canLoadMore
        self.currentFeedID = currentFeedID
        self.filter = filter
        isLoadingNextPage = false
        nextPageErrorMessage = nil
        selectedItemID = nil
        requestedResumeFeedID = nil
        isRefreshing = false
        refreshFeedback = nil
    }

    func configure(repository: any FeedRepository) {
        if self.repository == nil {
            self.repository = repository
        }
    }

    func loadInitialIfNeeded(feedID: String) async {
        if currentFeedID != nil, currentFeedID != feedID {
            filter = .all
        }

        if currentFeedID == feedID, state != .idle {
            return
        }

        await loadFirstPage(feedID: feedID, filter: filter)
    }

    func retryInitialLoad(feedID: String) async {
        await loadFirstPage(feedID: feedID, filter: filter)
    }

    func selectFilter(_ newFilter: FeedItemFilter, feedID: String) async {
        guard currentFeedID != feedID || filter != newFilter || state == .idle else {
            return
        }

        await loadFirstPage(feedID: feedID, filter: newFilter)
    }

    func loadNextPageIfNeeded(currentItemID: String? = nil) async {
        guard canLoadMore, !isLoadingFirstPage, !isLoadingNextPage, !isRefreshing else {
            return
        }

        if let currentItemID, !isPaginationTriggerItem(id: currentItemID) {
            return
        }

        guard let repository else {
            applyNextPageFailure()
            return
        }

        let expectedSession = currentSession
        isLoadingNextPage = true
        nextPageErrorMessage = nil

        do {
            let snapshot = try await repository.loadFeedItemsNextPage()
            if currentSession == expectedSession,
               expectedSession == Session(feedID: snapshot.feedID, filter: snapshot.filter) {
                apply(snapshot: snapshot)
            }
        } catch {
            if currentSession == expectedSession {
                applyNextPageFailure()
            }
        }

        isLoadingNextPage = false

        if let pendingFirstPageSession {
            self.pendingFirstPageSession = nil
            await loadFirstPage(
                feedID: pendingFirstPageSession.feedID,
                filter: pendingFirstPageSession.filter
            )
        }
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

    func requestResume(feedID: String) {
        requestedResumeFeedID = feedID
    }

    func statusBanner(for status: FeedStatus) -> FeedStatusBannerDescriptor? {
        FeedStatusBannerDescriptor(status: status)
    }

    func refreshFeed(feedID: String, subscriptionID: String?) async {
        guard !isRefreshing else {
            return
        }

        guard !isLoadingFirstPage, !isLoadingNextPage else {
            refreshFeedback = FeedRefreshFeedbackDescriptor(
                message: "記事の読み込みが終わってからもう一度お試しください。",
                style: .warning
            )
            return
        }

        guard let repository else {
            refreshFeedback = Self.refreshFailureFeedback(for: FeedViewModelError.repositoryUnavailable)
            return
        }

        guard let manualFetchSubscriptionID = subscriptionID?.nilIfBlank else {
            refreshFeedback = FeedRefreshFeedbackDescriptor(
                message: "このフィードは手動更新に必要な購読情報がありません。",
                style: .warning
            )
            return
        }

        let expectedSession = Session(feedID: feedID, filter: filter)
        isRefreshing = true
        refreshFeedback = nil
        defer {
            isRefreshing = false
        }

        do {
            try await repository.manualFetchSubscription(subscriptionID: manualFetchSubscriptionID)
        } catch {
            if currentSession == expectedSession || currentSession == nil {
                refreshFeedback = Self.refreshFailureFeedback(for: error)
            }
            return
        }

        guard currentSession == expectedSession || currentSession == nil else {
            return
        }

        do {
            let snapshot = try await repository.loadFeedItemsFirstPage(
                feedID: expectedSession.feedID,
                filter: expectedSession.filter,
                limit: nil
            )
            if currentSession == expectedSession || currentSession == nil {
                refreshFeedback = nil
                apply(snapshot: snapshot)
            }
        } catch {
            if currentSession == expectedSession || currentSession == nil {
                refreshFeedback = FeedRefreshFeedbackDescriptor(
                    message: "手動取得は完了しましたが、記事一覧を再読み込みできませんでした。もう一度お試しください。",
                    style: .warning
                )
            }
        }
    }

    func descriptor(for item: ItemSummary, now: Date = Date()) -> FeedItemCardDescriptor {
        FeedItemCardDescriptor(item: item, now: now)
    }

    func visibleState(for feedID: String) -> FeedViewState {
        guard currentFeedID == feedID else {
            return .loading
        }

        return state
    }

    var emptySubtitle: String {
        switch filter {
        case .all:
            return "条件を変えるか、時間をおいて確認してください。"
        case .unread:
            return "未読の記事はありません。フィルターを切り替えると既読の記事も確認できます。"
        case .starred:
            return "スター付きの記事はありません。フィルターを切り替えると他の記事を確認できます。"
        }
    }

    private var currentSession: Session? {
        guard let currentFeedID else {
            return nil
        }
        return Session(feedID: currentFeedID, filter: filter)
    }

    private func loadFirstPage(feedID: String, filter: FeedItemFilter) async {
        let session = Session(feedID: feedID, filter: filter)

        if isLoadingFirstPage {
            guard loadingFirstPageSession != session else {
                return
            }

            preparePendingFirstPage(session)
            return
        }

        if isLoadingNextPage {
            preparePendingFirstPage(session)
            return
        }

        guard let repository else {
            currentFeedID = feedID
            self.filter = filter
            applyFirstPageFailure()
            return
        }

        isLoadingFirstPage = true
        loadingFirstPageSession = session
        pendingFirstPageSession = nil
        currentFeedID = feedID
        self.filter = filter
        items = []
        canLoadMore = false
        nextPageErrorMessage = nil
        refreshFeedback = nil
        state = .loading

        do {
            let snapshot = try await repository.loadFeedItemsFirstPage(
                feedID: feedID,
                filter: filter,
                limit: nil
            )
            if currentSession == Session(feedID: snapshot.feedID, filter: snapshot.filter) {
                apply(snapshot: snapshot)
            }
        } catch {
            if currentSession == session {
                applyFirstPageFailure()
            }
        }

        isLoadingFirstPage = false
        loadingFirstPageSession = nil

        if let pendingFirstPageSession {
            self.pendingFirstPageSession = nil
            await loadFirstPage(
                feedID: pendingFirstPageSession.feedID,
                filter: pendingFirstPageSession.filter
            )
        }
    }

    private func apply(snapshot: FeedItemPaginationSnapshot) {
        currentFeedID = snapshot.feedID
        filter = snapshot.filter
        items = snapshot.items.map { item in
            guard let isStarred = localStarOverrides[item.id] else {
                return item
            }
            return item.updatingStarredState(isStarred)
        }
        canLoadMore = snapshot.canLoadMore
        state = items.isEmpty ? .empty : .loaded
    }

    private func preparePendingFirstPage(_ session: Session) {
        currentFeedID = session.feedID
        filter = session.filter
        items = []
        canLoadMore = false
        nextPageErrorMessage = nil
        state = .loading
        pendingFirstPageSession = session
    }

    private func applyFirstPageFailure() {
        items = []
        canLoadMore = false
        state = .failed(message: "フィードの記事を読み込めませんでした。")
    }

    private func applyNextPageFailure() {
        nextPageErrorMessage = "続きを読み込めませんでした。"
    }

    private static func refreshFailureFeedback(for error: Error) -> FeedRefreshFeedbackDescriptor {
        if case let FeedmanAPIError.feedmanError(context) = error,
           context.statusCode == 429,
           context.code == "FEED_COOLDOWN" {
            return FeedRefreshFeedbackDescriptor(
                message: cooldownMessage(retryAfterSeconds: context.presentationRetryAfterSeconds),
                style: .warning
            )
        }

        if case FeedmanAPIError.authRequired = error {
            return FeedRefreshFeedbackDescriptor(
                message: "ログイン状態を確認してからもう一度お試しください。",
                style: .warning
            )
        }

        if case FeedmanAPIError.transportFailed = error {
            return FeedRefreshFeedbackDescriptor(
                message: "通信できませんでした。ネットワーク接続を確認してからもう一度お試しください。",
                style: .warning
            )
        }

        return FeedRefreshFeedbackDescriptor(
            message: "フィードを更新できませんでした。しばらく待ってからもう一度お試しください。",
            style: .warning
        )
    }

    private static func cooldownMessage(retryAfterSeconds: Int?) -> String {
        guard let retryAfterSeconds else {
            return "このフィードは取得間隔の制限中です。しばらく待ってからもう一度お試しください。"
        }

        return "このフィードは取得間隔の制限中です。約 \(retryAfterSeconds) 秒後にもう一度お試しください。"
    }

    private func isPaginationTriggerItem(id: String) -> Bool {
        let triggerIDs = items.suffix(5).map(\.id)
        return triggerIDs.contains(id)
    }
}

private enum FeedViewModelError: Error {
    case repositoryUnavailable
}

private extension FeedmanErrorContext {
    var presentationRetryAfterSeconds: Int? {
        retryAfterSeconds ?? retryAfter.flatMap(Int.init)
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

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
