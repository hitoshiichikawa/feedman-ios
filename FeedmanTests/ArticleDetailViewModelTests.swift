import XCTest
@testable import Feedman

@MainActor
final class ArticleDetailViewModelTests: XCTestCase {
    func testOpenFetchesDetailAndMarksReadWithPartialRequest() async throws {
        let repository = ArticleDetailRecordingRepository(
            detailResults: [.success(makeDetail(isRead: false, isStarred: false))],
            stateUpdateResults: [.success(())]
        )
        let viewModel = makeViewModel(repository: repository)

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

    func testReadMarkingFailureDoesNotBlockLoadedDetail() async throws {
        let repository = ArticleDetailRecordingRepository(
            detailResults: [.success(makeDetail(isRead: false, isStarred: false))],
            stateUpdateResults: [.failure(ArticleDetailTestError.transport)]
        )
        let viewModel = makeViewModel(repository: repository)

        await viewModel.open()

        let presentation = try XCTUnwrap(viewModel.loadedPresentation)
        XCTAssertEqual(presentation.title, "Article Title")
        XCTAssertEqual(viewModel.mutationMessage?.kind, .read)
        XCTAssertEqual(viewModel.mutationMessage?.message, "既読状態を保存できませんでした。")
    }

    func testStarToggleSendsPartialStarRequestAndUpdatesSheetLocalState() async throws {
        let repository = ArticleDetailRecordingRepository(
            detailResults: [.success(makeDetail(isRead: true, isStarred: false))],
            stateUpdateResults: [.success(()), .success(())]
        )
        let viewModel = makeViewModel(repository: repository)

        await viewModel.open()
        await viewModel.toggleStar()

        let updates = await repository.stateUpdateCalls()
        XCTAssertEqual(updates.map(\.request), [
            ItemStateUpdateRequest(isRead: true, isStarred: nil),
            ItemStateUpdateRequest(isRead: nil, isStarred: true)
        ])
        XCTAssertEqual(viewModel.loadedPresentation?.isStarred, true)
        XCTAssertNil(viewModel.mutationMessage)
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
        XCTAssertEqual(viewModel.mutationMessage?.kind, .star)
        XCTAssertEqual(viewModel.mutationMessage?.message, "スター状態を保存できませんでした。")
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

    func testPublishedDateFormatterFormatsSummaryPreviewDate() {
        let dateText = ArticleDetailPublishedDateFormatter.string(
            from: "2026-06-08T08:30:00Z",
            isEstimated: true
        )

        XCTAssertFalse(dateText?.contains("T") ?? true)
        XCTAssertFalse(dateText?.contains("Z") ?? true)
        XCTAssertTrue(dateText?.contains("推定") ?? false)
    }

    private func makeViewModel(
        repository: any ItemRepository,
        accessToken: String? = "test-access-token"
    ) -> ArticleDetailViewModel {
        ArticleDetailViewModel(
            itemID: "item-123",
            summary: ArticleDetailSummary(
                id: "item-123",
                feedTitle: "Summary Feed",
                title: "Summary Title",
                summary: "Summary text",
                link: "https://example.com/summary",
                publishedAt: "2026-06-08T08:30:00Z",
                isStarred: false,
                hatebuCount: 1
            ),
            repository: repository,
            accessToken: accessToken
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
