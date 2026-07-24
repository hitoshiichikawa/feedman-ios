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
        let trimmedUsername = response.username?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let trimmedEmail = response.email?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if !trimmedName.isEmpty {
            displayName = trimmedName
        } else if !trimmedUsername.isEmpty {
            displayName = trimmedUsername
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

enum AccountLogoutState: Equatable {
    case idle
    case loggingOut
    case failed(AccountErrorViewState)

    var isLoggingOut: Bool {
        if case .loggingOut = self {
            return true
        }
        return false
    }
}

enum PasskeyEnrollmentState: Equatable {
    case idle
    case adding
    case canceled(AccountErrorViewState)
    case failed(AccountErrorViewState)
    case resultUnknown(AccountErrorViewState)
    case succeeded

    var isAdding: Bool {
        if case .adding = self {
            return true
        }
        return false
    }

    var errorState: AccountErrorViewState? {
        switch self {
        case .idle, .adding, .succeeded:
            return nil
        case let .canceled(errorState), let .failed(errorState), let .resultUnknown(errorState):
            return errorState
        }
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

struct AccountPasskeyEnrollmentPresentation: Equatable {
    let addButtonTitle: String
    let addButtonAccessibilityLabel: String
    let isAddDisabled: Bool
    let isAddLoading: Bool
    let isLogoutDisabled: Bool
    let isDeleteDisabled: Bool
    let isDeleteActionHidden: Bool

    init(
        passkeyState: PasskeyEnrollmentState,
        logoutState: AccountLogoutState,
        deletionState: AccountDeletionState
    ) {
        isAddLoading = passkeyState.isAdding
        addButtonTitle = isAddLoading ? "パスキーを追加しています" : "パスキーを追加"
        addButtonAccessibilityLabel = addButtonTitle
        isAddDisabled = passkeyState.isAdding || logoutState.isLoggingOut || deletionState.isConfirming || deletionState.isDeleting
        isLogoutDisabled = logoutState.isLoggingOut || deletionState.isDeleting || passkeyState.isAdding
        isDeleteDisabled = deletionState.isDeleting || passkeyState.isAdding
        isDeleteActionHidden = false
    }
}

@MainActor
final class AccountViewModel: ObservableObject {
    typealias AccountDeletionCompletion = @MainActor () async -> Void
    typealias LogoutCompletion = @MainActor () async throws -> Void

    @Published private(set) var state: AccountViewState = .idle
    @Published private(set) var logoutState: AccountLogoutState = .idle
    @Published private(set) var deletionState: AccountDeletionState = .idle
    @Published private(set) var passkeyEnrollmentState: PasskeyEnrollmentState = .idle
    @Published var actionNotice: AccountActionNotice?

    private let repository: any AccountRepository
    private let accessToken: String?
    private let passkeyRepository: any PasskeyRepository
    private let passkeyCoordinator: any PasskeyPlatformAuthorizationCoordinating
    private let onLogout: LogoutCompletion
    private let onAccountDeleted: AccountDeletionCompletion
    private var passkeyEnrollmentCancellationRequested = false

    init(
        repository: any AccountRepository,
        accessToken: String?,
        passkeyRepository: any PasskeyRepository = UnavailablePasskeyRepository(),
        passkeyCoordinator: any PasskeyPlatformAuthorizationCoordinating = UnavailablePasskeyPlatformAuthorizationCoordinator(),
        onLogout: @escaping LogoutCompletion = {},
        onAccountDeleted: @escaping AccountDeletionCompletion = {}
    ) {
        self.repository = repository
        self.accessToken = accessToken
        self.passkeyRepository = passkeyRepository
        self.passkeyCoordinator = passkeyCoordinator
        self.onLogout = onLogout
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

    func logout() async {
        guard !logoutState.isLoggingOut else {
            return
        }
        guard !passkeyEnrollmentState.isAdding else {
            return
        }

        logoutState = .loggingOut

        do {
            try await onLogout()
            logoutState = .idle
        } catch {
            logoutState = .failed(Self.logoutErrorViewState(from: error))
        }
    }

    func requestDeleteAccountConfirmation() {
        guard !passkeyEnrollmentState.isAdding else {
            return
        }

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
        guard !passkeyEnrollmentState.isAdding else {
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

    func startPasskeyEnrollment() async {
        guard !passkeyEnrollmentState.isAdding else {
            return
        }
        guard !logoutState.isLoggingOut,
              !deletionState.isConfirming,
              !deletionState.isDeleting
        else {
            return
        }

        guard let accessToken, !accessToken.isEmpty else {
            passkeyEnrollmentState = .failed(Self.authRequiredErrorViewState())
            return
        }
        guard case .loaded = state else {
            passkeyEnrollmentState = .failed(Self.authRequiredErrorViewState())
            return
        }

        passkeyEnrollmentCancellationRequested = false
        passkeyEnrollmentState = .adding
        actionNotice = nil

        var didDispatchFinish = false
        do {
            let beginResponse = try await passkeyRepository.beginAddRegistration(accessToken: accessToken)
            try ensurePasskeyEnrollmentNotCanceled()
            let credential = try await passkeyCoordinator.performRegistration(
                options: beginResponse.options.publicKey
            )
            try ensurePasskeyEnrollmentNotCanceled()
            didDispatchFinish = true
            try await passkeyRepository.finishAddRegistration(
                challengeID: beginResponse.challengeID,
                credential: credential,
                accessToken: accessToken
            )
            passkeyEnrollmentState = .succeeded
            actionNotice = AccountActionNotice(
                title: "パスキーを追加しました",
                message: "次回からこのアカウントにパスキーでログインできます。"
            )
        } catch is CancellationError {
            if didDispatchFinish {
                passkeyEnrollmentState = .resultUnknown(Self.passkeyResultUnknownViewState())
            } else {
                passkeyEnrollmentState = .canceled(Self.passkeyCanceledViewState())
            }
        } catch PasskeyPlatformAuthorizationError.canceled {
            passkeyEnrollmentState = .canceled(Self.passkeyCanceledViewState())
        } catch {
            if didDispatchFinish, Self.isResultUnknownFinishError(error) {
                passkeyEnrollmentState = .resultUnknown(Self.passkeyResultUnknownViewState())
            } else {
                passkeyEnrollmentState = .failed(Self.passkeyErrorViewState(from: error))
            }
        }
    }

    func cancelActivePasskeyEnrollment() {
        passkeyEnrollmentCancellationRequested = true
        passkeyCoordinator.cancelActiveAuthorization()
    }

    private func ensurePasskeyEnrollmentNotCanceled() throws {
        if passkeyEnrollmentCancellationRequested || Task.isCancelled {
            throw CancellationError()
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

    private static func logoutErrorViewState(from error: Error) -> AccountErrorViewState {
        guard let apiError = error as? FeedmanAPIError else {
            return AccountErrorViewState(
                title: "ログアウトできませんでした",
                message: "通信状況を確認してから再試行してください。"
            )
        }

        switch apiError {
        case .transportFailed:
            return AccountErrorViewState(
                title: "通信できません",
                message: "ネットワーク接続を確認してから再試行してください。"
            )
        default:
            return AccountErrorViewState(
                title: "ログアウトできませんでした",
                message: "応答を処理できませんでした。しばらくしてから再試行してください。"
            )
        }
    }

    private static func passkeyErrorViewState(from error: Error) -> AccountErrorViewState {
        if let repositoryError = error as? AccountRepositoryError,
           repositoryError == .authenticatedSessionUnavailable {
            return authRequiredErrorViewState()
        }

        if let platformError = error as? PasskeyPlatformAuthorizationError {
            switch platformError {
            case .presentationAnchorUnavailable, .authorizationFailed, .authorizationAlreadyActive,
                 .invalidOptions, .invalidCredentialType:
                return AccountErrorViewState(
                    title: "パスキーを追加できませんでした",
                    message: "現在のログイン状態は維持されています。時間をおいてから再試行してください。"
                )
            case .canceled:
                return passkeyCanceledViewState()
            }
        }

        guard let apiError = error as? FeedmanAPIError else {
            return AccountErrorViewState(
                title: "パスキーを追加できませんでした",
                message: "通信状況を確認してから再試行してください。"
            )
        }

        switch apiError {
        case .authRequired:
            return AccountErrorViewState(
                title: "認証の有効期限が切れました",
                message: "パスキーは追加されていません。再ログイン後にもう一度お試しください。"
            )
        case let .feedmanError(context) where context.statusCode == 401 || context.category == "auth":
            return authRequiredErrorViewState()
        case let .feedmanError(context) where context.statusCode == 429:
            return AccountErrorViewState(
                title: "しばらくしてから再試行してください",
                message: "パスキー追加が一時的に制限されています。"
            )
        case .feedmanError:
            return AccountErrorViewState(
                title: "パスキーを追加できませんでした",
                message: "サーバーでエラーが発生しました。現在のログイン状態は維持されています。"
            )
        case .transportFailed:
            return AccountErrorViewState(
                title: "通信できません",
                message: "ネットワーク接続を確認してから再試行してください。"
            )
        case .malformedErrorResponse, .successDecodingFailed, .invalidRequestURL, .nonHTTPResponse:
            return AccountErrorViewState(
                title: "パスキーを追加できませんでした",
                message: "応答を処理できませんでした。しばらくしてから再試行してください。"
            )
        }
    }

    private static func isResultUnknownFinishError(_ error: Error) -> Bool {
        guard let apiError = error as? FeedmanAPIError else {
            return false
        }

        switch apiError {
        case .transportFailed, .successDecodingFailed, .malformedErrorResponse, .nonHTTPResponse:
            return true
        case .authRequired, .feedmanError, .invalidRequestURL:
            return false
        }
    }

    private static func authRequiredErrorViewState() -> AccountErrorViewState {
        AccountErrorViewState(
            title: "認証が必要です",
            message: "ログイン状態を確認できませんでした。再ログインしてください。"
        )
    }

    private static func passkeyCanceledViewState() -> AccountErrorViewState {
        AccountErrorViewState(
            title: "パスキー追加をキャンセルしました",
            message: "現在のログイン状態は維持されています。必要なときにもう一度お試しください。"
        )
    }

    private static func passkeyResultUnknownViewState() -> AccountErrorViewState {
        AccountErrorViewState(
            title: "パスキー追加結果を確認できません",
            message: "現在のログイン状態は維持されています。追加済みかどうかは再試行または次回のパスキーログインで照合してください。"
        )
    }
}
