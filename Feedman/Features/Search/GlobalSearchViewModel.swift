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
        URL(string: hit.link)
    }

    func select(_ action: (String) -> Void) {
        action(hit.id)
    }

    func openLink(_ action: (URL) -> Void) {
        guard let linkURL else {
            return
        }
        action(linkURL)
    }
}

@MainActor
final class GlobalSearchViewModel: ObservableObject {
    static let suggestions = ["Swift", "iOS", "API"]

    @Published var query: String
    @Published private(set) var state: GlobalSearchViewState

    private let repository: any SearchRepository
    private let onAuthRequired: () -> Void
    private var currentRequestID: UUID?
    private var activeSearchTask: Task<Result<[ItemSearchHit], Error>, Never>?

    init(
        query: String = "",
        state: GlobalSearchViewState = .suggestions,
        repository: any SearchRepository,
        onAuthRequired: @escaping () -> Void = {}
    ) {
        self.query = query
        self.state = state
        self.repository = repository
        self.onAuthRequired = onAuthRequired
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
            state = hits.isEmpty ? .empty(query: submittedQuery) : .results(query: submittedQuery, hits: hits)
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

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
