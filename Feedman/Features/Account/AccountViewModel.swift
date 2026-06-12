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
    @Published private(set) var state: AccountViewState = .idle
    @Published var actionNotice: AccountActionNotice?

    private let repository: any AccountRepository
    private let accessToken: String?

    init(repository: any AccountRepository, accessToken: String?) {
        self.repository = repository
        self.accessToken = accessToken
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

    func requestDeleteAccountPlaceholder() {
        actionNotice = AccountActionNotice(
            title: "退会",
            message: "退会処理は後続 Issue で接続します。この画面ではアカウント削除や認証情報の削除は行いません。"
        )
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
}
