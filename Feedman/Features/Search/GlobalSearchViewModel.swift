import Combine
import Foundation

enum GlobalSearchViewState: Equatable {
    case suggestions
    case loading(query: String)
    case results(query: String, hits: [ItemSearchHit])
    case empty(query: String)
    case failed(query: String, message: String, isAuthRequired: Bool)

    var activeQuery: String? {
        switch self {
        case .suggestions:
            return nil
        case let .loading(query),
             let .results(query, _),
             let .empty(query),
             let .failed(query, _, _):
            return query
        }
    }
}

struct SearchResultRowDescriptor: Equatable {
    let hit: ItemSearchHit

    var itemID: String {
        hit.id
    }

    var title: String {
        hit.title
    }

    var summary: String? {
        hit.summary?.nilIfBlank
    }

    var sourceMetadata: ArticleSourceMetadata {
        ArticleSourceMetadata(
            feedTitle: hit.feedTitle,
            faviconURL: hit.faviconURL,
            relativeDate: publishedDateText
        )
    }

    var publishedDateText: String? {
        hit.publishedAt?.nilIfBlank
    }

    var isRead: Bool {
        hit.isRead ?? false
    }

    var isStarred: Bool {
        hit.isStarred ?? false
    }

    var isStarMutationEnabled: Bool {
        false
    }

    var hatebuState: ArticleHatebuCountState {
        .unavailable
    }

    var linkURL: URL? {
        Self.validHTTPURL(from: hit.link)
    }

    var detailInput: ArticleDetailSheetInput? {
        guard !hit.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        return ArticleDetailSheetInput(searchHit: hit)
    }

    var openLinkRequest: SearchResultOpenLinkRequest? {
        guard let linkURL,
              !hit.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return nil
        }

        return SearchResultOpenLinkRequest(
            itemID: hit.id,
            url: linkURL,
            isRead: hit.isRead,
            isStarred: hit.isStarred
        )
    }

    func select(_ action: (ArticleDetailSheetInput) -> Void) {
        guard let detailInput else {
            return
        }
        action(detailInput)
    }

    func openLink(_ action: (SearchResultOpenLinkRequest) -> Void) {
        guard let openLinkRequest else {
            return
        }
        action(openLinkRequest)
    }

    private static func validHTTPURL(from rawValue: String) -> URL? {
        guard let url = URL(string: rawValue),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              url.host != nil
        else {
            return nil
        }

        return url
    }
}

struct SearchResultOpenLinkRequest: Equatable {
    let itemID: String
    let url: URL
    let isRead: Bool?
    let isStarred: Bool?

    init(
        itemID: String,
        url: URL,
        isRead: Bool? = nil,
        isStarred: Bool? = nil
    ) {
        self.itemID = itemID
        self.url = url
        self.isRead = isRead
        self.isStarred = isStarred
    }
}

@MainActor
final class GlobalSearchViewModel: ObservableObject {
    static let suggestions = ["Swift", "iOS", "API"]

    @Published var query: String
    @Published private(set) var state: GlobalSearchViewState

    private let repository: any SearchRepository
    private let itemStateCoordinator: ItemStateCoordinator?
    private let onAuthRequired: () -> Void
    private var currentRequestID: UUID?
    private var activeSearchTask: Task<Result<[ItemSearchHit], Error>, Never>?
    private var cancellables: Set<AnyCancellable> = []

    init(
        query: String = "",
        state: GlobalSearchViewState = .suggestions,
        repository: any SearchRepository,
        itemStateCoordinator: ItemStateCoordinator? = nil,
        onAuthRequired: @escaping () -> Void = {}
    ) {
        self.query = query
        self.state = state
        self.repository = repository
        self.itemStateCoordinator = itemStateCoordinator
        self.onAuthRequired = onAuthRequired
        observeItemStateCoordinator()
    }

    deinit {
        activeSearchTask?.cancel()
    }

    func submitSearch() async {
        await submitSearch(query)
    }

    func submitSuggestion(_ suggestion: String) async {
        query = suggestion
        await submitSearch(suggestion)
    }

    func submitSearch(_ rawQuery: String) async {
        let submittedQuery = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        query = rawQuery

        guard !submittedQuery.isEmpty else {
            clearActiveSearch()
            state = .suggestions
            return
        }

        activeSearchTask?.cancel()
        let requestID = UUID()
        currentRequestID = requestID
        state = .loading(query: submittedQuery)

        let repository = repository
        let task = Task<Result<[ItemSearchHit], Error>, Never> {
            do {
                return .success(try await repository.searchItems(query: submittedQuery, scope: .global))
            } catch {
                return .failure(error)
            }
        }
        activeSearchTask = task

        let result = await task.value
        guard currentRequestID == requestID else {
            return
        }

        activeSearchTask = nil
        switch result {
        case .success(let hits):
            let effectiveHits = hits.map(effectiveHit(_:))
            state = effectiveHits.isEmpty ? .empty(query: submittedQuery) : .results(query: submittedQuery, hits: effectiveHits)
        case .failure(let error):
            applyFailure(error, query: submittedQuery)
        }
    }

    func clearQuery() {
        query = ""
        clearActiveSearch()
        state = .suggestions
    }

    func retry() async {
        guard let activeQuery = state.activeQuery else {
            return
        }
        await submitSearch(activeQuery)
    }

    func applyItemStateChange(_ change: ItemStateChange) {
        guard case let .results(query, hits) = state else {
            return
        }

        var didChange = false
        let updatedHits = hits.map { hit in
            guard hit.id == change.itemID else {
                return hit
            }

            didChange = true
            return hit.updating(isRead: change.isRead, isStarred: change.isStarred)
        }

        if didChange {
            state = .results(query: query, hits: updatedHits)
        }
    }

    private func observeItemStateCoordinator() {
        itemStateCoordinator?.objectWillChange
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.applyEffectiveStateToVisibleHits()
                }
            }
            .store(in: &cancellables)
    }

    private func applyEffectiveStateToVisibleHits() {
        guard case let .results(query, hits) = state else {
            return
        }

        state = .results(query: query, hits: hits.map(effectiveHit(_:)))
    }

    private func effectiveHit(_ hit: ItemSearchHit) -> ItemSearchHit {
        itemStateCoordinator?.effectiveSearchHit(hit) ?? hit
    }

    private func clearActiveSearch() {
        activeSearchTask?.cancel()
        activeSearchTask = nil
        currentRequestID = nil
    }

    private func applyFailure(_ error: Error, query: String) {
        if case FeedmanAPIError.authRequired = error {
            onAuthRequired()
            state = .failed(
                query: query,
                message: "認証の有効期限が切れました。もう一度ログインしてください。",
                isAuthRequired: true
            )
            return
        }

        state = .failed(
            query: query,
            message: "検索結果を読み込めませんでした。",
            isAuthRequired: false
        )
    }
}

private extension ItemSearchHit {
    func updating(isRead: Bool?, isStarred: Bool?) -> ItemSearchHit {
        ItemSearchHit(
            id: id,
            feedID: feedID,
            feedTitle: feedTitle,
            faviconURL: faviconURL,
            title: title,
            summary: summary,
            link: link,
            publishedAt: publishedAt,
            isDateEstimated: isDateEstimated,
            isRead: isRead ?? self.isRead,
            isStarred: isStarred ?? self.isStarred,
            hatebuCount: hatebuCount,
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
