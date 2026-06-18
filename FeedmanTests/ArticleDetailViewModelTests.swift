import XCTest
@testable import Feedman

@MainActor
final class ArticleDetailViewModelTests: XCTestCase {
    func testOpenFetchesDetailAndMarksReadWithPartialRequest() async throws {
        let repository = ArticleDetailRecordingRepository(
            detailResults: [.success(makeDetail(isRead: false, isStarred: false))],
            stateUpdateResults: [.success(())]
        )
        var stateChanges: [ItemStateChange] = []
        let viewModel = makeViewModel(repository: repository, onItemStateChange: { change in
            stateChanges.append(change)
        })

        await viewModel.open()

        let detailCalls = await repository.detailCalls()
        let stateUpdateCalls = await repository.stateUpdateCalls()

        XCTAssertEqual(detailCalls, [
            ArticleDetailCall(itemID: "item-123", accessToken: "test-access-token")
        ])
        XCTAssertEqual(stateUpdateCalls, [
            ArticleDetailStateUpdateCall(
                itemID: "item-123",
                request: ItemStateUpdateRequest(isRead: true, isStarred: nil),
                accessToken: "test-access-token"
            )
        ])

        let presentation = try XCTUnwrap(viewModel.loadedPresentation)
        XCTAssertEqual(presentation.sourceMetadata.feedTitle, "Feed Title")
        XCTAssertEqual(presentation.title, "Article Title")
        XCTAssertEqual(presentation.authorText, "Author")
        XCTAssertEqual(presentation.preview.text, "本文 HTML")
        XCTAssertTrue(presentation.isRead)
        XCTAssertFalse(presentation.isStarred)
        XCTAssertNil(viewModel.mutationMessage)
        XCTAssertEqual(stateChanges.map(\.itemID), ["item-123"])
        XCTAssertEqual(stateChanges.map(\.isRead), [true])
        XCTAssertEqual(stateChanges.map(\.isStarred), [nil])
    }

    func testDetailOpenReadSuccessSyncsVisibleListState() async throws {
        let coordinator = ItemStateCoordinator()
        let repository = ArticleDetailRecordingRepository(
            detailResults: [.success(makeDetail(isRead: false, isStarred: false))],
            stateUpdateResults: [.success(())]
        )
        let viewModel = makeViewModel(
            repository: repository,
            itemStateCoordinator: coordinator
        )

        await viewModel.open()

        XCTAssertEqual(viewModel.loadedPresentation?.isRead, true)
        XCTAssertEqual(
            coordinator.effectiveSummary(makeSummaryItem(isRead: false, isStarred: false)).isRead,
            true
        )
        XCTAssertNil(viewModel.mutationMessage)
        let stateUpdateCalls = await repository.stateUpdateCalls()
        XCTAssertEqual(stateUpdateCalls.map(\.request), [
            ItemStateUpdateRequest(isRead: true, isStarred: nil)
        ])
    }

    func testDetailFailureShowsRecoverableStateAndRetryUsesSameItem() async throws {
        let repository = ArticleDetailRecordingRepository(
            detailResults: [
                .failure(ArticleDetailTestError.transport),
                .success(makeDetail(isRead: true, isStarred: true))
            ],
            stateUpdateResults: [.success(())]
        )
        let viewModel = makeViewModel(repository: repository)

        await viewModel.open()

        XCTAssertEqual(
            viewModel.state,
            .failed(message: "記事詳細を読み込めませんでした。", isAuthRequired: false)
        )

        await viewModel.retry()

        let detailCalls = await repository.detailCalls()
        XCTAssertEqual(detailCalls.map(\.itemID), ["item-123", "item-123"])
        XCTAssertEqual(viewModel.loadedPresentation?.isStarred, true)
    }

    func testOpenShowsSummaryLoadingWhileDetailRequestIsInFlight() async throws {
        let repository = PendingArticleDetailRepository()
        let viewModel = makeViewModel(
            repository: repository,
            summaryIsRead: true
        )

        let task = Task {
            await viewModel.open()
        }
        try await waitUntil {
            await repository.detailCalls().count == 1
        }

        guard case let .loading(summary) = viewModel.state else {
            return XCTFail("Expected summary loading state")
        }
        XCTAssertEqual(summary?.id, "item-123")
        XCTAssertEqual(summary?.title, "Summary Title")

        await repository.succeed(makeDetail(isRead: true, isStarred: false))
        await task.value

        XCTAssertEqual(viewModel.loadedPresentation?.title, "Article Title")
    }

    func testReadMarkingFailureDoesNotBlockLoadedDetail() async throws {
        let repository = ArticleDetailRecordingRepository(
            detailResults: [.success(makeDetail(isRead: false, isStarred: false))],
            stateUpdateResults: [.failure(ArticleDetailTestError.transport)]
        )
        let viewModel = makeViewModel(repository: repository)

        await viewModel.open()

        let presentation = try XCTUnwrap(viewModel.loadedPresentation)
        XCTAssertEqual(presentation.title, "Article Title")
        XCTAssertEqual(viewModel.state, .loaded(presentation))
        XCTAssertEqual(viewModel.mutationMessage?.kind, .read)
        XCTAssertEqual(viewModel.mutationMessage?.message, "既読状態を更新できませんでした。")
    }

    func testStarToggleSendsPartialStarRequestAndUpdatesSheetLocalState() async throws {
        let repository = ArticleDetailRecordingRepository(
            detailResults: [.success(makeDetail(isRead: true, isStarred: false))],
            stateUpdateResults: [.success(()), .success(())]
        )
        var stateChanges: [ItemStateChange] = []
        let viewModel = makeViewModel(repository: repository, onItemStateChange: { change in
            stateChanges.append(change)
        })

        await viewModel.open()
        await viewModel.toggleStar()

        let updates = await repository.stateUpdateCalls()
        XCTAssertEqual(updates.map(\.request), [
            ItemStateUpdateRequest(isRead: true, isStarred: nil),
            ItemStateUpdateRequest(isRead: nil, isStarred: true)
        ])
        XCTAssertEqual(viewModel.loadedPresentation?.isStarred, true)
        XCTAssertNil(viewModel.mutationMessage)
        XCTAssertEqual(stateChanges.map(\.itemID), ["item-123", "item-123"])
        XCTAssertEqual(stateChanges.map(\.isRead), [true, nil])
        XCTAssertEqual(stateChanges.map(\.isStarred), [nil, true])
    }

    func testStarFailureKeepsDeterministicFinalStateAndSurfacesMessage() async throws {
        let repository = ArticleDetailRecordingRepository(
            detailResults: [.success(makeDetail(isRead: true, isStarred: false))],
            stateUpdateResults: [.success(()), .failure(ArticleDetailTestError.transport)]
        )
        let viewModel = makeViewModel(repository: repository)

        await viewModel.open()
        await viewModel.toggleStar()

        XCTAssertEqual(viewModel.loadedPresentation?.isStarred, false)
        if case let .loaded(presentation) = viewModel.state {
            XCTAssertEqual(presentation.id, "item-123")
            XCTAssertFalse(presentation.isStarred)
        } else {
            XCTFail("Expected loaded state after star failure")
        }
        XCTAssertEqual(viewModel.mutationMessage?.kind, .star)
        XCTAssertEqual(viewModel.mutationMessage?.message, "スターを更新できませんでした。")
    }

    func testDetailStarSuccessUpdatesSharedCoordinatorForVisibleListCopy() async throws {
        let coordinator = ItemStateCoordinator()
        let repository = ArticleDetailRecordingRepository(
            detailResults: [.success(makeDetail(isRead: true, isStarred: false))],
            stateUpdateResults: [.success(())]
        )
        let viewModel = makeViewModel(
            repository: repository,
            summaryIsRead: true,
            itemStateCoordinator: coordinator
        )

        await viewModel.open()
        await viewModel.toggleStar()

        let listItem = makeSummaryItem(isRead: true, isStarred: false)
        let effectiveListItem = coordinator.effectiveSummary(listItem)
        XCTAssertTrue(effectiveListItem.isStarred)
        XCTAssertEqual(viewModel.loadedPresentation?.isStarred, true)
        let updates = await repository.stateUpdateCalls()
        XCTAssertEqual(updates.map(\.request), [
            ItemStateUpdateRequest(isRead: nil, isStarred: true)
        ])
    }

    func testCoordinatorStarChangeFromVisibleListUpdatesLoadedDetailPresentation() async throws {
        let coordinator = ItemStateCoordinator()
        let repository = ArticleDetailRecordingRepository(
            detailResults: [.success(makeDetail(isRead: true, isStarred: false))],
            stateUpdateResults: []
        )
        let viewModel = makeViewModel(
            repository: repository,
            summaryIsRead: true,
            itemStateCoordinator: coordinator
        )

        await viewModel.open()
        let token = try XCTUnwrap(coordinator.beginMutation(
            itemID: "item-123",
            baseRead: true,
            baseStarred: false,
            isStarred: true
        ))
        await Task.yield()

        XCTAssertEqual(viewModel.loadedPresentation?.isStarred, true)

        coordinator.commitMutation(token)
        await Task.yield()

        XCTAssertEqual(viewModel.loadedPresentation?.isStarred, true)
    }

    func testDetailStarFailureRollsBackSharedCoordinatorForVisibleListCopy() async throws {
        let coordinator = ItemStateCoordinator()
        let repository = ArticleDetailRecordingRepository(
            detailResults: [.success(makeDetail(isRead: true, isStarred: false))],
            stateUpdateResults: [.failure(ArticleDetailTestError.transport)]
        )
        let viewModel = makeViewModel(
            repository: repository,
            summaryIsRead: true,
            itemStateCoordinator: coordinator
        )

        await viewModel.open()
        await viewModel.toggleStar()

        let listItem = makeSummaryItem(isRead: true, isStarred: false)
        let effectiveListItem = coordinator.effectiveSummary(listItem)
        XCTAssertFalse(effectiveListItem.isStarred)
        XCTAssertEqual(viewModel.loadedPresentation?.isStarred, false)
        XCTAssertEqual(viewModel.mutationMessage?.kind, .star)
    }

    func testReadMarkingFailureRollsBackSharedCoordinatorForVisibleListCopy() async throws {
        let coordinator = ItemStateCoordinator()
        let repository = ArticleDetailRecordingRepository(
            detailResults: [.success(makeDetail(isRead: false, isStarred: false))],
            stateUpdateResults: [.failure(ArticleDetailTestError.transport)]
        )
        let viewModel = makeViewModel(
            repository: repository,
            itemStateCoordinator: coordinator
        )

        await viewModel.open()

        let listItem = makeSummaryItem(isRead: false, isStarred: false)
        let effectiveListItem = coordinator.effectiveSummary(listItem)
        XCTAssertFalse(effectiveListItem.isRead)
        XCTAssertEqual(viewModel.loadedPresentation?.isRead, false)
        XCTAssertEqual(viewModel.mutationMessage?.kind, .read)
    }

    func testContentPreviewUsesReadableHTMLText() {
        let preview = ArticleDetailContentPreview(
            contentHTML: "<p>Hello <strong>World</strong></p>",
            summary: nil
        )

        XCTAssertEqual(preview.text, "Hello World")
        XCTAssertEqual(preview.source, .content)
        XCTAssertFalse(preview.text.contains("<strong>"))
    }

    func testContentPreviewFallsBackToSummaryAndNeutralEmptyText() {
        let summaryPreview = ArticleDetailContentPreview(
            contentHTML: "   ",
            summary: " Summary text "
        )
        let emptyPreview = ArticleDetailContentPreview(
            contentHTML: nil,
            summary: nil
        )

        XCTAssertEqual(summaryPreview.text, "Summary text")
        XCTAssertEqual(summaryPreview.source, .summary)
        XCTAssertEqual(emptyPreview.text, "本文プレビューはありません。")
        XCTAssertEqual(emptyPreview.source, .empty)
    }

    func testContentPreviewKeepsLongContentAsReadableText() {
        let longBody = Array(repeating: "本文", count: 80).joined(separator: " ")
        let preview = ArticleDetailContentPreview(
            contentHTML: "<article><p>\(longBody)</p></article>",
            summary: nil
        )

        XCTAssertEqual(preview.source, .content)
        XCTAssertEqual(preview.text, longBody)
        XCTAssertTrue(preview.text.hasPrefix("本文 本文"))
        XCTAssertFalse(preview.text.contains("<article>"))
    }

    func testPresentationDisablesInvalidOriginalLink() {
        let presentation = ArticleDetailPresentation(
            detail: makeDetail(
                isRead: true,
                isStarred: false,
                link: "not-a-valid-absolute-url"
            )
        )

        XCTAssertNil(presentation.linkURL)
    }

    func testOpenOriginalWithValidHTTPURLReturnsRequestAndMarksRead() async throws {
        let repository = ArticleDetailRecordingRepository(
            detailResults: [],
            stateUpdateResults: [.success(())]
        )
        var stateChanges: [ItemStateChange] = []
        let viewModel = makeViewModel(
            summaryLink: "http://example.com/articles/123",
            repository: repository,
            onItemStateChange: { change in
                stateChanges.append(change)
            }
        )

        let openRequest = await viewModel.openOriginal()
        let request = try XCTUnwrap(openRequest)

        XCTAssertEqual(request.itemID, "item-123")
        XCTAssertEqual(request.url.absoluteString, "http://example.com/articles/123")
        let stateUpdateCalls = await repository.stateUpdateCalls()
        XCTAssertEqual(
            stateUpdateCalls,
            [
                ArticleDetailStateUpdateCall(
                    itemID: "item-123",
                    request: ItemStateUpdateRequest(isRead: true, isStarred: nil),
                    accessToken: "test-access-token"
                )
            ]
        )
        XCTAssertEqual(stateChanges.map(\.isRead), [true])
        XCTAssertNil(stateChanges.first?.isStarred)
        XCTAssertNil(viewModel.mutationMessage)
    }

    func testOpenOriginalWithValidHTTPSURLReturnsRequest() async throws {
        let repository = ArticleDetailRecordingRepository(
            detailResults: [],
            stateUpdateResults: [.success(())]
        )
        let viewModel = makeViewModel(
            summaryLink: "https://example.com/articles/123",
            repository: repository
        )

        let openRequest = await viewModel.openOriginal()
        let request = try XCTUnwrap(openRequest)

        XCTAssertEqual(request.url.absoluteString, "https://example.com/articles/123")
    }

    func testOpenOriginalPrefersLoadedDetailURLOverSummaryURL() async throws {
        let repository = ArticleDetailRecordingRepository(
            detailResults: [
                .success(makeDetail(
                    isRead: false,
                    isStarred: false,
                    link: "https://example.com/detail"
                ))
            ],
            stateUpdateResults: [.success(())]
        )
        let viewModel = makeViewModel(
            summaryLink: "https://example.com/summary",
            repository: repository
        )

        await viewModel.open()
        let openRequest = await viewModel.openOriginal()
        let request = try XCTUnwrap(openRequest)

        XCTAssertEqual(request.url.absoluteString, "https://example.com/detail")
        let stateUpdateCalls = await repository.stateUpdateCalls()
        XCTAssertEqual(stateUpdateCalls.count, 1)
    }

    func testOpenOriginalWithInvalidURLReturnsNilAndDoesNotMarkRead() async {
        let invalidLinks = [
            "",
            "not-a-valid-absolute-url",
            "ftp://example.com/articles/123"
        ]

        for invalidLink in invalidLinks {
            let repository = ArticleDetailRecordingRepository(
                detailResults: [],
                stateUpdateResults: [.success(())]
            )
            let viewModel = makeViewModel(summaryLink: invalidLink, repository: repository)

            let request = await viewModel.openOriginal()

            XCTAssertNil(request)
            XCTAssertEqual(viewModel.mutationMessage?.kind, .openOriginal)
            XCTAssertEqual(viewModel.mutationMessage?.message, "元記事のURLを開けませんでした。")
            let stateUpdateCalls = await repository.stateUpdateCalls()
            XCTAssertTrue(stateUpdateCalls.isEmpty)
        }
    }

    func testOpenOriginalReadMarkingFailureStillReturnsURLAndKeepsMessage() async throws {
        let repository = ArticleDetailRecordingRepository(
            detailResults: [],
            stateUpdateResults: [.failure(ArticleDetailTestError.transport)]
        )
        let viewModel = makeViewModel(repository: repository)

        let openRequest = await viewModel.openOriginal()
        let request = try XCTUnwrap(openRequest)

        XCTAssertEqual(request.url.absoluteString, "https://example.com/summary")
        XCTAssertEqual(viewModel.mutationMessage?.kind, .read)
        XCTAssertEqual(viewModel.mutationMessage?.message, "既読状態を更新できませんでした。")
        let stateUpdateCalls = await repository.stateUpdateCalls()
        XCTAssertEqual(stateUpdateCalls.count, 1)
    }

    func testOpenOriginalMissingAccessTokenRoutesAuthBoundary() async throws {
        let repository = ArticleDetailRecordingRepository(
            detailResults: [],
            stateUpdateResults: [.success(())]
        )
        var authRequiredCount = 0
        let viewModel = makeViewModel(
            repository: repository,
            accessToken: nil,
            onAuthRequired: {
                authRequiredCount += 1
            }
        )

        let openRequest = await viewModel.openOriginal()
        let request = try XCTUnwrap(openRequest)

        XCTAssertEqual(request.url.absoluteString, "https://example.com/summary")
        XCTAssertEqual(authRequiredCount, 1)
        let stateUpdateCalls = await repository.stateUpdateCalls()
        XCTAssertTrue(stateUpdateCalls.isEmpty)
        XCTAssertEqual(
            viewModel.state,
            .failed(
                message: "認証の有効期限が切れました。もう一度ログインしてください。",
                isAuthRequired: true
            )
        )
    }

    func testOpenOriginalAuthRequiredFailureRoutesAuthBoundary() async throws {
        let repository = ArticleDetailRecordingRepository(
            detailResults: [],
            stateUpdateResults: [.failure(Self.authRequiredError)]
        )
        var authRequiredCount = 0
        let viewModel = makeViewModel(
            repository: repository,
            onAuthRequired: {
                authRequiredCount += 1
            }
        )

        let openRequest = await viewModel.openOriginal()
        let request = try XCTUnwrap(openRequest)

        XCTAssertEqual(request.url.absoluteString, "https://example.com/summary")
        XCTAssertEqual(authRequiredCount, 1)
        XCTAssertEqual(viewModel.mutationMessage?.kind, .read)
        XCTAssertEqual(
            viewModel.mutationMessage?.message,
            "認証の有効期限が切れました。もう一度ログインしてください。"
        )
        let stateUpdateCalls = await repository.stateUpdateCalls()
        XCTAssertEqual(stateUpdateCalls.count, 1)
    }

    func testPublishedDateFormatterFormatsSummaryPreviewDate() {
        let dateText = ArticleDetailPublishedDateFormatter.string(
            from: "2026-06-08T08:30:00Z",
            isEstimated: true
        )

        XCTAssertFalse(dateText?.contains("T") ?? true)
        XCTAssertFalse(dateText?.contains("Z") ?? true)
        XCTAssertTrue(dateText?.contains("推定") ?? false)
    }

    func testSearchHitSummaryMappingPreservesNullableFields() {
        let input = ArticleDetailSheetInput(
            searchHit: ItemSearchHit(
                id: "search-hit",
                feedID: "feed-search-hit",
                feedTitle: "Search Feed",
                faviconURL: nil,
                title: "Search Title",
                summary: "Search Summary",
                link: "https://example.com/search-hit",
                publishedAt: nil,
                isDateEstimated: nil,
                isRead: nil,
                isStarred: nil,
                hatebuCount: nil,
                author: nil
            )
        )

        XCTAssertEqual(input.id, "search-hit")
        XCTAssertEqual(input.summary?.feedTitle, "Search Feed")
        XCTAssertNil(input.summary?.feedFaviconURL)
        XCTAssertEqual(input.summary?.title, "Search Title")
        XCTAssertEqual(input.summary?.summary, "Search Summary")
        XCTAssertEqual(input.summary?.link, "https://example.com/search-hit")
        XCTAssertNil(input.summary?.publishedAt)
        XCTAssertNil(input.summary?.isDateEstimated)
        XCTAssertNil(input.summary?.isRead)
        XCTAssertNil(input.summary?.isStarred)
        XCTAssertNil(input.summary?.hatebuCount)
        XCTAssertNil(input.summary?.hatebuFetchedAt)
        XCTAssertNil(input.summary?.author)
    }

    private func makeViewModel(
        summaryLink: String = "https://example.com/summary",
        repository: any ItemRepository,
        accessToken: String? = "test-access-token",
        summaryIsRead: Bool = false,
        itemStateCoordinator: ItemStateCoordinator? = nil,
        onAuthRequired: @escaping () -> Void = {},
        onItemStateChange: @escaping (ItemStateChange) -> Void = { _ in }
    ) -> ArticleDetailViewModel {
        ArticleDetailViewModel(
            itemID: "item-123",
            summary: ArticleDetailSummary(
                id: "item-123",
                feedTitle: "Summary Feed",
                title: "Summary Title",
                summary: "Summary text",
                link: summaryLink,
                publishedAt: "2026-06-08T08:30:00Z",
                isRead: summaryIsRead,
                isStarred: false,
                hatebuCount: 1
            ),
            repository: repository,
            accessToken: accessToken,
            itemStateCoordinator: itemStateCoordinator,
            onAuthRequired: onAuthRequired,
            onItemStateChange: onItemStateChange
        )
    }

    private func makeSummaryItem(isRead: Bool, isStarred: Bool) -> ItemSummary {
        ItemSummary(
            id: "item-123",
            feedID: "feed-123",
            feedTitle: "Feed Title",
            feedFaviconURL: nil,
            title: "Article Title",
            summary: "Summary",
            link: "https://example.com/articles/123",
            publishedAt: "2026-06-08T08:30:00Z",
            isDateEstimated: false,
            isRead: isRead,
            isStarred: isStarred,
            hatebuCount: nil,
            hatebuFetchedAt: nil,
            author: nil
        )
    }

    private func makeDetail(
        isRead: Bool,
        isStarred: Bool,
        content: String? = "<p>本文 <strong>HTML</strong></p>",
        link: String = "https://example.com/articles/123"
    ) -> ItemDetail {
        ItemDetail(
            id: "item-123",
            feedID: "feed-123",
            feedTitle: "Feed Title",
            feedFaviconURL: "data:image/png;base64,iVBORw0KGgo=",
            title: "Article Title",
            summary: "Summary",
            content: content,
            link: link,
            publishedAt: "2026-06-08T08:30:00Z",
            isDateEstimated: false,
            isRead: isRead,
            isStarred: isStarred,
            hatebuCount: 42,
            hatebuFetchedAt: "2026-06-08T08:35:00Z",
            author: "Author"
        )
    }

    private func waitUntil(
        _ condition: @escaping () async -> Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        for _ in 0..<20 {
            if await condition() {
                return
            }
            await Task.yield()
        }

        XCTFail("Timed out waiting for condition", file: file, line: line)
    }

    private static let authRequiredError = FeedmanAPIError.authRequired(
        AuthRequiredContext(
            reason: .missingRefreshHook,
            statusCode: 401,
            underlyingError: nil
        )
    )
}

private enum ArticleDetailTestError: Error {
    case transport
}

private struct ArticleDetailCall: Equatable {
    let itemID: String
    let accessToken: String
}

private struct ArticleDetailStateUpdateCall: Equatable {
    let itemID: String
    let request: ItemStateUpdateRequest
    let accessToken: String
}

private actor ArticleDetailRecordingRepository: ItemRepository {
    private var detailResults: [Result<ItemDetail, Error>]
    private var stateUpdateResults: [Result<Void, Error>]
    private var recordedDetailCalls: [ArticleDetailCall] = []
    private var recordedStateUpdateCalls: [ArticleDetailStateUpdateCall] = []

    init(
        detailResults: [Result<ItemDetail, Error>],
        stateUpdateResults: [Result<Void, Error>]
    ) {
        self.detailResults = detailResults
        self.stateUpdateResults = stateUpdateResults
    }

    func detailCalls() -> [ArticleDetailCall] {
        recordedDetailCalls
    }

    func stateUpdateCalls() -> [ArticleDetailStateUpdateCall] {
        recordedStateUpdateCalls
    }

    func itemDetail(id: String, accessToken: String) async throws -> ItemDetail {
        recordedDetailCalls.append(ArticleDetailCall(itemID: id, accessToken: accessToken))
        guard !detailResults.isEmpty else {
            throw ArticleDetailTestError.transport
        }
        return try detailResults.removeFirst().get()
    }

    func updateItemState(
        id: String,
        request: ItemStateUpdateRequest,
        accessToken: String
    ) async throws {
        recordedStateUpdateCalls.append(
            ArticleDetailStateUpdateCall(
                itemID: id,
                request: request,
                accessToken: accessToken
            )
        )

        guard !stateUpdateResults.isEmpty else {
            return
        }
        try stateUpdateResults.removeFirst().get()
    }
}

private actor PendingArticleDetailRepository: ItemRepository {
    private var recordedDetailCalls: [ArticleDetailCall] = []
    private var detailContinuation: CheckedContinuation<ItemDetail, Error>?

    func detailCalls() -> [ArticleDetailCall] {
        recordedDetailCalls
    }

    func itemDetail(id: String, accessToken: String) async throws -> ItemDetail {
        recordedDetailCalls.append(ArticleDetailCall(itemID: id, accessToken: accessToken))
        return try await withCheckedThrowingContinuation { continuation in
            detailContinuation = continuation
        }
    }

    func updateItemState(
        id: String,
        request: ItemStateUpdateRequest,
        accessToken: String
    ) async throws {}

    func succeed(_ detail: ItemDetail) {
        detailContinuation?.resume(returning: detail)
        detailContinuation = nil
    }
}
