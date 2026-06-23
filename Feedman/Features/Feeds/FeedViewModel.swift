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
    let isStarMutationPending: Bool
    private let fallbackFeedTitle: String?
    private let fallbackFaviconURL: String?

    init(
        item: ItemSummary,
        isStarMutationPending: Bool = false,
        now: Date = Date(),
        fallbackFeedTitle: String? = nil,
        fallbackFaviconURL: String? = nil
    ) {
        self.item = item
        self.isStarMutationPending = isStarMutationPending
        self.fallbackFeedTitle = fallbackFeedTitle
        self.fallbackFaviconURL = fallbackFaviconURL
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
            feedTitle: displayFeedTitle,
            faviconURL: item.feedFaviconURL ?? fallbackFaviconURL,
            relativeDate: relativeDate
        )
    }

    var opacity: Double {
        item.isRead ? 0.55 : 1
    }

    var isStarred: Bool {
        item.isStarred
    }

    var isStarControlEnabled: Bool {
        !isStarMutationPending
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
        [displayFeedTitle, item.title, relativeDate]
            .filter { !$0.isEmpty }
            .joined(separator: "、")
    }

    private var displayFeedTitle: String {
        item.feedTitle.nilIfBlank ?? fallbackFeedTitle?.nilIfBlank ?? ""
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
    @Published private(set) var starMutationErrorMessage: String?

    private struct Session: Equatable {
        let feedID: String
        let filter: FeedItemFilter
    }

    private var repository: (any FeedRepository)?
    private var itemRepository: (any ItemRepository)?
    private var accessToken: String?
    private var selectedFeedTitle: String?
    private var selectedFeedFaviconURL: String?
    private let itemStateCoordinator: ItemStateCoordinator
    private var isLoadingFirstPage = false
    private var loadingFirstPageSession: Session?
    private var pendingFirstPageSession: Session?
    private var cancellables: Set<AnyCancellable> = []

    init(
        repository: (any FeedRepository)? = nil,
        itemRepository: (any ItemRepository)? = nil,
        accessToken: String? = nil,
        itemStateCoordinator: ItemStateCoordinator? = nil,
        state: FeedViewState = .idle,
        items: [ItemSummary] = [],
        canLoadMore: Bool = false,
        currentFeedID: String? = nil,
        filter: FeedItemFilter = .all
    ) {
        self.repository = repository
        self.itemRepository = itemRepository
        self.accessToken = accessToken
        self.selectedFeedTitle = nil
        self.selectedFeedFaviconURL = nil
        self.itemStateCoordinator = itemStateCoordinator ?? ItemStateCoordinator()
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
        starMutationErrorMessage = nil
        observeItemStateCoordinator()
    }

    func configure(
        repository: any FeedRepository,
        itemRepository: (any ItemRepository)? = nil,
        accessToken: String? = nil,
        selectedFeed: Feed? = nil
    ) {
        if self.repository == nil {
            self.repository = repository
        }
        if let itemRepository {
            self.itemRepository = itemRepository
        }
        self.accessToken = accessToken
        if let selectedFeed {
            selectedFeedTitle = selectedFeed.title
            selectedFeedFaviconURL = selectedFeed.faviconURL
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

    func detailInput(for id: String) -> ArticleDetailSheetInput {
        guard let item = items.first(where: { $0.id == id }) else {
            return ArticleDetailSheetInput(id: id)
        }

        let effectiveItem = itemStateCoordinator.effectiveSummary(item)
        return ArticleDetailSheetInput(
            id: id,
            summary: ArticleDetailSummary(
                item: effectiveItem,
                fallbackFeedTitle: selectedFeedTitle,
                fallbackFaviconURL: selectedFeedFaviconURL
            )
        )
    }

    func toggleStar(id: String) async {
        guard let item = items.first(where: { $0.id == id }) else {
            return
        }

        let snapshot = itemStateCoordinator.effectiveState(
            itemID: item.id,
            baseRead: item.isRead,
            baseStarred: item.isStarred
        )
        let targetValue = !snapshot.isStarred
        guard let token = itemStateCoordinator.beginMutation(
            itemID: item.id,
            baseRead: item.isRead,
            baseStarred: item.isStarred,
            isStarred: targetValue
        ) else {
            return
        }

        starMutationErrorMessage = nil

        guard let itemRepository,
              let accessToken = validatedAccessToken()
        else {
            itemStateCoordinator.rollbackMutation(token)
            starMutationErrorMessage = "スターを更新できませんでした。"
            return
        }

        do {
            try await itemRepository.updateItemState(
                id: item.id,
                request: ItemStateUpdateRequest(isRead: nil, isStarred: targetValue),
                accessToken: accessToken
            )
            itemStateCoordinator.commitMutation(token)
        } catch {
            itemStateCoordinator.rollbackMutation(token)
            starMutationErrorMessage = "スターを更新できませんでした。"
        }
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
        FeedItemCardDescriptor(
            item: itemStateCoordinator.effectiveSummary(item),
            isStarMutationPending: itemStateCoordinator.isPending(itemID: item.id, field: .starred),
            now: now,
            fallbackFeedTitle: selectedFeedTitle,
            fallbackFaviconURL: selectedFeedFaviconURL
        )
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
        items = snapshot.items
        canLoadMore = snapshot.canLoadMore
        state = items.isEmpty ? .empty : .loaded
    }

    private func observeItemStateCoordinator() {
        itemStateCoordinator.objectWillChange
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.objectWillChange.send()
                }
            }
            .store(in: &cancellables)
    }

    private func validatedAccessToken() -> String? {
        guard let accessToken = accessToken?.trimmingCharacters(in: .whitespacesAndNewlines),
              !accessToken.isEmpty
        else {
            return nil
        }
        return accessToken
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

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
