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

        let awaitedCalls1 = await repository.calls()

        XCTAssertEqual(awaitedCalls1, [])
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
        let awaitedCalls2 = await repository.calls()
        XCTAssertEqual(awaitedCalls2, [SearchRepositoryCall(query: "missing", scope: .global)])
    }

    func testFailureStateIsDistinctFromEmptyAndRetryUsesSameQuery() async {
        let repository = RecordingSearchRepository(result: .failure(SearchViewModelTestError.transport))
        let viewModel = makeViewModel(repository: repository)

        await viewModel.submitSearch("Swift")

        XCTAssertEqual(
            viewModel.state,
            .failed(query: "Swift", message: "検索結果を読み込めませんでした。", isAuthRequired: false)
        )
        XCTAssertEqual(viewModel.query, "Swift")

        await repository.setResult(.success([hit(id: "recovered")]))
        await viewModel.retry()

        let retriedCalls = await repository.calls()
        XCTAssertEqual(retriedCalls, [
            SearchRepositoryCall(query: "Swift", scope: .global),
            SearchRepositoryCall(query: "Swift", scope: .global)
        ])
        XCTAssertEqual(viewModel.query, "Swift")
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
        let awaitedCalls3 = await repository.calls()
        XCTAssertEqual(awaitedCalls3, [SearchRepositoryCall(query: "Swift", scope: .global)])
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

    func testResultDescriptorBuildsSafeDetailInputFromNullableHit() throws {
        let descriptor = SearchResultRowDescriptor(
            hit: hit(
                id: "nullable",
                faviconURL: nil,
                publishedAt: nil,
                isDateEstimated: nil,
                isRead: nil,
                isStarred: nil,
                hatebuCount: nil,
                author: nil
            )
        )

        let input = try XCTUnwrap(descriptor.detailInput)
        XCTAssertEqual(input.id, "nullable")
        XCTAssertEqual(input.summary?.feedTitle, "Feed nullable")
        XCTAssertNil(input.summary?.feedFaviconURL)
        XCTAssertEqual(input.summary?.title, "Title nullable")
        XCTAssertEqual(input.summary?.summary, "Summary nullable")
        XCTAssertEqual(input.summary?.link, "https://example.com/nullable")
        XCTAssertNil(input.summary?.publishedAt)
        XCTAssertNil(input.summary?.isDateEstimated)
        XCTAssertNil(input.summary?.isStarred)
        XCTAssertNil(input.summary?.hatebuCount)
        XCTAssertNil(input.summary?.hatebuFetchedAt)
        XCTAssertNil(input.summary?.author)
    }

    func testResultDescriptorSeparatesCardAndOpenLinkActions() throws {
        let descriptor = SearchResultRowDescriptor(hit: hit(id: "action"))
        var selectedInputs: [ArticleDetailSheetInput] = []
        var openRequests: [SearchResultOpenLinkRequest] = []

        descriptor.openLink { request in
            openRequests.append(request)
        }
        descriptor.select { input in
            selectedInputs.append(input)
        }

        XCTAssertEqual(selectedInputs.map(\.id), ["action"])
        XCTAssertEqual(openRequests, [
            SearchResultOpenLinkRequest(
                itemID: "action",
                url: try XCTUnwrap(URL(string: "https://example.com/action")),
                isRead: false,
                isStarred: false
            )
        ])
    }

    func testInvalidResultLinkDoesNotCreateOpenRequest() {
        let descriptor = SearchResultRowDescriptor(
            hit: hit(id: "invalid-link", link: "feedman://invalid-link")
        )
        var openRequestCount = 0

        descriptor.openLink { _ in
            openRequestCount += 1
        }

        XCTAssertNil(descriptor.linkURL)
        XCTAssertNil(descriptor.openLinkRequest)
        XCTAssertEqual(openRequestCount, 0)
    }

    func testApplyingItemStateChangeUpdatesVisibleSearchHitOnly() async {
        let viewModel = makeViewModel(
            repository: RecordingSearchRepository(result: .success([
                hit(id: "target", isRead: false, isStarred: false),
                hit(id: "other", isRead: false, isStarred: false)
            ]))
        )

        await viewModel.submitSearch("Swift")
        viewModel.applyItemStateChange(
            ItemStateChange(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000047")!,
                itemID: "target",
                isRead: true,
                isStarred: true
            )
        )

        guard case let .results(_, hits) = viewModel.state else {
            return XCTFail("Expected results state")
        }

        XCTAssertEqual(hits.first(where: { $0.id == "target" })?.isRead, true)
        XCTAssertEqual(hits.first(where: { $0.id == "target" })?.isStarred, true)
        XCTAssertEqual(hits.first(where: { $0.id == "other" })?.isRead, false)
        XCTAssertEqual(hits.first(where: { $0.id == "other" })?.isStarred, false)
    }

    func testSelectedDetailFailureDoesNotClearSearchResults() async throws {
        let searchHit = hit(id: "target", isRead: false, isStarred: false)
        let searchRepository = RecordingSearchRepository(result: .success([searchHit]))
        let searchViewModel = makeViewModel(repository: searchRepository)

        await searchViewModel.submitSearch("Swift")

        let input = try XCTUnwrap(SearchResultRowDescriptor(hit: searchHit).detailInput)
        let detailViewModel = ArticleDetailViewModel(
            itemID: input.id,
            summary: input.summary,
            repository: ArticleDetailFailureRepository(),
            accessToken: "test-access-token"
        )

        await detailViewModel.open()

        XCTAssertEqual(
            detailViewModel.state,
            .failed(message: "記事詳細を読み込めませんでした。", isAuthRequired: false)
        )
        XCTAssertEqual(searchViewModel.query, "Swift")
        XCTAssertEqual(searchViewModel.state, .results(query: "Swift", hits: [searchHit]))
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
        isDateEstimated: Bool? = false,
        isRead: Bool? = false,
        isStarred: Bool? = false,
        hatebuCount: Int? = nil,
        author: String? = nil,
        link: String? = nil
    ) -> ItemSearchHit {
        ItemSearchHit(
            id: id,
            feedID: "feed-\(id)",
            feedTitle: "Feed \(id)",
            faviconURL: faviconURL,
            title: "Title \(id)",
            summary: "Summary \(id)",
            link: link ?? "https://example.com/\(id)",
            publishedAt: publishedAt,
            isDateEstimated: isDateEstimated,
            isRead: isRead,
            isStarred: isStarred,
            hatebuCount: hatebuCount,
            author: author
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

private struct ArticleDetailFailureRepository: ItemRepository {
    func itemDetail(id: String, accessToken: String) async throws -> ItemDetail {
        throw SearchViewModelTestError.transport
    }

    func updateItemState(
        id: String,
        request: ItemStateUpdateRequest,
        accessToken: String
    ) async throws {}
}
