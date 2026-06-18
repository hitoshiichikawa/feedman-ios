import Combine
import Foundation

enum StarredViewState: Equatable {
    case idle
    case loading
    case loaded
    case empty
    case failed(message: String, isAuthRequired: Bool)
}

struct StarredItemCardDescriptor: Equatable {
    let item: ItemSummary
    let relativeDate: String
    let isStarMutationPending: Bool

    init(
        item: ItemSummary,
        isStarMutationPending: Bool = false,
        now: Date = Date()
    ) {
        self.item = item
        self.isStarMutationPending = isStarMutationPending
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
final class StarredViewModel: ObservableObject {
    @Published private(set) var state: StarredViewState
    @Published private(set) var items: [ItemSummary]
    @Published private(set) var canLoadMore: Bool
    @Published private(set) var isLoadingNextPage: Bool
    @Published private(set) var nextPageErrorMessage: String?
    @Published private(set) var refreshErrorMessage: String?
    @Published private(set) var starMutationErrorMessage: String?
    @Published private(set) var selectedItemID: String?

    private var repository: (any FeedRepository)?
    private var itemRepository: (any ItemRepository)?
    private var accessToken: String?
    private var onAuthRequired: () -> Void
    private let itemStateCoordinator: ItemStateCoordinator
    private var isLoadingFirstPage = false
    private var removedItemsByMutation: [String: RemovedItem] = [:]
    private var handledStateChangeID: UUID?
    private var cancellables: Set<AnyCancellable> = []

    private struct RemovedItem: Equatable {
        let item: ItemSummary
        let index: Int
    }

    init(
        repository: (any FeedRepository)? = nil,
        itemRepository: (any ItemRepository)? = nil,
        accessToken: String? = nil,
        itemStateCoordinator: ItemStateCoordinator? = nil,
        onAuthRequired: @escaping () -> Void = {},
        state: StarredViewState = .idle,
        items: [ItemSummary] = [],
        canLoadMore: Bool = false
    ) {
        self.repository = repository
        self.itemRepository = itemRepository
        self.accessToken = accessToken
        self.onAuthRequired = onAuthRequired
        self.itemStateCoordinator = itemStateCoordinator ?? ItemStateCoordinator()
        self.state = state
        self.items = items
        self.canLoadMore = canLoadMore
        isLoadingNextPage = false
        nextPageErrorMessage = nil
        refreshErrorMessage = nil
        starMutationErrorMessage = nil
        selectedItemID = nil
        observeItemStateCoordinator()
    }

    func configure(
        repository: any FeedRepository,
        itemRepository: (any ItemRepository)? = nil,
        accessToken: String? = nil,
        onAuthRequired: (() -> Void)? = nil
    ) {
        if self.repository == nil {
            self.repository = repository
        }
        if let itemRepository {
            self.itemRepository = itemRepository
        }
        self.accessToken = accessToken
        if let onAuthRequired {
            self.onAuthRequired = onAuthRequired
        }
    }

    func loadInitialIfNeeded() async {
        guard state == .idle, items.isEmpty else {
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
            let snapshot = try await repository.loadStarredItemsNextPage()
            apply(snapshot: snapshot)
        } catch {
            if !applyAuthRequiredFailureIfNeeded(error) {
                applyNextPageFailure()
            }
        }

        isLoadingNextPage = false
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
            summary: ArticleDetailSummary(item: effectiveItem)
        )
    }

    func handleItemStateChange(_ change: ItemStateChange?) {
        guard let change, handledStateChangeID != change.id else {
            return
        }

        handledStateChangeID = change.id
        itemStateCoordinator.confirmStateChange(change)

        if change.isStarred == false {
            removeVisibleItem(id: change.itemID)
        }
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
        let removedItem = targetValue ? nil : removeVisibleItem(id: item.id)

        guard let itemRepository,
              let accessToken = validatedAccessToken()
        else {
            restore(removedItem)
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
            if targetValue == false {
                removedItemsByMutation[item.id] = nil
            }
        } catch {
            restore(removedItem)
            itemStateCoordinator.rollbackMutation(token)
            starMutationErrorMessage = "スターを更新できませんでした。"
        }
    }

    func descriptor(for item: ItemSummary, now: Date = Date()) -> StarredItemCardDescriptor {
        StarredItemCardDescriptor(
            item: itemStateCoordinator.effectiveSummary(item),
            isStarMutationPending: itemStateCoordinator.isPending(itemID: item.id, field: .starred),
            now: now
        )
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
            let snapshot = try await repository.loadStarredItemsFirstPage(limit: nil)
            apply(snapshot: snapshot)
        } catch {
            applyFirstPageFailure(error, preservingExistingItems: preservingExistingItems)
        }

        isLoadingFirstPage = false
    }

    private func apply(snapshot: StarredItemPaginationSnapshot) {
        items = snapshot.items.filter { item in
            itemStateCoordinator.effectiveSummary(item).isStarred
        }
        canLoadMore = snapshot.canLoadMore
        state = items.isEmpty ? .empty : .loaded
    }

    @discardableResult
    private func removeVisibleItem(id: String) -> RemovedItem? {
        guard let index = items.firstIndex(where: { $0.id == id }) else {
            return nil
        }

        let removedItem = RemovedItem(item: items.remove(at: index), index: index)
        removedItemsByMutation[id] = removedItem
        if items.isEmpty {
            state = .empty
        }
        return removedItem
    }

    private func restore(_ removedItem: RemovedItem?) {
        guard let removedItem else {
            return
        }

        if !items.contains(where: { $0.id == removedItem.item.id }) {
            items.insert(removedItem.item, at: min(removedItem.index, items.count))
        }
        removedItemsByMutation[removedItem.item.id] = nil
        if !items.isEmpty {
            state = .loaded
        }
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

    private func applyFirstPageFailure(
        _ error: Error? = nil,
        preservingExistingItems: Bool
    ) {
        if let error, applyAuthRequiredFailureIfNeeded(error) {
            return
        }

        if preservingExistingItems, !items.isEmpty {
            refreshErrorMessage = "お気に入りを更新できませんでした。"
            state = .loaded
        } else {
            items = []
            canLoadMore = false
            state = .failed(message: "お気に入りを読み込めませんでした。", isAuthRequired: false)
        }
    }

    private func applyNextPageFailure() {
        nextPageErrorMessage = "続きを読み込めませんでした。"
    }

    private func applyAuthRequiredFailureIfNeeded(_ error: Error) -> Bool {
        guard case FeedmanAPIError.authRequired = error else {
            return false
        }

        onAuthRequired()
        refreshErrorMessage = nil
        nextPageErrorMessage = nil
        canLoadMore = false
        state = .failed(
            message: "認証の有効期限が切れました。もう一度ログインしてください。",
            isAuthRequired: true
        )
        return true
    }

    private func isPaginationTriggerItem(id: String) -> Bool {
        let triggerIDs = items.suffix(5).map(\.id)
        return triggerIDs.contains(id)
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
