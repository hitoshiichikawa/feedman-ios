import Foundation

enum KeywordSettingsContentState: Equatable {
    case idle
    case loading
    case empty
    case loaded([KeywordResponse])
    case failed(KeywordSettingsErrorPresentation)
}

enum KeywordSettingsOperation: Equatable {
    case loading
    case creating
    case updating(id: String)
    case toggling(id: String)
    case deleting(id: String)
}

enum KeywordSettingsMessage: Equatable {
    case success(String)
    case failure(KeywordSettingsErrorPresentation)
}

struct KeywordDeleteConfirmation: Equatable, Identifiable {
    let id: String
    let term: String
}

struct KeywordSettingsErrorPresentation: Equatable {
    enum Kind: Equatable {
        case emptyTerm
        case duplicate
        case rateLimit(retryAfterSeconds: Int?)
        case authRequired
        case network
        case api(code: String, category: String)
        case generic
    }

    let kind: Kind
    let title: String
    let message: String

    static let emptyTerm = KeywordSettingsErrorPresentation(
        kind: .emptyTerm,
        title: "キーワードを入力してください",
        message: "通知対象にしたい記事タイトルのキーワードを入力してください。"
    )
}

@MainActor
final class KeywordSettingsViewModel: ObservableObject {
    @Published private(set) var contentState: KeywordSettingsContentState = .idle
    @Published private(set) var operation: KeywordSettingsOperation?
    @Published private(set) var message: KeywordSettingsMessage?
    @Published private(set) var deleteConfirmation: KeywordDeleteConfirmation?
    @Published var draftTerm: String = "" {
        didSet {
            guard oldValue != draftTerm else {
                return
            }
            clearValidationMessage()
        }
    }

    private let repository: any KeywordRepository
    private let accessTokenProvider: () -> String?
    private let authRequiredHandler: () -> Void

    convenience init(
        repository: any KeywordRepository,
        accessToken: String?,
        authRequiredHandler: @escaping () -> Void = {}
    ) {
        self.init(
            repository: repository,
            accessTokenProvider: { accessToken },
            authRequiredHandler: authRequiredHandler
        )
    }

    init(
        repository: any KeywordRepository,
        accessTokenProvider: @escaping () -> String?,
        authRequiredHandler: @escaping () -> Void = {}
    ) {
        self.repository = repository
        self.accessTokenProvider = accessTokenProvider
        self.authRequiredHandler = authRequiredHandler
    }

    var keywords: [KeywordResponse] {
        switch contentState {
        case .loaded(let keywords):
            return keywords
        case .idle, .loading, .empty, .failed:
            return []
        }
    }

    var canCreate: Bool {
        !trimmed(draftTerm).isEmpty && operation != .creating
    }

    var isLoading: Bool {
        operation == .loading
    }

    func loadKeywords() async {
        guard operation != .loading else {
            return
        }

        let previousKeywords = keywords
        let isInitialLoad = previousKeywords.isEmpty
        operation = .loading
        message = nil
        deleteConfirmation = nil
        if isInitialLoad {
            contentState = .loading
        }

        do {
            let loadedKeywords = try await repository.keywords(accessToken: try accessToken())
            operation = nil
            contentState = loadedKeywords.isEmpty ? .empty : .loaded(loadedKeywords)
        } catch {
            operation = nil
            let presentation = Self.errorPresentation(for: error)
            handleAuthIfNeeded(presentation)
            if isInitialLoad {
                contentState = .failed(presentation)
            } else {
                contentState = .loaded(previousKeywords)
                message = .failure(presentation)
            }
        }
    }

    func retryInitialLoad() async {
        await loadKeywords()
    }

    @discardableResult
    func createKeyword(term: String? = nil) async -> Bool {
        guard operation != .creating else {
            return false
        }

        let sourceTerm = term ?? draftTerm
        let term = trimmed(sourceTerm)
        guard !term.isEmpty else {
            message = .failure(.emptyTerm)
            return false
        }

        operation = .creating
        do {
            let keyword = try await repository.createKeyword(
                KeywordCreateRequest(term: term, enabled: true),
                accessToken: try accessToken()
            )
            operation = nil
            draftTerm = ""
            replaceOrAppend(keyword)
            message = .success("キーワードを追加しました")
            return true
        } catch {
            operation = nil
            let presentation = Self.errorPresentation(for: error)
            handleAuthIfNeeded(presentation)
            message = .failure(presentation)
            return false
        }
    }

    @discardableResult
    func updateKeyword(id: String, term: String) async -> Bool {
        guard operation != .updating(id: id) else {
            return false
        }

        let term = trimmed(term)
        guard !term.isEmpty else {
            message = .failure(.emptyTerm)
            return false
        }

        operation = .updating(id: id)
        do {
            let keyword = try await repository.updateKeyword(
                id: id,
                request: KeywordUpdateRequest(term: term, enabled: nil),
                accessToken: try accessToken()
            )
            operation = nil
            replaceOrAppend(keyword)
            message = .success("キーワードを更新しました")
            return true
        } catch {
            operation = nil
            let presentation = Self.errorPresentation(for: error)
            handleAuthIfNeeded(presentation)
            message = .failure(presentation)
            return false
        }
    }

    @discardableResult
    func setKeywordEnabled(id: String, enabled: Bool) async -> Bool {
        guard operation != .toggling(id: id) else {
            return false
        }

        operation = .toggling(id: id)
        do {
            let keyword = try await repository.updateKeyword(
                id: id,
                request: KeywordUpdateRequest(term: nil, enabled: enabled),
                accessToken: try accessToken()
            )
            operation = nil
            replaceOrAppend(keyword)
            message = .success(enabled ? "キーワード通知を有効にしました" : "キーワード通知を無効にしました")
            return true
        } catch {
            operation = nil
            let presentation = Self.errorPresentation(for: error)
            handleAuthIfNeeded(presentation)
            message = .failure(presentation)
            return false
        }
    }

    func requestDeleteConfirmation(id: String) {
        guard operation == nil,
              let keyword = keywords.first(where: { $0.id == id }) else {
            return
        }
        deleteConfirmation = KeywordDeleteConfirmation(id: keyword.id, term: keyword.term)
    }

    func cancelDeleteConfirmation() {
        deleteConfirmation = nil
    }

    @discardableResult
    func confirmDeleteKeyword() async -> Bool {
        guard let confirmation = deleteConfirmation,
              operation != .deleting(id: confirmation.id) else {
            return false
        }

        operation = .deleting(id: confirmation.id)
        do {
            try await repository.deleteKeyword(id: confirmation.id, accessToken: try accessToken())
            operation = nil
            removeKeyword(id: confirmation.id)
            deleteConfirmation = nil
            message = .success("キーワードを削除しました")
            return true
        } catch {
            operation = nil
            let presentation = Self.errorPresentation(for: error)
            handleAuthIfNeeded(presentation)
            message = .failure(presentation)
            return false
        }
    }

    static func errorPresentation(for error: Error) -> KeywordSettingsErrorPresentation {
        if case FeedmanAPIError.authRequired = error {
            return KeywordSettingsErrorPresentation(
                kind: .authRequired,
                title: "ログインが必要です",
                message: "認証の有効期限が切れています。再ログイン後にもう一度お試しください。"
            )
        }

        if case FeedmanAPIError.transportFailed = error {
            return KeywordSettingsErrorPresentation(
                kind: .network,
                title: "通信できませんでした",
                message: "ネットワーク接続を確認してからもう一度お試しください。"
            )
        }

        guard case let FeedmanAPIError.feedmanError(context) = error else {
            return KeywordSettingsErrorPresentation(
                kind: .generic,
                title: "キーワードを更新できませんでした",
                message: "時間をおいてもう一度お試しください。"
            )
        }

        if context.isDuplicateKeywordError {
            return KeywordSettingsErrorPresentation(
                kind: .duplicate,
                title: "すでに登録されています",
                message: "このキーワードは登録済みです。別のキーワードを入力してください。"
            )
        }

        if context.isRateLimitError {
            let retryAfterSeconds = context.presentationRetryAfterSeconds
            return KeywordSettingsErrorPresentation(
                kind: .rateLimit(retryAfterSeconds: retryAfterSeconds),
                title: "しばらく待ってください",
                message: rateLimitMessage(retryAfterSeconds: retryAfterSeconds)
            )
        }

        return KeywordSettingsErrorPresentation(
            kind: .api(code: context.code, category: context.category),
            title: "キーワードを更新できませんでした",
            message: "入力内容を確認し、時間をおいてもう一度お試しください。"
        )
    }

    private func accessToken() throws -> String {
        guard let accessToken = accessTokenProvider(), !accessToken.isEmpty else {
            throw FeedmanAPIError.authRequired(
                AuthRequiredContext(
                    reason: .credentialsUnavailable,
                    statusCode: nil,
                    underlyingError: nil
                )
            )
        }
        return accessToken
    }

    private func trimmed(_ term: String) -> String {
        term.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func replaceOrAppend(_ keyword: KeywordResponse) {
        var nextKeywords = keywords
        if let index = nextKeywords.firstIndex(where: { $0.id == keyword.id }) {
            nextKeywords[index] = keyword
        } else {
            nextKeywords.append(keyword)
        }
        contentState = nextKeywords.isEmpty ? .empty : .loaded(nextKeywords)
    }

    private func removeKeyword(id: String) {
        let nextKeywords = keywords.filter { $0.id != id }
        contentState = nextKeywords.isEmpty ? .empty : .loaded(nextKeywords)
    }

    private func handleAuthIfNeeded(_ presentation: KeywordSettingsErrorPresentation) {
        if presentation.kind == .authRequired {
            authRequiredHandler()
        }
    }

    private func clearValidationMessage() {
        guard case .failure(let presentation) = message,
              presentation.kind == .emptyTerm else {
            return
        }
        message = nil
    }

    private static func rateLimitMessage(retryAfterSeconds: Int?) -> String {
        guard let retryAfterSeconds else {
            return "操作が多すぎます。時間をおいてもう一度お試しください。"
        }

        return "操作が多すぎます。約 \(retryAfterSeconds) 秒後にもう一度お試しください。"
    }
}

private extension FeedmanErrorContext {
    var normalizedCode: String {
        code.lowercased()
    }

    var normalizedCategory: String {
        category.lowercased()
    }

    var isDuplicateKeywordError: Bool {
        statusCode == 409
            || normalizedCode.contains("duplicate")
            || normalizedCode.contains("already")
            || normalizedCode.contains("exists")
            || normalizedCategory.contains("conflict")
    }

    var isRateLimitError: Bool {
        statusCode == 429
            || normalizedCategory == "rate_limit"
            || normalizedCode.contains("rate_limit")
            || normalizedCode.contains("cooldown")
    }

    var presentationRetryAfterSeconds: Int? {
        retryAfterSeconds ?? retryAfter.flatMap(Int.init)
    }
}
