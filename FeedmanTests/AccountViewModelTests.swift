import XCTest
@testable import Feedman

@MainActor
final class AccountViewModelTests: XCTestCase {
    func testLoadCurrentUserShowsLoadingThenSuccess() async throws {
        let repository = PendingAccountRepository()
        let viewModel = AccountViewModel(repository: repository, accessToken: "access-1")

        let task = Task {
            await viewModel.loadCurrentUser()
        }
        await waitForRequest(repository)

        XCTAssertEqual(viewModel.state, .loading)
        repository.succeed(with: userResponse(name: "  Hitoshi  ", email: " hitoshi@example.com "))
        await task.value

        XCTAssertEqual(
            viewModel.state,
            .loaded(
                AccountDisplayUser(
                    response: userResponse(name: "  Hitoshi  ", email: " hitoshi@example.com ")
                )
            )
        )
        XCTAssertEqual(repository.recordedAccessTokens(), ["access-1"])
    }

    func testMissingAccessTokenShowsAuthErrorWithoutRequest() async {
        let repository = RecordingAccountRepository()
        let viewModel = AccountViewModel(repository: repository, accessToken: nil)

        await viewModel.loadCurrentUser()

        XCTAssertTrue(repository.accessTokens.isEmpty)
        XCTAssertEqual(
            viewModel.state,
            .failed(
                AccountErrorViewState(
                    title: "認証が必要です",
                    message: "ログイン状態を確認できませんでした。再ログインしてください。"
                )
            )
        )
    }

    func testFailureShowsRetryableError() async {
        let repository = RecordingAccountRepository(results: [
            .failure(AccountTestError.rejected)
        ])
        let viewModel = AccountViewModel(repository: repository, accessToken: "access-1")

        await viewModel.loadCurrentUser()

        XCTAssertEqual(repository.accessTokens, ["access-1"])
        XCTAssertEqual(
            viewModel.state,
            .failed(
                AccountErrorViewState(
                    title: "ユーザー情報を読み込めません",
                    message: "通信状況を確認してから再試行してください。"
                )
            )
        )
    }

    func testCurrentUserAuthRequiredShowsAuthBoundaryError() async {
        let repository = RecordingAccountRepository(results: [
            .failure(Self.authRequiredError)
        ])
        let viewModel = AccountViewModel(repository: repository, accessToken: "access-1")

        await viewModel.loadCurrentUser()

        XCTAssertEqual(repository.accessTokens, ["access-1"])
        XCTAssertEqual(
            viewModel.state,
            .failed(
                AccountErrorViewState(
                    title: "認証の有効期限が切れました",
                    message: "ログイン状態を更新できませんでした。再ログインしてください。"
                )
            )
        )
    }

    func testRetryRunsCurrentUserLoadingAgain() async {
        let repository = RecordingAccountRepository(results: [
            .failure(AccountTestError.rejected),
            .success(userResponse(name: nil, email: "user@example.com"))
        ])
        let viewModel = AccountViewModel(repository: repository, accessToken: "access-1")

        await viewModel.loadCurrentUser()
        await viewModel.retryCurrentUserLoading()

        XCTAssertEqual(repository.accessTokens, ["access-1", "access-1"])
        XCTAssertEqual(
            viewModel.state,
            .loaded(AccountDisplayUser(response: userResponse(name: nil, email: "user@example.com")))
        )
    }

    func testDuplicateLoadWhileLoadingDoesNotStartSecondRequest() async {
        let repository = PendingAccountRepository()
        let viewModel = AccountViewModel(repository: repository, accessToken: "access-1")

        let task = Task {
            await viewModel.loadCurrentUser()
        }
        await waitForRequest(repository)

        await viewModel.loadCurrentUser()

        XCTAssertEqual(repository.recordedAccessTokens(), ["access-1"])
        repository.succeed(with: userResponse(name: "You", email: "you@example.com"))
        await task.value
    }

    func testDisplayUserFallsBackToEmailAndHidesBlankEmail() {
        let emailFallback = AccountDisplayUser(
            response: userResponse(name: "   ", email: "you@example.com")
        )
        let missingEmail = AccountDisplayUser(
            response: userResponse(name: "You", email: "   ")
        )

        XCTAssertEqual(emailFallback.displayName, "you@example.com")
        XCTAssertEqual(emailFallback.email, "you@example.com")
        XCTAssertEqual(missingEmail.displayName, "You")
        XCTAssertNil(missingEmail.email)
    }

    func testDisplayUserPrefersNameThenUsernameThenEmailThenFallback() {
        XCTAssertEqual(
            AccountDisplayUser(response: userResponse(username: "reader", name: "  Hitoshi  ", email: "you@example.com")).displayName,
            "Hitoshi"
        )
        XCTAssertEqual(
            AccountDisplayUser(response: userResponse(username: "  reader  ", name: "  ", email: "you@example.com")).displayName,
            "reader"
        )
        XCTAssertEqual(
            AccountDisplayUser(response: userResponse(username: "  ", name: nil, email: " you@example.com ")).displayName,
            "you@example.com"
        )
        XCTAssertEqual(
            AccountDisplayUser(response: userResponse(username: nil, name: nil, email: nil)).displayName,
            "ログイン中のユーザー"
        )
    }

    func testPasskeyEnrollmentPresentationKeepsDeleteActionVisibleAndDisablesDuringAdd() {
        let idle = AccountPasskeyEnrollmentPresentation(
            passkeyState: .idle,
            logoutState: .idle,
            deletionState: .idle
        )
        let adding = AccountPasskeyEnrollmentPresentation(
            passkeyState: .adding,
            logoutState: .idle,
            deletionState: .idle
        )

        XCTAssertEqual(idle.addButtonTitle, "パスキーを追加")
        XCTAssertFalse(idle.isDeleteActionHidden)
        XCTAssertFalse(idle.isAddDisabled)
        XCTAssertTrue(adding.isAddLoading)
        XCTAssertTrue(adding.isLogoutDisabled)
        XCTAssertTrue(adding.isDeleteDisabled)
        XCTAssertFalse(adding.isDeleteActionHidden)
    }

    func testPasskeyEnrollmentSuccessShowsNoticeAndPreservesSession() async {
        let repository = RecordingAccountRepository()
        let passkeyRepository = RecordingAccountPasskeyRepository()
        let passkeyCoordinator = RecordingAccountPasskeyCoordinator(registrationEnvelope: .accountRegistration(rawID: "credential-1"))
        let viewModel = AccountViewModel(
            repository: repository,
            accessToken: "access-1",
            passkeyRepository: passkeyRepository,
            passkeyCoordinator: passkeyCoordinator
        )
        await viewModel.loadCurrentUser()
        let loadedState = viewModel.state

        await viewModel.startPasskeyEnrollment()

        XCTAssertEqual(passkeyRepository.beginAddAccessTokens, ["access-1"])
        XCTAssertEqual(passkeyCoordinator.registrationRequests.map(\.rp.id), ["example.com"])
        XCTAssertEqual(passkeyRepository.finishAddCalls, [
            AccountPasskeyFinishCall(challengeID: "add-challenge-1", rawID: "credential-1", accessToken: "access-1")
        ])
        XCTAssertEqual(viewModel.passkeyEnrollmentState, .succeeded)
        XCTAssertEqual(viewModel.actionNotice?.title, "パスキーを追加しました")
        XCTAssertEqual(viewModel.state, loadedState)
        XCTAssertTrue(repository.deleteAccessTokens.isEmpty)
    }

    func testPasskeyEnrollmentMissingTokenFailsWithoutRequest() async {
        let passkeyRepository = RecordingAccountPasskeyRepository()
        let viewModel = AccountViewModel(
            repository: RecordingAccountRepository(),
            accessToken: nil,
            passkeyRepository: passkeyRepository,
            passkeyCoordinator: RecordingAccountPasskeyCoordinator()
        )

        await viewModel.startPasskeyEnrollment()

        XCTAssertTrue(passkeyRepository.beginAddAccessTokens.isEmpty)
        XCTAssertEqual(
            viewModel.passkeyEnrollmentState,
            .failed(AccountErrorViewState(
                title: "認証が必要です",
                message: "ログイン状態を確認できませんでした。再ログインしてください。"
            ))
        )
    }

    func testPasskeyEnrollmentCancellationBeforeFinishSkipsFinishAndPreservesSession() async {
        let passkeyRepository = RecordingAccountPasskeyRepository()
        let passkeyCoordinator = CancelingAccountPasskeyCoordinator(viewModelProvider: { nil })
        let viewModel = AccountViewModel(
            repository: RecordingAccountRepository(),
            accessToken: "access-1",
            passkeyRepository: passkeyRepository,
            passkeyCoordinator: passkeyCoordinator
        )
        passkeyCoordinator.viewModelProvider = { viewModel }
        await viewModel.loadCurrentUser()
        let loadedState = viewModel.state

        await viewModel.startPasskeyEnrollment()

        XCTAssertTrue(passkeyRepository.finishAddCalls.isEmpty)
        XCTAssertEqual(passkeyCoordinator.cancelActiveAuthorizationCount, 1)
        XCTAssertEqual(viewModel.passkeyEnrollmentState, .canceled(AccountErrorViewState(
            title: "パスキー追加をキャンセルしました",
            message: "現在のログイン状態は維持されています。必要なときにもう一度お試しください。"
        )))
        XCTAssertEqual(viewModel.state, loadedState)
    }

    func testPasskeyEnrollmentFinishCancellationIsResultUnknownAndPreservesSession() async {
        let passkeyRepository = RecordingAccountPasskeyRepository(
            finishAddResult: .failure(CancellationError())
        )
        let viewModel = AccountViewModel(
            repository: RecordingAccountRepository(),
            accessToken: "access-1",
            passkeyRepository: passkeyRepository,
            passkeyCoordinator: RecordingAccountPasskeyCoordinator(registrationEnvelope: .accountRegistration(rawID: "credential-1"))
        )
        await viewModel.loadCurrentUser()
        let loadedState = viewModel.state

        await viewModel.startPasskeyEnrollment()

        XCTAssertEqual(passkeyRepository.finishAddCalls.count, 1)
        XCTAssertEqual(viewModel.passkeyEnrollmentState, .resultUnknown(AccountErrorViewState(
            title: "パスキー追加結果を確認できません",
            message: "現在のログイン状態は維持されています。追加済みかどうかは再試行または次回のパスキーログインで照合してください。"
        )))
        XCTAssertEqual(viewModel.state, loadedState)
    }

    func testPasskeyEnrollmentFinishDecodeFailureIsResultUnknown() async {
        let passkeyRepository = RecordingAccountPasskeyRepository(
            finishAddResult: .failure(FeedmanAPIError.successDecodingFailed(underlyingError: AccountTestError.rejected))
        )
        let viewModel = AccountViewModel(
            repository: RecordingAccountRepository(),
            accessToken: "access-1",
            passkeyRepository: passkeyRepository,
            passkeyCoordinator: RecordingAccountPasskeyCoordinator(registrationEnvelope: .accountRegistration(rawID: "credential-1"))
        )
        await viewModel.loadCurrentUser()

        await viewModel.startPasskeyEnrollment()

        XCTAssertEqual(passkeyRepository.finishAddCalls.count, 1)
        XCTAssertEqual(viewModel.passkeyEnrollmentState.errorState?.title, "パスキー追加結果を確認できません")
    }

    func testPasskeyEnrollmentMapsAuthRequiredRateLimitAndServerFailure() async {
        let authRequired = AccountViewModel(
            repository: RecordingAccountRepository(),
            accessToken: "access-1",
            passkeyRepository: RecordingAccountPasskeyRepository(beginAddResult: .failure(Self.authRequiredError)),
            passkeyCoordinator: RecordingAccountPasskeyCoordinator()
        )
        await authRequired.loadCurrentUser()
        await authRequired.startPasskeyEnrollment()

        let rateLimited = AccountViewModel(
            repository: RecordingAccountRepository(),
            accessToken: "access-1",
            passkeyRepository: RecordingAccountPasskeyRepository(beginAddResult: .failure(Self.feedmanError(code: "RATE_LIMITED", statusCode: 429))),
            passkeyCoordinator: RecordingAccountPasskeyCoordinator()
        )
        await rateLimited.loadCurrentUser()
        await rateLimited.startPasskeyEnrollment()

        let serverFailed = AccountViewModel(
            repository: RecordingAccountRepository(),
            accessToken: "access-1",
            passkeyRepository: RecordingAccountPasskeyRepository(beginAddResult: .failure(Self.feedmanError(code: "SERVER_ERROR", statusCode: 500))),
            passkeyCoordinator: RecordingAccountPasskeyCoordinator()
        )
        await serverFailed.loadCurrentUser()
        await serverFailed.startPasskeyEnrollment()

        XCTAssertEqual(authRequired.passkeyEnrollmentState.errorState?.title, "認証の有効期限が切れました")
        XCTAssertEqual(rateLimited.passkeyEnrollmentState.errorState?.title, "しばらくしてから再試行してください")
        XCTAssertEqual(serverFailed.passkeyEnrollmentState.errorState?.title, "パスキーを追加できませんでした")
    }

    func testPasskeyEnrollmentDuplicateAndLogoutDeleteGuards() async {
        let passkeyRepository = SlowAccountPasskeyRepository()
        let viewModel = AccountViewModel(
            repository: RecordingAccountRepository(),
            accessToken: "access-1",
            passkeyRepository: passkeyRepository,
            passkeyCoordinator: RecordingAccountPasskeyCoordinator()
        )
        await viewModel.loadCurrentUser()

        let task = Task {
            await viewModel.startPasskeyEnrollment()
        }
        await waitForPasskeyAddingState(viewModel)
        await viewModel.startPasskeyEnrollment()
        await viewModel.logout()
        viewModel.requestDeleteAccountConfirmation()

        XCTAssertEqual(passkeyRepository.beginAddAccessTokens, ["access-1"])
        XCTAssertEqual(viewModel.logoutState, .idle)
        XCTAssertEqual(viewModel.deletionState, .idle)
        passkeyRepository.succeedBegin()
        await task.value

        let loggingOut = AccountViewModel(
            repository: RecordingAccountRepository(),
            accessToken: "access-1",
            passkeyRepository: RecordingAccountPasskeyRepository(),
            passkeyCoordinator: RecordingAccountPasskeyCoordinator(),
            onLogout: {
                try await Task.sleep(nanoseconds: 20_000_000)
            }
        )
        let logoutTask = Task {
            await loggingOut.logout()
        }
        await waitForLoggingOutState(loggingOut)
        await loggingOut.startPasskeyEnrollment()
        XCTAssertEqual(loggingOut.passkeyEnrollmentState, .idle)
        logoutTask.cancel()
        await logoutTask.value
    }

    func testDeleteAccountFlowIsUnchangedAfterPasskeySupport() async {
        let repository = RecordingAccountRepository(deleteResults: [.success(())])
        let session = RecordingAccountDeletionSession()
        let viewModel = AccountViewModel(
            repository: repository,
            accessToken: "access-1",
            passkeyRepository: RecordingAccountPasskeyRepository(),
            passkeyCoordinator: RecordingAccountPasskeyCoordinator(),
            onAccountDeleted: {
                await session.complete()
            }
        )
        await viewModel.loadCurrentUser()

        viewModel.requestDeleteAccountConfirmation()
        await viewModel.confirmDeleteAccount()

        XCTAssertEqual(repository.deleteAccessTokens, ["access-1"])
        XCTAssertEqual(viewModel.deletionState, .succeeded)
        XCTAssertEqual(session.completionCount, 1)
    }

    func testLogoutRunsCompletionWithoutAccountRepositoryRequest() async {
        let repository = RecordingAccountRepository()
        let session = RecordingLogoutSession()
        let viewModel = AccountViewModel(
            repository: repository,
            accessToken: "access-1",
            onLogout: {
                await session.complete()
            }
        )

        await viewModel.logout()

        XCTAssertEqual(viewModel.logoutState, .idle)
        XCTAssertEqual(session.completionCount, 1)
        XCTAssertTrue(repository.accessTokens.isEmpty)
        XCTAssertTrue(repository.deleteAccessTokens.isEmpty)
    }

    func testLogoutFailureShowsRetryableError() async {
        let repository = RecordingAccountRepository()
        let viewModel = AccountViewModel(
            repository: repository,
            accessToken: "access-1",
            onLogout: {
                throw AccountTestError.rejected
            }
        )

        await viewModel.logout()

        XCTAssertEqual(
            viewModel.logoutState,
            .failed(
                AccountErrorViewState(
                    title: "ログアウトできませんでした",
                    message: "通信状況を確認してから再試行してください。"
                )
            )
        )
    }

    func testDeleteAccountActionShowsConfirmation() async {
        let repository = RecordingAccountRepository()
        let viewModel = AccountViewModel(repository: repository, accessToken: "access-1")
        await viewModel.loadCurrentUser()

        viewModel.requestDeleteAccountConfirmation()

        XCTAssertEqual(viewModel.deletionState, .confirming)
        XCTAssertTrue(repository.deleteAccessTokens.isEmpty)
    }

    func testCancelDeleteAccountConfirmationDoesNotRequestOrCompleteSession() async {
        let repository = RecordingAccountRepository()
        let session = RecordingAccountDeletionSession()
        let viewModel = AccountViewModel(
            repository: repository,
            accessToken: "access-1",
            onAccountDeleted: {
                await session.complete()
            }
        )
        await viewModel.loadCurrentUser()

        viewModel.requestDeleteAccountConfirmation()
        viewModel.cancelDeleteAccountConfirmation()

        XCTAssertEqual(viewModel.deletionState, .idle)
        XCTAssertTrue(repository.deleteAccessTokens.isEmpty)
        XCTAssertEqual(session.completionCount, 0)
    }

    func testConfirmDeleteAccountSuccessRequestsDeleteAndCompletesSession() async {
        let repository = RecordingAccountRepository(deleteResults: [
            .success(())
        ])
        let session = RecordingAccountDeletionSession()
        let viewModel = AccountViewModel(
            repository: repository,
            accessToken: "access-1",
            onAccountDeleted: {
                await session.complete()
            }
        )
        await viewModel.loadCurrentUser()

        viewModel.requestDeleteAccountConfirmation()
        await viewModel.confirmDeleteAccount()

        XCTAssertEqual(repository.deleteAccessTokens, ["access-1"])
        XCTAssertEqual(viewModel.deletionState, .succeeded)
        XCTAssertEqual(session.completionCount, 1)
    }

    func testConfirmDeleteAccountFailurePreservesSessionAndShowsError() async {
        let repository = RecordingAccountRepository(deleteResults: [
            .failure(AccountTestError.rejected)
        ])
        let session = RecordingAccountDeletionSession()
        let viewModel = AccountViewModel(
            repository: repository,
            accessToken: "access-1",
            onAccountDeleted: {
                await session.complete()
            }
        )
        await viewModel.loadCurrentUser()

        viewModel.requestDeleteAccountConfirmation()
        await viewModel.confirmDeleteAccount()

        XCTAssertEqual(repository.deleteAccessTokens, ["access-1"])
        XCTAssertEqual(
            viewModel.deletionState,
            .failed(
                AccountErrorViewState(
                    title: "退会できませんでした",
                    message: "通信状況を確認してから再試行してください。"
                )
            )
        )
        XCTAssertEqual(session.completionCount, 0)
    }

    func testConfirmDeleteAccountAuthRequiredPreservesLoadedUserAndDoesNotCompleteSession() async {
        let repository = RecordingAccountRepository(deleteResults: [
            .failure(Self.authRequiredError)
        ])
        let session = RecordingAccountDeletionSession()
        let viewModel = AccountViewModel(
            repository: repository,
            accessToken: "access-1",
            onAccountDeleted: {
                await session.complete()
            }
        )
        await viewModel.loadCurrentUser()
        let loadedState = viewModel.state

        viewModel.requestDeleteAccountConfirmation()
        await viewModel.confirmDeleteAccount()

        XCTAssertEqual(repository.deleteAccessTokens, ["access-1"])
        XCTAssertEqual(viewModel.state, loadedState)
        XCTAssertEqual(
            viewModel.deletionState,
            .failed(
                AccountErrorViewState(
                    title: "認証の有効期限が切れました",
                    message: "退会は完了していません。再ログイン後にもう一度お試しください。"
                )
            )
        )
        XCTAssertEqual(session.completionCount, 0)
    }

    func testDuplicateDeleteConfirmationWhileDeletingDoesNotStartSecondRequest() async {
        let repository = SlowDeletingAccountRepository()
        let session = RecordingAccountDeletionSession()
        let viewModel = AccountViewModel(
            repository: repository,
            accessToken: "access-1",
            onAccountDeleted: {
                await session.complete()
            }
        )
        await viewModel.loadCurrentUser()

        viewModel.requestDeleteAccountConfirmation()
        let task = Task {
            await viewModel.confirmDeleteAccount()
        }
        await waitForDeletingState(viewModel)

        await viewModel.confirmDeleteAccount()

        XCTAssertEqual(repository.deleteAccessTokens, ["access-1"])
        await task.value
        XCTAssertEqual(session.completionCount, 1)
    }

    private func waitForRequest(
        _ repository: PendingAccountRepository,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        for _ in 0..<50 where !repository.hasPendingRequest {
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        XCTAssertTrue(repository.hasPendingRequest, file: file, line: line)
    }

    private func waitForDeletingState(
        _ viewModel: AccountViewModel,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        for _ in 0..<50 where !viewModel.deletionState.isDeleting {
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        XCTAssertTrue(viewModel.deletionState.isDeleting, file: file, line: line)
    }

    private func waitForPasskeyAddingState(
        _ viewModel: AccountViewModel,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        for _ in 0..<50 where !viewModel.passkeyEnrollmentState.isAdding {
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        XCTAssertTrue(viewModel.passkeyEnrollmentState.isAdding, file: file, line: line)
    }

    private func waitForLoggingOutState(
        _ viewModel: AccountViewModel,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        for _ in 0..<50 where !viewModel.logoutState.isLoggingOut {
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        XCTAssertTrue(viewModel.logoutState.isLoggingOut, file: file, line: line)
    }

    private static let authRequiredError = FeedmanAPIError.authRequired(
        AuthRequiredContext(
            reason: .missingRefreshHook,
            statusCode: 401,
            underlyingError: nil
        )
    )

    private static func feedmanError(code: String, statusCode: Int) -> FeedmanAPIError {
        FeedmanAPIError.feedmanError(
            FeedmanErrorContext(
                statusCode: statusCode,
                body: FeedmanErrorBody(
                    code: code,
                    message: code,
                    category: "passkey",
                    action: "retry",
                    details: nil
                ),
                retryAfter: nil
            )
        )
    }
}

private final class RecordingAccountRepository: AccountRepository {
    private(set) var accessTokens: [String] = []
    private(set) var deleteAccessTokens: [String] = []
    private var results: [Result<UserResponse, Error>]
    private var deleteResults: [Result<Void, Error>]

    init(
        results: [Result<UserResponse, Error>] = [],
        deleteResults: [Result<Void, Error>] = []
    ) {
        self.results = results
        self.deleteResults = deleteResults
    }

    func currentUser(accessToken: String) async throws -> UserResponse {
        accessTokens.append(accessToken)
        if results.isEmpty {
            return userResponse(name: "You", email: "you@example.com")
        }
        return try results.removeFirst().get()
    }

    func deleteCurrentUser(accessToken: String) async throws {
        deleteAccessTokens.append(accessToken)
        if deleteResults.isEmpty {
            return
        }
        try deleteResults.removeFirst().get()
    }
}

private final class PendingAccountRepository: AccountRepository {
    private(set) var accessTokens: [String] = []
    private var continuation: CheckedContinuation<UserResponse, Error>?

    var hasPendingRequest: Bool {
        continuation != nil
    }

    func currentUser(accessToken: String) async throws -> UserResponse {
        accessTokens.append(accessToken)
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
        }
    }

    func deleteCurrentUser(accessToken: String) async throws {
        throw AccountRepositoryError.authenticatedSessionUnavailable
    }

    func succeed(with response: UserResponse) {
        continuation?.resume(returning: response)
        continuation = nil
    }

    func recordedAccessTokens() -> [String] {
        accessTokens
    }
}

private final class SlowDeletingAccountRepository: AccountRepository {
    private(set) var accessTokens: [String] = []
    private(set) var deleteAccessTokens: [String] = []

    func currentUser(accessToken: String) async throws -> UserResponse {
        accessTokens.append(accessToken)
        return userResponse(name: "You", email: "you@example.com")
    }

    func deleteCurrentUser(accessToken: String) async throws {
        deleteAccessTokens.append(accessToken)
        try await Task.sleep(nanoseconds: 50_000_000)
    }
}

@MainActor
private final class RecordingLogoutSession {
    private(set) var completionCount = 0

    func complete() async {
        completionCount += 1
    }
}

@MainActor
private final class RecordingAccountDeletionSession {
    private(set) var completionCount = 0

    func complete() async {
        completionCount += 1
    }
}

private func userResponse(
    id: String = "user-1",
    username: String? = nil,
    name: String?,
    email: String?,
    avatarURL: String? = nil
) -> UserResponse {
    UserResponse(
        id: id,
        username: username,
        email: email,
        name: name,
        avatarURL: avatarURL
    )
}

private enum AccountTestError: Error {
    case rejected
}

private struct AccountPasskeyFinishCall: Equatable {
    let challengeID: String
    let rawID: String
    let accessToken: String
}

private final class RecordingAccountPasskeyRepository: PasskeyRepository {
    private(set) var beginAddAccessTokens: [String] = []
    private(set) var finishAddCalls: [AccountPasskeyFinishCall] = []

    private let beginAddResult: Result<PasskeyAddRegistrationBeginResponse, Error>
    private let finishAddResult: Result<Void, Error>

    init(
        beginAddResult: Result<PasskeyAddRegistrationBeginResponse, Error> = .success(.accountAddBegin()),
        finishAddResult: Result<Void, Error> = .success(())
    ) {
        self.beginAddResult = beginAddResult
        self.finishAddResult = finishAddResult
    }

    func beginRegistration(
        username: String,
        codeChallenge: String
    ) async throws -> PasskeyRegistrationBeginResponse {
        throw PasskeyRepositoryError.unavailable
    }

    func finishRegistration(
        challengeID: String,
        credential: PasskeyCredentialEnvelope
    ) async throws -> PasskeyRegistrationFinishResponse {
        throw PasskeyRepositoryError.unavailable
    }

    func beginAuthentication(codeChallenge: String) async throws -> PasskeyAuthenticationBeginResponse {
        throw PasskeyRepositoryError.unavailable
    }

    func finishAuthentication(
        challengeID: String,
        credential: PasskeyCredentialEnvelope
    ) async throws -> PasskeyAuthenticationFinishResponse {
        throw PasskeyRepositoryError.unavailable
    }

    func beginAddRegistration(accessToken: String) async throws -> PasskeyAddRegistrationBeginResponse {
        beginAddAccessTokens.append(accessToken)
        return try beginAddResult.get()
    }

    func finishAddRegistration(
        challengeID: String,
        credential: PasskeyCredentialEnvelope,
        accessToken: String
    ) async throws {
        finishAddCalls.append(AccountPasskeyFinishCall(
            challengeID: challengeID,
            rawID: credential.rawID,
            accessToken: accessToken
        ))
        try finishAddResult.get()
    }
}

private final class SlowAccountPasskeyRepository: PasskeyRepository {
    private(set) var beginAddAccessTokens: [String] = []
    private var continuation: CheckedContinuation<PasskeyAddRegistrationBeginResponse, Error>?

    func beginRegistration(
        username: String,
        codeChallenge: String
    ) async throws -> PasskeyRegistrationBeginResponse {
        throw PasskeyRepositoryError.unavailable
    }

    func finishRegistration(
        challengeID: String,
        credential: PasskeyCredentialEnvelope
    ) async throws -> PasskeyRegistrationFinishResponse {
        throw PasskeyRepositoryError.unavailable
    }

    func beginAuthentication(codeChallenge: String) async throws -> PasskeyAuthenticationBeginResponse {
        throw PasskeyRepositoryError.unavailable
    }

    func finishAuthentication(
        challengeID: String,
        credential: PasskeyCredentialEnvelope
    ) async throws -> PasskeyAuthenticationFinishResponse {
        throw PasskeyRepositoryError.unavailable
    }

    func beginAddRegistration(accessToken: String) async throws -> PasskeyAddRegistrationBeginResponse {
        beginAddAccessTokens.append(accessToken)
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
        }
    }

    func finishAddRegistration(
        challengeID: String,
        credential: PasskeyCredentialEnvelope,
        accessToken: String
    ) async throws {}

    func succeedBegin() {
        continuation?.resume(returning: .accountAddBegin())
        continuation = nil
    }
}

@MainActor
private class RecordingAccountPasskeyCoordinator: PasskeyPlatformAuthorizationCoordinating {
    private(set) var registrationRequests: [PasskeyPublicKeyCredentialCreationOptions] = []
    private(set) var cancelActiveAuthorizationCount = 0

    private let registrationEnvelope: PasskeyCredentialEnvelope
    private let registrationError: Error?

    init(
        registrationEnvelope: PasskeyCredentialEnvelope = .accountRegistration(rawID: "credential-1"),
        registrationError: Error? = nil
    ) {
        self.registrationEnvelope = registrationEnvelope
        self.registrationError = registrationError
    }

    func performRegistration(
        options: PasskeyPublicKeyCredentialCreationOptions
    ) async throws -> PasskeyCredentialEnvelope {
        registrationRequests.append(options)
        if let registrationError {
            throw registrationError
        }
        return registrationEnvelope
    }

    func performAssertion(
        options: PasskeyPublicKeyCredentialRequestOptions,
        allowedCredentialID: String?
    ) async throws -> PasskeyCredentialEnvelope {
        throw PasskeyRepositoryError.unavailable
    }

    func cancelActiveAuthorization() {
        cancelActiveAuthorizationCount += 1
    }
}

@MainActor
private final class CancelingAccountPasskeyCoordinator: RecordingAccountPasskeyCoordinator {
    var viewModelProvider: () -> AccountViewModel?

    init(viewModelProvider: @escaping () -> AccountViewModel?) {
        self.viewModelProvider = viewModelProvider
        super.init(registrationEnvelope: .accountRegistration(rawID: "credential-1"))
    }

    override func performRegistration(
        options: PasskeyPublicKeyCredentialCreationOptions
    ) async throws -> PasskeyCredentialEnvelope {
        let envelope = try await super.performRegistration(options: options)
        viewModelProvider()?.cancelActivePasskeyEnrollment()
        return envelope
    }
}

private extension PasskeyAddRegistrationBeginResponse {
    static func accountAddBegin() -> PasskeyAddRegistrationBeginResponse {
        PasskeyAddRegistrationBeginResponse(
            challengeID: "add-challenge-1",
            options: PasskeyPublicKeyCredentialCreationOptionsEnvelope(
                publicKey: PasskeyPublicKeyCredentialCreationOptions(
                    challenge: "Y2hhbGxlbmdl",
                    rp: PasskeyRelyingParty(id: "example.com", name: "Feedman"),
                    user: PasskeyUserEntity(id: "dXNlci0x", name: "reader", displayName: "reader"),
                    pubKeyCredParams: [
                        PasskeyPublicKeyCredentialParameter(type: "public-key", alg: -7)
                    ],
                    timeout: nil,
                    excludeCredentials: nil,
                    authenticatorSelection: nil,
                    attestation: nil
                )
            )
        )
    }
}

private extension PasskeyCredentialEnvelope {
    static func accountRegistration(rawID: String) -> PasskeyCredentialEnvelope {
        PasskeyCredentialEnvelope(
            id: rawID,
            rawID: rawID,
            type: "public-key",
            response: .registration(PasskeyRegistrationCredentialResponse(
                clientDataJSON: "Y2xpZW50",
                attestationObject: "YXR0ZXN0YXRpb24"
            ))
        )
    }
}
