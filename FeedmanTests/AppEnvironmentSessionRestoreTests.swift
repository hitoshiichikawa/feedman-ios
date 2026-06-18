import XCTest
@testable import Feedman

@MainActor
final class AppEnvironmentSessionRestoreTests: XCTestCase {
    private func makeEnvironment(
        repository: SessionRestoreAuthRepositoryMock,
        state: AppAuthenticationState = .restoring,
        deviceRegistrationService: APNsDeviceRegistrationService? = nil
    ) -> AppEnvironment {
        AppEnvironment(
            feedRepository: MockFeedRepository(),
            authRepository: repository,
            accountRepository: UnavailableAccountRepository(),
            deviceRegistrationService: deviceRegistrationService,
            authBaseURL: URL(string: "https://api.example.com")!,
            authenticationState: state
        )
    }

    func testRestoreWithStoredTokenSucceedsAndShowsAuthenticatedShell() async {
        let repository = SessionRestoreAuthRepositoryMock(
            refreshResult: .success(
                TokenCredentials(
                    accessToken: "restored-access",
                    refreshToken: "rotated-refresh",
                    tokenType: "Bearer",
                    expiresIn: 900
                )
            )
        )
        let environment = makeEnvironment(repository: repository)

        await environment.restoreSessionAtLaunch()

        XCTAssertEqual(environment.authenticationState, .authenticated(accessToken: "restored-access"))
        XCTAssertEqual(repository.refreshCallCount, 1)
        XCTAssertEqual(repository.clearLocalCallCount, 0)
    }

    func testRestoreWithoutStoredTokenShowsLoginWithoutClearing() async {
        let repository = SessionRestoreAuthRepositoryMock(
            refreshResult: .failure(AuthRepositoryError.missingRefreshToken)
        )
        let environment = makeEnvironment(repository: repository)

        await environment.restoreSessionAtLaunch()

        XCTAssertEqual(environment.authenticationState, .unauthenticated)
        XCTAssertEqual(repository.refreshCallCount, 1)
        XCTAssertEqual(repository.clearLocalCallCount, 0)
    }

    func testRestoreWithRejectedRefreshClearsCredentialsAndShowsLogin() async {
        let repository = SessionRestoreAuthRepositoryMock(
            refreshResult: .failure(SessionRestoreTestError.refreshRejected)
        )
        let environment = makeEnvironment(repository: repository)

        await environment.restoreSessionAtLaunch()

        XCTAssertEqual(environment.authenticationState, .unauthenticated)
        XCTAssertEqual(repository.refreshCallCount, 1)
        XCTAssertEqual(repository.clearLocalCallCount, 1)
    }

    func testRestoreIsNoOpWhenStateIsNotRestoring() async {
        let repository = SessionRestoreAuthRepositoryMock(
            refreshResult: .failure(SessionRestoreTestError.refreshRejected)
        )
        let environment = makeEnvironment(
            repository: repository,
            state: .authenticated(accessToken: "existing-access")
        )

        await environment.restoreSessionAtLaunch()

        XCTAssertEqual(environment.authenticationState, .authenticated(accessToken: "existing-access"))
        XCTAssertEqual(repository.refreshCallCount, 0)
    }

    func testCompleteLoginStillTransitionsToAuthenticated() async {
        let repository = SessionRestoreAuthRepositoryMock(
            refreshResult: .failure(AuthRepositoryError.missingRefreshToken)
        )
        let environment = makeEnvironment(repository: repository, state: .unauthenticated)

        environment.completeLogin(
            with: TokenCredentials(
                accessToken: "login-access",
                refreshToken: "login-refresh",
                tokenType: "Bearer",
                expiresIn: 900
            )
        )

        XCTAssertEqual(environment.authenticationState, .authenticated(accessToken: "login-access"))
    }

    func testAccountDeletionSessionClearClearsCredentialsAndShowsLogin() async {
        let repository = SessionRestoreAuthRepositoryMock(
            refreshResult: .failure(AuthRepositoryError.missingRefreshToken)
        )
        let deviceStateStore = InMemoryDeviceRegistrationStateStore(
            state: DeviceRegistrationState(deviceID: "device-1")
        )
        let deviceRegistrationService = APNsDeviceRegistrationService(
            repository: UnavailableDeviceRegistrationRepository(),
            stateStore: deviceStateStore,
            accessTokenProvider: {
                throw AppEnvironmentError.missingAccessToken
            }
        )
        let environment = makeEnvironment(
            repository: repository,
            state: .authenticated(accessToken: "existing-access"),
            deviceRegistrationService: deviceRegistrationService
        )

        await environment.clearLocalAuthenticationAfterAccountDeletion()

        XCTAssertEqual(environment.authenticationState, .unauthenticated)
        XCTAssertNil(environment.currentAccessToken)
        XCTAssertNil(deviceStateStore.load())
        XCTAssertEqual(repository.clearLocalCallCount, 1)
        XCTAssertEqual(repository.revokeCallCount, 0)
    }
}

private enum SessionRestoreTestError: Error {
    case refreshRejected
}

private final class SessionRestoreAuthRepositoryMock: AuthRepository {
    private let refreshResult: Result<TokenCredentials, Error>
    private(set) var refreshCallCount = 0
    private(set) var clearLocalCallCount = 0
    private(set) var revokeCallCount = 0

    init(refreshResult: Result<TokenCredentials, Error>) {
        self.refreshResult = refreshResult
    }

    @discardableResult
    func exchangeAuthCode(_ authCode: String, codeVerifier: String) async throws -> TokenCredentials {
        throw SessionRestoreTestError.refreshRejected
    }

    @discardableResult
    func refreshTokens() async throws -> TokenCredentials {
        refreshCallCount += 1
        return try refreshResult.get()
    }

    func revokeAndClearCredentials(accessToken: String?) async throws {
        revokeCallCount += 1
    }

    func clearLocalCredentials() throws {
        clearLocalCallCount += 1
    }
}
