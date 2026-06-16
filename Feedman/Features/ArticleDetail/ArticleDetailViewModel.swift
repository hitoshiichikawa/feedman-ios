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
            isStarred: item.isStarred,
            hatebuCount: item.hatebuCount
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
        self.sourceMetadata = ArticleSourceMetadata(
            feedTitle: detail.feedTitle,
            faviconURL: detail.feedFaviconURL,
            relativeDate: Self.formattedPublishedDate(
                detail.publishedAt,
                isEstimated: detail.isDateEstimated
            )
        )
        self.title = detail.title
        self.publishedDateText = Self.formattedPublishedDate(
            detail.publishedAt,
            isEstimated: detail.isDateEstimated
        )
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

    private static func formattedPublishedDate(_ rfc3339: String, isEstimated: Bool) -> String? {
        guard let date = ISO8601DateFormatter.feedmanDate(from: rfc3339) else {
            return rfc3339.nilIfBlank
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy/MM/dd HH:mm"

        let formatted = formatter.string(from: date)
        return isEstimated ? "\(formatted) 推定" : formatted
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
    }

    let id = UUID()
    let kind: Kind
    let message: String

    static let readFailure = ArticleDetailMutationMessage(
        kind: .read,
        message: "既読状態を保存できませんでした。"
    )

    static let starFailure = ArticleDetailMutationMessage(
        kind: .star,
        message: "スター状態を保存できませんでした。"
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
    private let onAuthRequired: () -> Void
    private var hasOpened = false
    private var didMarkReadOnOpen = false
    private var detail: ItemDetail?

    init(
        itemID: String,
        summary: ArticleDetailSummary? = nil,
        repository: any ItemRepository,
        accessToken: String?,
        onAuthRequired: @escaping () -> Void = {}
    ) {
        self.itemID = itemID
        self.summary = summary
        self.repository = repository
        self.accessToken = accessToken
        self.onAuthRequired = onAuthRequired
        self.state = .idle
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

        let targetValue = !detail.isStarred
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
            applyDetail(detail.updating(isStarred: targetValue))
            mutationMessage = nil
        } catch {
            applyMutationFailure(.starFailure, error: error)
        }
    }

    func dismissMutationMessage() {
        mutationMessage = nil
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

        do {
            try await repository.updateItemState(
                id: itemID,
                request: ItemStateUpdateRequest(isRead: true, isStarred: nil),
                accessToken: accessToken
            )
            didMarkReadOnOpen = true

            if let detail {
                applyDetail(detail.updating(isRead: true))
            }
        } catch {
            applyMutationFailure(.readFailure, error: error)
        }
    }

    private func applyDetail(_ detail: ItemDetail) {
        let displayDetail = didMarkReadOnOpen ? detail.updating(isRead: true) : detail
        self.detail = displayDetail
        state = .loaded(ArticleDetailPresentation(detail: displayDetail))
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
