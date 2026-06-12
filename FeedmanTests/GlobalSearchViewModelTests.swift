import XCTest
@testable import Feedman

@MainActor
final class GlobalSearchViewModelTests: XCTestCase {
    func testInitialStateShowsSuggestions() {
        let viewModel = makeViewModel()

        XCTAssertEqual(viewModel.query, "")
        XCTAssertEqual(viewModel.state, .suggestions)
    }

    func testEmptyAndWhitespaceQueriesDoNotCallRepository() async {
        let repository = RecordingSearchRepository(result: .success([hit(id: "ignored")]))
        let viewModel = makeViewModel(repository: repository)

        await viewModel.submitSearch("")
        await viewModel.submitSearch("   \n\t")

        XCTAssertEqual(await repository.calls(), [])
        XCTAssertEqual(viewModel.state, .suggestions)
    }

    func testNonEmptySearchShowsLoadingThenResultsInAPIOrder() async {
        let repository = PendingSearchRepository()
        let viewModel = makeViewModel(repository: repository)

        let task = Task {
            await viewModel.submitSearch("Swift")
        }
        await waitUntil {
            await repository.queries() == ["Swift"]
        }

        XCTAssertEqual(viewModel.state, .loading(query: "Swift"))

        await repository.succeed(query: "Swift", hits: [
            hit(id: "first"),
            hit(id: "second")
        ])
        await task.value

        XCTAssertEqual(
            viewModel.state,
            .results(query: "Swift", hits: [hit(id: "first"), hit(id: "second")])
        )
    }

    func testZeroResultSearchShowsEmptyStateForSubmittedQuery() async {
        let repository = RecordingSearchRepository(result: .success([]))
        let viewModel = makeViewModel(repository: repository)

        await viewModel.submitSearch("missing")

        XCTAssertEqual(viewModel.state, .empty(query: "missing"))
        XCTAssertEqual(await repository.calls(), [SearchRepositoryCall(query: "missing", scope: .global)])
    }

    func testFailureStateIsDistinctFromEmptyAndRetryUsesSameQuery() async {
        let repository = RecordingSearchRepository(result: .failure(SearchViewModelTestError.transport))
        let viewModel = makeViewModel(repository: repository)

        await viewModel.submitSearch("Swift")

        XCTAssertEqual(
            viewModel.state,
            .failed(query: "Swift", message: "検索結果を読み込めませんでした。", isAuthRequired: false)
        )

        await repository.setResult(.success([hit(id: "recovered")]))
        await viewModel.retry()

        XCTAssertEqual(await repository.calls(), [
            SearchRepositoryCall(query: "Swift", scope: .global),
            SearchRepositoryCall(query: "Swift", scope: .global)
        ])
        XCTAssertEqual(viewModel.state, .results(query: "Swift", hits: [hit(id: "recovered")]))
    }

    func testAuthRequiredFailureCallsBoundaryAndDoesNotShowEmptyResult() async {
        let error = FeedmanAPIError.authRequired(
            AuthRequiredContext(
                reason: .missingRefreshHook,
                statusCode: 401,
                underlyingError: nil
            )
        )
        let repository = RecordingSearchRepository(result: .failure(error))
        var authRequiredCount = 0
        let viewModel = makeViewModel(repository: repository) {
            authRequiredCount += 1
        }

        await viewModel.submitSearch("Swift")

        XCTAssertEqual(authRequiredCount, 1)
        XCTAssertEqual(
            viewModel.state,
            .failed(
                query: "Swift",
                message: "認証の有効期限が切れました。もう一度ログインしてください。",
                isAuthRequired: true
            )
        )
    }

    func testOlderResponseDoesNotOverwriteNewerSubmittedQuery() async {
        let repository = PendingSearchRepository()
        let viewModel = makeViewModel(repository: repository)

        let firstTask = Task {
            await viewModel.submitSearch("old")
        }
        await waitUntil {
            await repository.queries() == ["old"]
        }

        let secondTask = Task {
            await viewModel.submitSearch("new")
        }
        await waitUntil {
            await repository.queries() == ["old", "new"]
        }

        await repository.succeed(query: "old", hits: [hit(id: "old-hit")])
        await firstTask.value

        XCTAssertEqual(viewModel.state, .loading(query: "new"))

        await repository.succeed(query: "new", hits: [hit(id: "new-hit")])
        await secondTask.value

        XCTAssertEqual(viewModel.state, .results(query: "new", hits: [hit(id: "new-hit")]))
    }

    func testSuggestionSelectionSubmitsGlobalSearch() async {
        let repository = RecordingSearchRepository(result: .success([hit(id: "suggested")]))
        let viewModel = makeViewModel(repository: repository)

        await viewModel.submitSuggestion("Swift")

        XCTAssertEqual(viewModel.query, "Swift")
        XCTAssertEqual(await repository.calls(), [SearchRepositoryCall(query: "Swift", scope: .global)])
        XCTAssertEqual(viewModel.state, .results(query: "Swift", hits: [hit(id: "suggested")]))
    }

    func testResultDescriptorKeepsNullableMetadataSafe() {
        let dataFavicon = "data:image/png;base64,iVBORw0KGgo="
        let descriptor = SearchResultRowDescriptor(
            hit: hit(
                id: "nullable",
                faviconURL: dataFavicon,
                publishedAt: nil,
                hatebuCount: 99
            )
        )

        XCTAssertNil(descriptor.publishedDateText)
        XCTAssertEqual(descriptor.sourceMetadata.faviconURL, dataFavicon)
        XCTAssertEqual(descriptor.hatebuState, .unavailable)
        XCTAssertFalse(descriptor.isStarMutationEnabled)
    }

    func testResultDescriptorSeparatesCardAndOpenLinkActions() throws {
        let descriptor = SearchResultRowDescriptor(hit: hit(id: "action"))
        var selectedIDs: [String] = []
        var openedURLs: [URL] = []

        descriptor.openLink { url in
            openedURLs.append(url)
        }
        descriptor.select { id in
            selectedIDs.append(id)
        }

        XCTAssertEqual(selectedIDs, ["action"])
        XCTAssertEqual(openedURLs, [try XCTUnwrap(URL(string: "https://example.com/action"))])
    }

    private func makeViewModel(
        repository: any SearchRepository = RecordingSearchRepository(result: .success([])),
        onAuthRequired: @escaping () -> Void = {}
    ) -> GlobalSearchViewModel {
        GlobalSearchViewModel(
            repository: repository,
            onAuthRequired: onAuthRequired
        )
    }

    private func waitUntil(
        _ condition: @escaping () async -> Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        for _ in 0..<20 {
            if await condition() {
                return
            }
            await Task.yield()
        }

        XCTFail("Timed out waiting for condition", file: file, line: line)
    }

    private func hit(
        id: String,
        faviconURL: String? = nil,
        publishedAt: String? = "2026-06-08T08:30:00Z",
        hatebuCount: Int? = nil
    ) -> ItemSearchHit {
        ItemSearchHit(
            id: id,
            feedID: "feed-\(id)",
            feedTitle: "Feed \(id)",
            faviconURL: faviconURL,
            title: "Title \(id)",
            summary: "Summary \(id)",
            link: "https://example.com/\(id)",
            publishedAt: publishedAt,
            isDateEstimated: false,
            isRead: false,
            isStarred: false,
            hatebuCount: hatebuCount,
            author: nil
        )
    }
}

private enum SearchViewModelTestError: Error {
    case transport
}

private struct SearchRepositoryCall: Equatable {
    let query: String
    let scope: SearchScope
}

private actor RecordingSearchRepository: SearchRepository {
    private var recordedCalls: [SearchRepositoryCall] = []
    private var result: Result<[ItemSearchHit], Error>

    init(result: Result<[ItemSearchHit], Error>) {
        self.result = result
    }

    func setResult(_ result: Result<[ItemSearchHit], Error>) {
        self.result = result
    }

    func calls() -> [SearchRepositoryCall] {
        recordedCalls
    }

    func searchItems(query: String, scope: SearchScope) async throws -> [ItemSearchHit] {
        recordedCalls.append(SearchRepositoryCall(query: query, scope: scope))
        return try result.get()
    }
}

private actor PendingSearchRepository: SearchRepository {
    private var recordedCalls: [SearchRepositoryCall] = []
    private var continuations: [String: CheckedContinuation<[ItemSearchHit], Error>] = [:]

    func queries() -> [String] {
        recordedCalls.map(\.query)
    }

    func searchItems(query: String, scope: SearchScope) async throws -> [ItemSearchHit] {
        recordedCalls.append(SearchRepositoryCall(query: query, scope: scope))
        return try await withCheckedThrowingContinuation { continuation in
            continuations[query] = continuation
        }
    }

    func succeed(query: String, hits: [ItemSearchHit]) {
        continuations.removeValue(forKey: query)?.resume(returning: hits)
    }
}
