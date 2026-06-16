import Combine
import Foundation

struct AccountDisplayUser: Equatable {
    let id: String
    let displayName: String
    let email: String?
    let avatarURL: String?

    init(response: UserResponse) {
        id = response.id

        let trimmedName = response.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let trimmedEmail = response.email?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if !trimmedName.isEmpty {
            displayName = trimmedName
        } else if !trimmedEmail.isEmpty {
            displayName = trimmedEmail
        } else {
            displayName = "ログイン中のユーザー"
        }

        email = trimmedEmail.isEmpty ? nil : trimmedEmail
        avatarURL = response.avatarURL
    }
}

enum AccountViewState: Equatable {
    case idle
    case loading
    case loaded(AccountDisplayUser)
    case failed(AccountErrorViewState)

    var isLoading: Bool {
        if case .loading = self {
            return true
        }
        return false
    }
}

enum AccountDeletionState: Equatable {
    case idle
    case confirming
    case deleting
    case failed(AccountErrorViewState)
    case succeeded

    var isConfirming: Bool {
        if case .confirming = self {
            return true
        }
        return false
    }

    var isDeleting: Bool {
        if case .deleting = self {
            return true
        }
        return false
    }
}

struct AccountErrorViewState: Equatable {
    let title: String
    let message: String
}

struct AccountActionNotice: Equatable, Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

@MainActor
final class AccountViewModel: ObservableObject {
    typealias AccountDeletionCompletion = @MainActor () async -> Void

    @Published private(set) var state: AccountViewState = .idle
    @Published private(set) var deletionState: AccountDeletionState = .idle
    @Published var actionNotice: AccountActionNotice?

    private let repository: any AccountRepository
    private let accessToken: String?
    private let onAccountDeleted: AccountDeletionCompletion

    init(
        repository: any AccountRepository,
        accessToken: String?,
        onAccountDeleted: @escaping AccountDeletionCompletion = {}
    ) {
        self.repository = repository
        self.accessToken = accessToken
        self.onAccountDeleted = onAccountDeleted
    }

    func loadCurrentUser() async {
        guard !state.isLoading else {
            return
        }

        guard let accessToken, !accessToken.isEmpty else {
            state = .failed(
                AccountErrorViewState(
                    title: "認証が必要です",
                    message: "ログイン状態を確認できませんでした。再ログインしてください。"
                )
            )
            return
        }

        state = .loading

        do {
            let response = try await repository.currentUser(accessToken: accessToken)
            state = .loaded(AccountDisplayUser(response: response))
        } catch {
            state = .failed(Self.errorViewState(from: error))
        }
    }

    func retryCurrentUserLoading() async {
        await loadCurrentUser()
    }

    func requestLogoutPlaceholder() {
        actionNotice = AccountActionNotice(
            title: "ログアウト",
            message: "ログアウト処理は後続 Issue で接続します。この画面では認証情報の削除や通信は行いません。"
        )
    }

    func requestDeleteAccountConfirmation() {
        guard case .loaded = state else {
            deletionState = .failed(
                AccountErrorViewState(
                    title: "認証が必要です",
                    message: "ログイン状態を確認できませんでした。再ログインしてください。"
                )
            )
            return
        }

        guard !deletionState.isDeleting else {
            return
        }

        deletionState = .confirming
    }

    func cancelDeleteAccountConfirmation() {
        guard deletionState.isConfirming else {
            return
        }

        deletionState = .idle
    }

    func confirmDeleteAccount() async {
        guard deletionState.isConfirming else {
            return
        }

        guard let accessToken, !accessToken.isEmpty else {
            deletionState = .failed(
                AccountErrorViewState(
                    title: "認証が必要です",
                    message: "ログイン状態を確認できませんでした。再ログインしてください。"
                )
            )
            return
        }

        deletionState = .deleting

        do {
            try await repository.deleteCurrentUser(accessToken: accessToken)
            deletionState = .succeeded
            await onAccountDeleted()
        } catch is CancellationError {
            deletionState = .idle
        } catch {
            deletionState = .failed(Self.deletionErrorViewState(from: error))
        }
    }

    private static func errorViewState(from error: Error) -> AccountErrorViewState {
        if let repositoryError = error as? AccountRepositoryError,
           repositoryError == .authenticatedSessionUnavailable {
            return AccountErrorViewState(
                title: "認証が必要です",
                message: "ログイン状態を確認できませんでした。再ログインしてください。"
            )
        }

        guard let apiError = error as? FeedmanAPIError else {
            return AccountErrorViewState(
                title: "ユーザー情報を読み込めません",
                message: "通信状況を確認してから再試行してください。"
            )
        }

        switch apiError {
        case .authRequired:
            return AccountErrorViewState(
                title: "認証の有効期限が切れました",
                message: "ログイン状態を更新できませんでした。再ログインしてください。"
            )
        case let .feedmanError(context) where context.statusCode == 401 || context.category == "auth":
            return AccountErrorViewState(
                title: "認証が必要です",
                message: "ログイン状態を確認できませんでした。再ログインしてください。"
            )
        case let .feedmanError(context) where context.statusCode == 429:
            return AccountErrorViewState(
                title: "しばらくしてから再試行してください",
                message: "ユーザー情報の取得が一時的に制限されています。"
            )
        case .feedmanError:
            return AccountErrorViewState(
                title: "ユーザー情報を読み込めません",
                message: "サーバーでエラーが発生しました。しばらくしてから再試行してください。"
            )
        case .transportFailed:
            return AccountErrorViewState(
                title: "通信できません",
                message: "ネットワーク接続を確認してから再試行してください。"
            )
        case .malformedErrorResponse, .successDecodingFailed, .invalidRequestURL, .nonHTTPResponse:
            return AccountErrorViewState(
                title: "ユーザー情報を読み込めません",
                message: "応答を処理できませんでした。しばらくしてから再試行してください。"
            )
        }
    }

    private static func deletionErrorViewState(from error: Error) -> AccountErrorViewState {
        if let repositoryError = error as? AccountRepositoryError,
           repositoryError == .authenticatedSessionUnavailable {
            return AccountErrorViewState(
                title: "認証が必要です",
                message: "ログイン状態を確認できませんでした。再ログインしてください。"
            )
        }

        guard let apiError = error as? FeedmanAPIError else {
            return AccountErrorViewState(
                title: "退会できませんでした",
                message: "通信状況を確認してから再試行してください。"
            )
        }

        switch apiError {
        case .authRequired:
            return AccountErrorViewState(
                title: "認証の有効期限が切れました",
                message: "退会は完了していません。再ログイン後にもう一度お試しください。"
            )
        case let .feedmanError(context) where context.statusCode == 401 || context.category == "auth":
            return AccountErrorViewState(
                title: "認証が必要です",
                message: "退会は完了していません。ログイン状態を確認してから再試行してください。"
            )
        case let .feedmanError(context) where context.statusCode == 429:
            return AccountErrorViewState(
                title: "しばらくしてから再試行してください",
                message: "退会処理が一時的に制限されています。"
            )
        case .feedmanError:
            return AccountErrorViewState(
                title: "退会できませんでした",
                message: "サーバーでエラーが発生しました。しばらくしてから再試行してください。"
            )
        case .transportFailed:
            return AccountErrorViewState(
                title: "通信できません",
                message: "ネットワーク接続を確認してから再試行してください。"
            )
        case .malformedErrorResponse, .successDecodingFailed, .invalidRequestURL, .nonHTTPResponse:
            return AccountErrorViewState(
                title: "退会できませんでした",
                message: "応答を処理できませんでした。しばらくしてから再試行してください。"
            )
        }
    }
}
