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

    func testActionPlaceholdersOnlyShowNotice() {
        let repository = RecordingAccountRepository()
        let viewModel = AccountViewModel(repository: repository, accessToken: "access-1")

        viewModel.requestLogoutPlaceholder()
        XCTAssertEqual(viewModel.actionNotice?.title, "ログアウト")
        XCTAssertTrue(repository.accessTokens.isEmpty)

        viewModel.requestDeleteAccountPlaceholder()
        XCTAssertEqual(viewModel.actionNotice?.title, "退会")
        XCTAssertTrue(repository.accessTokens.isEmpty)
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
}

private final class RecordingAccountRepository: AccountRepository {
    private(set) var accessTokens: [String] = []
    private var results: [Result<UserResponse, Error>]

    init(results: [Result<UserResponse, Error>] = []) {
        self.results = results
    }

    func currentUser(accessToken: String) async throws -> UserResponse {
        accessTokens.append(accessToken)
        if results.isEmpty {
            return userResponse(name: "You", email: "you@example.com")
        }
        return try results.removeFirst().get()
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

    func succeed(with response: UserResponse) {
        continuation?.resume(returning: response)
        continuation = nil
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
