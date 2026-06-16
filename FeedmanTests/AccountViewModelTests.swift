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
        XCTAssertEqual(repository.accessTokens, ["access-1"])
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

        XCTAssertEqual(repository.accessTokens, ["access-1"])
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

    func testLogoutPlaceholderOnlyShowsNotice() {
        let repository = RecordingAccountRepository()
        let viewModel = AccountViewModel(repository: repository, accessToken: "access-1")

        viewModel.requestLogoutPlaceholder()
        XCTAssertEqual(viewModel.actionNotice?.title, "ログアウト")
        XCTAssertTrue(repository.accessTokens.isEmpty)
        XCTAssertTrue(repository.deleteAccessTokens.isEmpty)
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
        for _ in 0..<10 where repository.accessTokens.isEmpty {
            await Task.yield()
        }
        XCTAssertFalse(repository.accessTokens.isEmpty, file: file, line: line)
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
private final class RecordingAccountDeletionSession {
    private(set) var completionCount = 0

    func complete() async {
        completionCount += 1
    }
}

private func userResponse(
    id: String = "user-1",
    name: String?,
    email: String?,
    avatarURL: String? = nil
) -> UserResponse {
    UserResponse(
        id: id,
        email: email,
        name: name,
        avatarURL: avatarURL
    )
}

private enum AccountTestError: Error {
    case rejected
}
