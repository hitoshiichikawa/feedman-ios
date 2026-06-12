import Foundation

enum RegisterFeedSubmissionState: Equatable {
    case input
    case loading
    case success(RegisteredFeed)
    case failure(RegisterFeedErrorPresentation)

    var isLoading: Bool {
        if case .loading = self {
            return true
        }
        return false
    }
}

struct RegisterFeedSuccessEvent: Equatable, Identifiable {
    let id: UUID
    let registeredFeed: RegisteredFeed

    init(id: UUID = UUID(), registeredFeed: RegisteredFeed) {
        self.id = id
        self.registeredFeed = registeredFeed
    }
}

struct RegisterFeedErrorPresentation: Equatable {
    enum Kind: Equatable {
        case emptyInput
        case invalidURL
        case duplicate
        case rateLimit(retryAfterSeconds: Int?)
        case authRequired
        case network
        case generic
    }

    let kind: Kind
    let title: String
    let message: String

    static let emptyInput = RegisterFeedErrorPresentation(
        kind: .emptyInput,
        title: "URL を入力してください",
        message: "サイトの URL か RSS/Atom の URL を入力してください。"
    )
}

@MainActor
final class RegisterFeedViewModel: ObservableObject {
    @Published var urlText: String {
        didSet {
            guard oldValue != urlText else {
                return
            }

            if case .failure = submissionState {
                submissionState = .input
            }
        }
    }

    @Published private(set) var submissionState: RegisterFeedSubmissionState
    @Published private(set) var successEvent: RegisterFeedSuccessEvent?

    private let repository: FeedRepository

    init(
        repository: FeedRepository,
        initialURL: String = ""
    ) {
        self.repository = repository
        self.urlText = initialURL
        self.submissionState = .input
    }

    var canSubmit: Bool {
        !trimmedURL.isEmpty && !submissionState.isLoading
    }

    func submit() async {
        guard !submissionState.isLoading else {
            return
        }

        let url = trimmedURL
        guard !url.isEmpty else {
            submissionState = .failure(.emptyInput)
            return
        }

        if urlText != url {
            urlText = url
        }

        submissionState = .loading

        do {
            let registeredFeed = try await repository.registerFeed(url: url)
            submissionState = .success(registeredFeed)
            successEvent = RegisterFeedSuccessEvent(registeredFeed: registeredFeed)
        } catch {
            submissionState = .failure(Self.errorPresentation(for: error))
        }
    }

    private var trimmedURL: String {
        urlText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func errorPresentation(for error: Error) -> RegisterFeedErrorPresentation {
        if case FeedmanAPIError.authRequired = error {
            return RegisterFeedErrorPresentation(
                kind: .authRequired,
                title: "ログインが必要です",
                message: "認証の有効期限が切れています。再ログインが必要です。"
            )
        }

        if case FeedmanAPIError.transportFailed = error {
            return RegisterFeedErrorPresentation(
                kind: .network,
                title: "通信できませんでした",
                message: "ネットワーク接続を確認してからもう一度お試しください。"
            )
        }

        guard case let FeedmanAPIError.feedmanError(context) = error else {
            return RegisterFeedErrorPresentation(
                kind: .generic,
                title: "フィードを登録できませんでした",
                message: "時間をおいてもう一度お試しください。"
            )
        }

        if context.isDuplicateFeedError {
            return RegisterFeedErrorPresentation(
                kind: .duplicate,
                title: "すでに登録されています",
                message: "このフィードは購読済みです。別の URL を入力する必要はありません。"
            )
        }

        if context.isRateLimitError {
            return RegisterFeedErrorPresentation(
                kind: .rateLimit(retryAfterSeconds: context.presentationRetryAfterSeconds),
                title: "しばらく待ってください",
                message: Self.rateLimitMessage(retryAfterSeconds: context.presentationRetryAfterSeconds)
            )
        }

        if context.isInvalidFeedURLError {
            return RegisterFeedErrorPresentation(
                kind: .invalidURL,
                title: "URL を確認してください",
                message: "サイトの URL または RSS/Atom の URL が正しいか確認してください。"
            )
        }

        return RegisterFeedErrorPresentation(
            kind: .generic,
            title: "フィードを登録できませんでした",
            message: "入力内容を確認し、時間をおいてもう一度お試しください。"
        )
    }

    private static func rateLimitMessage(retryAfterSeconds: Int?) -> String {
        guard let retryAfterSeconds else {
            return "登録リクエストが多すぎます。時間をおいてもう一度お試しください。"
        }

        return "登録リクエストが多すぎます。約 \(retryAfterSeconds) 秒後にもう一度お試しください。"
    }
}

private extension FeedmanErrorContext {
    var normalizedCode: String {
        code.lowercased()
    }

    var normalizedCategory: String {
        category.lowercased()
    }

    var isDuplicateFeedError: Bool {
        statusCode == 409
            || normalizedCode.contains("duplicate")
            || normalizedCode.contains("already")
            || normalizedCode.contains("exists")
            || normalizedCategory.contains("conflict")
    }

    var isRateLimitError: Bool {
        statusCode == 429
            || normalizedCode == "feed_cooldown"
            || normalizedCategory == "rate_limit"
    }

    var isInvalidFeedURLError: Bool {
        statusCode == 400
            || normalizedCategory == "validation"
            || normalizedCode.contains("invalid_url")
            || normalizedCode.contains("invalid_feed")
            || normalizedCode.contains("validation")
    }

    var presentationRetryAfterSeconds: Int? {
        retryAfterSeconds ?? retryAfter.flatMap(Int.init)
    }
}
