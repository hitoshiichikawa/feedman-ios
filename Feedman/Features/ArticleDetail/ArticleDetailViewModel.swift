import Combine
import Foundation

struct ArticleDetailSheetInput: Identifiable, Equatable {
    let id: String
    let summary: ArticleDetailSummary?

    init(id: String, summary: ArticleDetailSummary? = nil) {
        self.id = id
        self.summary = summary
    }

    init(item: FeedItem) {
        self.id = item.id
        self.summary = ArticleDetailSummary(item: item)
    }

    init(searchHit: ItemSearchHit) {
        self.id = searchHit.id
        self.summary = ArticleDetailSummary(searchHit: searchHit)
    }
}

struct ArticleDetailSummary: Equatable {
    let id: String
    let feedTitle: String?
    let feedFaviconURL: String?
    let title: String?
    let summary: String?
    let link: String?
    let publishedAt: String?
    let isDateEstimated: Bool?
    let isRead: Bool?
    let isStarred: Bool?
    let hatebuCount: Int?
    let hatebuFetchedAt: String?
    let author: String?

    init(
        id: String,
        feedTitle: String? = nil,
        feedFaviconURL: String? = nil,
        title: String? = nil,
        summary: String? = nil,
        link: String? = nil,
        publishedAt: String? = nil,
        isDateEstimated: Bool? = nil,
        isRead: Bool? = nil,
        isStarred: Bool? = nil,
        hatebuCount: Int? = nil,
        hatebuFetchedAt: String? = nil,
        author: String? = nil
    ) {
        self.id = id
        self.feedTitle = feedTitle
        self.feedFaviconURL = feedFaviconURL
        self.title = title
        self.summary = summary
        self.link = link
        self.publishedAt = publishedAt
        self.isDateEstimated = isDateEstimated
        self.isRead = isRead
        self.isStarred = isStarred
        self.hatebuCount = hatebuCount
        self.hatebuFetchedAt = hatebuFetchedAt
        self.author = author
    }

    init(item: FeedItem) {
        self.init(
            id: item.id,
            feedTitle: item.feedTitle,
            title: item.title,
            summary: item.summary,
            link: item.link.absoluteString,
            publishedAt: item.publishedAt,
            isRead: item.isRead,
            isStarred: item.isStarred,
            hatebuCount: item.hatebuCount
        )
    }

    init(item: ItemSummary) {
        self.init(
            id: item.id,
            feedTitle: item.feedTitle,
            feedFaviconURL: item.feedFaviconURL,
            title: item.title,
            summary: item.summary,
            link: item.link,
            publishedAt: item.publishedAt,
            isDateEstimated: item.isDateEstimated,
            isRead: item.isRead,
            isStarred: item.isStarred,
            hatebuCount: item.hatebuCount,
            hatebuFetchedAt: item.hatebuFetchedAt,
            author: item.author
        )
    }

    init(searchHit: ItemSearchHit) {
        self.init(
            id: searchHit.id,
            feedTitle: searchHit.feedTitle,
            feedFaviconURL: searchHit.faviconURL,
            title: searchHit.title,
            summary: searchHit.summary,
            link: searchHit.link,
            publishedAt: searchHit.publishedAt,
            isDateEstimated: searchHit.isDateEstimated,
            isRead: searchHit.isRead,
            isStarred: searchHit.isStarred,
            hatebuCount: searchHit.hatebuCount,
            hatebuFetchedAt: nil,
            author: searchHit.author
        )
    }
}

enum ArticleDetailViewState: Equatable {
    case idle
    case loading(summary: ArticleDetailSummary?)
    case loaded(ArticleDetailPresentation)
    case failed(message: String, isAuthRequired: Bool)
}

struct ArticleDetailPresentation: Equatable {
    let id: String
    let sourceMetadata: ArticleSourceMetadata
    let title: String
    let publishedDateText: String?
    let authorText: String?
    let isDateEstimated: Bool
    let isRead: Bool
    let isStarred: Bool
    let hatebuState: ArticleHatebuCountState
    let linkURL: URL?
    let preview: ArticleDetailContentPreview

    init(detail: ItemDetail) {
        self.id = detail.id
        let publishedDateText = ArticleDetailPublishedDateFormatter.string(
            from: detail.publishedAt,
            isEstimated: detail.isDateEstimated
        )
        self.sourceMetadata = ArticleSourceMetadata(
            feedTitle: detail.feedTitle,
            faviconURL: detail.feedFaviconURL,
            relativeDate: publishedDateText
        )
        self.title = detail.title
        self.publishedDateText = publishedDateText
        self.authorText = detail.author.nilIfBlank
        self.isDateEstimated = detail.isDateEstimated
        self.isRead = detail.isRead
        self.isStarred = detail.isStarred
        self.hatebuState = ArticleHatebuCountState(
            count: detail.hatebuCount,
            isFetched: detail.hatebuCount != nil || detail.hatebuFetchedAt != nil
        )
        self.linkURL = Self.validHTTPURL(from: detail.link)
        self.preview = ArticleDetailContentPreview(
            contentHTML: detail.content,
            summary: detail.summary
        )
    }

    private static func validHTTPURL(from rawValue: String) -> URL? {
        ArticleDetailOriginalArticleRequest.validHTTPURL(from: rawValue)
    }
}

struct ArticleDetailOriginalArticleRequest: Equatable {
    let itemID: String
    let url: URL

    static func validHTTPURL(from rawValue: String?) -> URL? {
        guard let rawValue = rawValue.nilIfBlank,
              let url = URL(string: rawValue),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              url.host != nil
        else {
            return nil
        }

        return url
    }
}

enum ArticleDetailPublishedDateFormatter {
    static func string(from rfc3339: String?, isEstimated: Bool?) -> String? {
        guard let rfc3339 = rfc3339.nilIfBlank else {
            return nil
        }

        guard let date = ISO8601DateFormatter.feedmanDate(from: rfc3339) else {
            return rfc3339
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy/MM/dd HH:mm"

        let formatted = formatter.string(from: date)
        return isEstimated == true ? "\(formatted) 推定" : formatted
    }
}

struct ArticleDetailContentPreview: Equatable {
    enum Source: Equatable {
        case content
        case summary
        case empty
    }

    let text: String
    let source: Source

    init(contentHTML: String?, summary: String?) {
        if let contentText = Self.readableText(fromHTML: contentHTML).nilIfBlank {
            self.text = contentText
            self.source = .content
            return
        }

        if let summaryText = summary.nilIfBlank {
            self.text = summaryText
            self.source = .summary
            return
        }

        self.text = "本文プレビューはありません。"
        self.source = .empty
    }

    private static func readableText(fromHTML html: String?) -> String {
        guard let html = html.nilIfBlank else {
            return ""
        }

        return normalizedText(strippingHTMLTags(from: html))
    }

    private static func strippingHTMLTags(from html: String) -> String {
        let withoutScripts = html.replacingOccurrences(
            of: "(?is)<(script|style)[^>]*>.*?</\\1>",
            with: " ",
            options: .regularExpression
        )
        return withoutScripts
            .replacingOccurrences(of: "(?s)<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
    }

    private static func normalizedText(_ text: String) -> String {
        text
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}

struct ArticleDetailMutationMessage: Equatable, Identifiable {
    enum Kind: Equatable {
        case read
        case star
        case openOriginal
    }

    let id = UUID()
    let kind: Kind
    let message: String

    static let readFailure = ArticleDetailMutationMessage(
        kind: .read,
        message: "既読状態を更新できませんでした。"
    )

    static let starFailure = ArticleDetailMutationMessage(
        kind: .star,
        message: "スターを更新できませんでした。"
    )

    static let openOriginalInvalidURL = ArticleDetailMutationMessage(
        kind: .openOriginal,
        message: "元記事のURLを開けませんでした。"
    )
}

@MainActor
final class ArticleDetailViewModel: ObservableObject {
    @Published private(set) var state: ArticleDetailViewState
    @Published private(set) var mutationMessage: ArticleDetailMutationMessage?
    @Published private(set) var isStarUpdateInFlight = false

    private let itemID: String
    private let summary: ArticleDetailSummary?
    private let repository: any ItemRepository
    private let accessToken: String?
    private let itemStateCoordinator: ItemStateCoordinator
    private let onAuthRequired: () -> Void
    private let onItemStateChange: (ItemStateChange) -> Void
    private var hasOpened = false
    private var didMarkReadOnOpen = false
    private var detail: ItemDetail?
    private var cancellables: Set<AnyCancellable> = []

    init(
        itemID: String,
        summary: ArticleDetailSummary? = nil,
        repository: any ItemRepository,
        accessToken: String?,
        itemStateCoordinator: ItemStateCoordinator? = nil,
        onAuthRequired: @escaping () -> Void = {},
        onItemStateChange: @escaping (ItemStateChange) -> Void = { _ in }
    ) {
        self.itemID = itemID
        self.summary = summary
        self.repository = repository
        self.accessToken = accessToken
        self.itemStateCoordinator = itemStateCoordinator ?? ItemStateCoordinator()
        self.onAuthRequired = onAuthRequired
        self.onItemStateChange = onItemStateChange
        self.state = .idle
        observeItemStateCoordinator()
    }

    var loadedPresentation: ArticleDetailPresentation? {
        if case let .loaded(presentation) = state {
            return presentation
        }
        return nil
    }

    func open() async {
        guard !hasOpened else {
            return
        }
        hasOpened = true

        await markReadOnOpen()
        await loadDetail()
    }

    func retry() async {
        await loadDetail()
    }

    func toggleStar() async {
        guard !isStarUpdateInFlight,
              let detail,
              let accessToken = validatedAccessToken()
        else {
            return
        }

        let snapshot = itemStateCoordinator.effectiveState(
            itemID: itemID,
            baseRead: detail.isRead,
            baseStarred: detail.isStarred
        )
        let targetValue = !snapshot.isStarred
        guard let token = itemStateCoordinator.beginMutation(
            itemID: itemID,
            baseRead: detail.isRead,
            baseStarred: detail.isStarred,
            isStarred: targetValue
        ) else {
            return
        }

        refreshLoadedPresentation()
        isStarUpdateInFlight = true
        defer {
            isStarUpdateInFlight = false
        }

        do {
            try await repository.updateItemState(
                id: itemID,
                request: ItemStateUpdateRequest(isRead: nil, isStarred: targetValue),
                accessToken: accessToken
            )
            itemStateCoordinator.commitMutation(token)
            refreshLoadedPresentation()
            mutationMessage = nil
            onItemStateChange(
                ItemStateChange(itemID: itemID, isRead: nil, isStarred: targetValue)
            )
        } catch {
            itemStateCoordinator.rollbackMutation(token)
            refreshLoadedPresentation()
            applyMutationFailure(.starFailure, error: error)
        }
    }

    func openOriginal() async -> ArticleDetailOriginalArticleRequest? {
        guard let url = originalArticleURL else {
            mutationMessage = .openOriginalInvalidURL
            return nil
        }

        if !didMarkReadOnOpen {
            await markReadOnOpen()
        }

        return ArticleDetailOriginalArticleRequest(itemID: itemID, url: url)
    }

    func dismissMutationMessage() {
        mutationMessage = nil
    }

    private var originalArticleURL: URL? {
        if let detail {
            return ArticleDetailOriginalArticleRequest.validHTTPURL(from: detail.link)
        }

        return ArticleDetailOriginalArticleRequest.validHTTPURL(from: summary?.link)
    }

    private func loadDetail() async {
        guard let accessToken = validatedAccessToken() else {
            applyFailure(AppEnvironmentError.missingAccessToken)
            return
        }

        state = .loading(summary: summary)

        do {
            let loadedDetail = try await repository.itemDetail(id: itemID, accessToken: accessToken)
            applyDetail(loadedDetail)
        } catch {
            applyFailure(error)
        }
    }

    private func markReadOnOpen() async {
        guard let accessToken = validatedAccessToken() else {
            applyFailure(AppEnvironmentError.missingAccessToken)
            return
        }

        let baseline = readStarBaseline()
        let snapshot = itemStateCoordinator.effectiveState(
            itemID: itemID,
            baseRead: baseline.isRead,
            baseStarred: baseline.isStarred
        )
        guard !snapshot.isRead else {
            didMarkReadOnOpen = true
            return
        }

        guard let token = itemStateCoordinator.beginMutation(
            itemID: itemID,
            baseRead: baseline.isRead,
            baseStarred: baseline.isStarred,
            isRead: true
        ) else {
            return
        }

        refreshLoadedPresentation()

        do {
            try await repository.updateItemState(
                id: itemID,
                request: ItemStateUpdateRequest(isRead: true, isStarred: nil),
                accessToken: accessToken
            )
            itemStateCoordinator.commitMutation(token)
            didMarkReadOnOpen = true
            refreshLoadedPresentation()
            onItemStateChange(
                ItemStateChange(itemID: itemID, isRead: true, isStarred: nil)
            )
            mutationMessage = nil
        } catch {
            itemStateCoordinator.rollbackMutation(token)
            refreshLoadedPresentation()
            applyMutationFailure(.readFailure, error: error)
        }
    }

    private func applyDetail(_ detail: ItemDetail) {
        self.detail = detail
        state = .loaded(ArticleDetailPresentation(detail: itemStateCoordinator.effectiveDetail(detail)))
    }

    private func refreshLoadedPresentation() {
        guard let detail else {
            return
        }

        state = .loaded(ArticleDetailPresentation(detail: itemStateCoordinator.effectiveDetail(detail)))
    }

    private func readStarBaseline() -> (isRead: Bool, isStarred: Bool) {
        if let detail {
            return (detail.isRead, detail.isStarred)
        }

        return (summary?.isRead ?? false, summary?.isStarred ?? false)
    }

    private func observeItemStateCoordinator() {
        itemStateCoordinator.objectWillChange
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.refreshLoadedPresentation()
                }
            }
            .store(in: &cancellables)
    }

    private func applyFailure(_ error: Error) {
        if case FeedmanAPIError.authRequired = error {
            onAuthRequired()
            state = .failed(
                message: "認証の有効期限が切れました。もう一度ログインしてください。",
                isAuthRequired: true
            )
            return
        }

        if case AppEnvironmentError.missingAccessToken = error {
            onAuthRequired()
            state = .failed(
                message: "認証の有効期限が切れました。もう一度ログインしてください。",
                isAuthRequired: true
            )
            return
        }

        state = .failed(
            message: "記事詳細を読み込めませんでした。",
            isAuthRequired: false
        )
    }

    private func applyMutationFailure(
        _ message: ArticleDetailMutationMessage,
        error: Error
    ) {
        if case FeedmanAPIError.authRequired = error {
            onAuthRequired()
            mutationMessage = ArticleDetailMutationMessage(
                kind: message.kind,
                message: "認証の有効期限が切れました。もう一度ログインしてください。"
            )
            return
        }

        if case AppEnvironmentError.missingAccessToken = error {
            onAuthRequired()
            mutationMessage = ArticleDetailMutationMessage(
                kind: message.kind,
                message: "認証の有効期限が切れました。もう一度ログインしてください。"
            )
            return
        }

        mutationMessage = message
    }

    private func validatedAccessToken() -> String? {
        guard let accessToken = accessToken?.nilIfBlank else {
            return nil
        }
        return accessToken
    }
}

private extension ItemDetail {
    func updating(isRead: Bool? = nil, isStarred: Bool? = nil) -> ItemDetail {
        ItemDetail(
            id: id,
            feedID: feedID,
            feedTitle: feedTitle,
            feedFaviconURL: feedFaviconURL,
            title: title,
            summary: summary,
            content: content,
            link: link,
            publishedAt: publishedAt,
            isDateEstimated: isDateEstimated,
            isRead: isRead ?? self.isRead,
            isStarred: isStarred ?? self.isStarred,
            hatebuCount: hatebuCount,
            hatebuFetchedAt: hatebuFetchedAt,
            author: author
        )
    }
}

private extension ISO8601DateFormatter {
    static func feedmanDate(from string: String) -> Date? {
        if let date = feedmanRFC3339WithFractionalSeconds.date(from: string) {
            return date
        }

        return feedmanRFC3339.date(from: string)
    }

    static let feedmanRFC3339WithFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static let feedmanRFC3339: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}

private extension String? {
    var nilIfBlank: String? {
        guard let trimmed = self?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty
        else {
            return nil
        }
        return trimmed
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
