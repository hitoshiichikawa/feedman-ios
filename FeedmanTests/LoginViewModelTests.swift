import Foundation
import XCTest
@testable import Feedman

@MainActor
final class LoginViewModelTests: XCTestCase {
    func testInitialStateIsIdle() {
        let viewModel = makeViewModel()

        XCTAssertEqual(viewModel.state, .idle)
        XCTAssertTrue(viewModel.state.isRetryEnabled)
    }

    func testStartGoogleLoginBuildsNativeFlowURLAndEntersLoading() async throws {
        let sessionStarter = PendingWebAuthenticationSessionStarter()
        let viewModel = makeViewModel(sessionStarter: sessionStarter)

        let task = Task {
            await viewModel.startGoogleLogin()
        }
        await waitForSessionRequest(sessionStarter)

        XCTAssertEqual(viewModel.state, .loading)
        XCTAssertEqual(viewModel.attemptStatus, .loading(.google))
        let request = try XCTUnwrap(sessionStarter.requests.first)
        XCTAssertEqual(request.callbackURLScheme, "feedman")
        XCTAssertEqual(request.url.path, "/auth/google/login")
        let components = try XCTUnwrap(URLComponents(url: request.url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.queryItems?.first(named: "diagnostic")?.value, "1")
        XCTAssertEqual(components.queryItems?.first(named: "flow")?.value, "native")
        XCTAssertEqual(components.queryItems?.first(named: "code_challenge")?.value, "challenge-1")
        XCTAssertEqual(components.queryItems?.first(named: "code_challenge_method")?.value, "S256")

        sessionStarter.cancel()
        await task.value
    }

    func testStartGoogleLoginNormalizesStaleAuthQueryParameters() async throws {
        let sessionStarter = PendingWebAuthenticationSessionStarter()
        let viewModel = makeViewModel(sessionStarter: sessionStarter)

        let task = Task {
            await viewModel.startGoogleLogin()
        }
        await waitForSessionRequest(sessionStarter)

        let request = try XCTUnwrap(sessionStarter.requests.first)
        let components = try XCTUnwrap(URLComponents(url: request.url, resolvingAgainstBaseURL: false))
        let queryItems = components.queryItems ?? []
        XCTAssertEqual(queryItems.filter { $0.name == "flow" }.map(\.value), ["native"])
        XCTAssertEqual(queryItems.filter { $0.name == "code_challenge" }.map(\.value), ["challenge-1"])
        XCTAssertEqual(queryItems.filter { $0.name == "code_challenge_method" }.map(\.value), ["S256"])
        XCTAssertEqual(queryItems.first(named: "diagnostic")?.value, "1")

        sessionStarter.cancel()
        await task.value
    }

    func testValidCallbackExchangesCodeWithMatchingVerifierAndAuthenticates() async throws {
        let sessionStarter = PendingWebAuthenticationSessionStarter()
        let repository = RecordingAuthRepository(
            result: .success(credentials(accessToken: "access-1"))
        )
        var completedCredentials: [TokenCredentials] = []
        let viewModel = makeViewModel(
            repository: repository,
            sessionStarter: sessionStarter
        ) { credentials in
            completedCredentials.append(credentials)
        }

        let task = Task {
            await viewModel.startGoogleLogin()
        }
        await waitForSessionRequest(sessionStarter)
        sessionStarter.succeed(with: URL(string: "feedman://auth/callback?auth_code=auth-1")!)
        await task.value

        XCTAssertEqual(repository.exchanges, [
            AuthCodeExchange(authCode: "auth-1", codeVerifier: "verifier-1")
        ])
        XCTAssertEqual(viewModel.state, .authenticated)
        XCTAssertEqual(completedCredentials.map(\.accessToken), ["access-1"])
    }

    func testPasskeyLoginExchangesAuthCodeAndAuthenticates() async throws {
        let passkeyRepository = RecordingPasskeyRepository()
        let passkeyCoordinator = RecordingPasskeyCoordinator(
            assertionEnvelope: .assertion(rawID: "assertion-1")
        )
        let authRepository = RecordingAuthRepository(
            result: .success(credentials(accessToken: "passkey-access"))
        )
        var completedCredentials: [TokenCredentials] = []
        let viewModel = makeViewModel(
            repository: authRepository,
            passkeyRepository: passkeyRepository,
            passkeyCoordinator: passkeyCoordinator
        ) { credentials in
            completedCredentials.append(credentials)
        }

        await viewModel.startPasskeyLogin()

        XCTAssertEqual(passkeyRepository.authenticationBeginChallenges, ["challenge-1"])
        XCTAssertEqual(passkeyCoordinator.assertionRequests.map(\.allowedCredentialID), [nil])
        XCTAssertEqual(passkeyRepository.authenticationFinishes, [
            PasskeyFinishCall(challengeID: "auth-challenge-1", rawID: "assertion-1")
        ])
        XCTAssertEqual(authRepository.exchanges, [
            AuthCodeExchange(authCode: "auth-code-1", codeVerifier: "verifier-1")
        ])
        XCTAssertEqual(viewModel.state, .authenticated)
        XCTAssertEqual(completedCredentials.map(\.accessToken), ["passkey-access"])
    }

    func testPasskeyLoginCancellationDoesNotExchangeAndAllowsRetry() async {
        let passkeyRepository = RecordingPasskeyRepository()
        let passkeyCoordinator = RecordingPasskeyCoordinator(
            assertionError: PasskeyPlatformAuthorizationError.canceled
        )
        let authRepository = RecordingAuthRepository()
        let viewModel = makeViewModel(
            repository: authRepository,
            passkeyRepository: passkeyRepository,
            passkeyCoordinator: passkeyCoordinator
        )

        await viewModel.startPasskeyLogin()

        XCTAssertTrue(passkeyRepository.authenticationFinishes.isEmpty)
        XCTAssertTrue(authRepository.exchanges.isEmpty)
        XCTAssertEqual(viewModel.state, .canceled)
        XCTAssertEqual(viewModel.attemptStatus, .canceled(.passkeyLogin))
        XCTAssertTrue(viewModel.state.isRetryEnabled)
    }

    func testPasskeyLoginAuthFinishFailureDoesNotExchange() async {
        let passkeyRepository = RecordingPasskeyRepository(
            finishAuthenticationResult: .failure(LoginTestError.serverRejected)
        )
        let authRepository = RecordingAuthRepository()
        let viewModel = makeViewModel(
            repository: authRepository,
            passkeyRepository: passkeyRepository,
            passkeyCoordinator: RecordingPasskeyCoordinator(assertionEnvelope: .assertion(rawID: "assertion-1"))
        )

        await viewModel.startPasskeyLogin()

        XCTAssertEqual(passkeyRepository.authenticationFinishes, [
            PasskeyFinishCall(challengeID: "auth-challenge-1", rawID: "assertion-1")
        ])
        XCTAssertTrue(authRepository.exchanges.isEmpty)
        XCTAssertFailed(viewModel, kind: .passkeyLogin)
    }

    func testPasskeyLoginTokenExchangeFailureShowsFailure() async {
        let authRepository = RecordingAuthRepository(result: .failure(LoginTestError.exchangeRejected))
        let viewModel = makeViewModel(
            repository: authRepository,
            passkeyRepository: RecordingPasskeyRepository(),
            passkeyCoordinator: RecordingPasskeyCoordinator(assertionEnvelope: .assertion(rawID: "assertion-1"))
        )

        await viewModel.startPasskeyLogin()

        XCTAssertEqual(authRepository.exchanges, [
            AuthCodeExchange(authCode: "auth-code-1", codeVerifier: "verifier-1")
        ])
        XCTAssertFailed(viewModel, kind: .passkeyLogin)
    }

    func testPasskeyRegistrationRejectsEmptyUsernameWithoutServerRequest() async {
        let passkeyRepository = RecordingPasskeyRepository()
        let passkeyCoordinator = RecordingPasskeyCoordinator()
        let viewModel = makeViewModel(
            passkeyRepository: passkeyRepository,
            passkeyCoordinator: passkeyCoordinator
        )

        await viewModel.startPasskeyRegistration(username: "")

        XCTAssertTrue(passkeyRepository.registrationBeginRequests.isEmpty)
        XCTAssertTrue(passkeyCoordinator.registrationRequests.isEmpty)
        XCTAssertFailed(viewModel, kind: .passkeyRegistration)
    }

    func testPasskeyRegistrationRejectsWhitespaceUsernameWithoutServerRequest() async {
        let passkeyRepository = RecordingPasskeyRepository()
        let passkeyCoordinator = RecordingPasskeyCoordinator()
        let viewModel = makeViewModel(
            passkeyRepository: passkeyRepository,
            passkeyCoordinator: passkeyCoordinator
        )

        await viewModel.startPasskeyRegistration(username: "   \n\t  ")

        XCTAssertTrue(passkeyRepository.registrationBeginRequests.isEmpty)
        XCTAssertTrue(passkeyCoordinator.registrationRequests.isEmpty)
        XCTAssertFailed(viewModel, kind: .passkeyRegistration)
    }

    func testPasskeyRegistrationUsernameTakenDoesNotCreatePlatformCredential() async {
        let passkeyRepository = RecordingPasskeyRepository(
            beginRegistrationResult: .failure(Self.feedmanError(code: "USERNAME_TAKEN", statusCode: 409))
        )
        let passkeyCoordinator = RecordingPasskeyCoordinator()
        let viewModel = makeViewModel(
            passkeyRepository: passkeyRepository,
            passkeyCoordinator: passkeyCoordinator
        )

        await viewModel.startPasskeyRegistration(username: "reader")

        XCTAssertEqual(passkeyRepository.registrationBeginRequests, [
            RegistrationBeginCall(username: "reader", codeChallenge: "challenge-1")
        ])
        XCTAssertTrue(passkeyCoordinator.registrationRequests.isEmpty)
        XCTAssertFailed(viewModel, kind: .passkeyRegistration)
    }

    func testPasskeyRegistrationInvalidUsernameDoesNotCreatePlatformCredential() async {
        let passkeyRepository = RecordingPasskeyRepository(
            beginRegistrationResult: .failure(Self.feedmanError(code: "INVALID_USERNAME", statusCode: 400))
        )
        let passkeyCoordinator = RecordingPasskeyCoordinator()
        let viewModel = makeViewModel(
            passkeyRepository: passkeyRepository,
            passkeyCoordinator: passkeyCoordinator
        )

        await viewModel.startPasskeyRegistration(username: "reader!")

        XCTAssertTrue(passkeyCoordinator.registrationRequests.isEmpty)
        XCTAssertFailed(viewModel, kind: .passkeyRegistration)
    }

    func testPasskeyRegistrationUsesCreatedCredentialForLocalHandoffAndAuthenticates() async {
        let passkeyRepository = RecordingPasskeyRepository()
        let passkeyCoordinator = RecordingPasskeyCoordinator(
            registrationEnvelope: .registration(rawID: "created-credential-1"),
            assertionEnvelope: .assertion(rawID: "created-assertion-1")
        )
        let authRepository = RecordingAuthRepository(result: .success(credentials(accessToken: "signup-access")))
        var completedCredentials: [TokenCredentials] = []
        let viewModel = makeViewModel(
            repository: authRepository,
            passkeyRepository: passkeyRepository,
            passkeyCoordinator: passkeyCoordinator
        ) { credentials in
            completedCredentials.append(credentials)
        }

        await viewModel.startPasskeyRegistration(username: " reader ")

        XCTAssertEqual(passkeyRepository.registrationBeginRequests, [
            RegistrationBeginCall(username: "reader", codeChallenge: "challenge-1")
        ])
        XCTAssertEqual(passkeyRepository.registrationFinishes, [
            PasskeyFinishCall(challengeID: "registration-challenge-1", rawID: "created-credential-1")
        ])
        XCTAssertEqual(passkeyRepository.authenticationBeginChallenges, ["challenge-1"])
        XCTAssertEqual(passkeyCoordinator.assertionRequests.map(\.allowedCredentialID), ["created-credential-1"])
        XCTAssertEqual(passkeyRepository.authenticationFinishes, [
            PasskeyFinishCall(challengeID: "auth-challenge-1", rawID: "created-assertion-1")
        ])
        XCTAssertEqual(authRepository.exchanges, [
            AuthCodeExchange(authCode: "auth-code-1", codeVerifier: "verifier-1")
        ])
        XCTAssertEqual(completedCredentials.map(\.accessToken), ["signup-access"])
        XCTAssertEqual(viewModel.state, .authenticated)
    }

    func testPasskeyRegistrationMissingCreatedCredentialIDIsResultUnknown() async {
        let passkeyRepository = RecordingPasskeyRepository()
        let authRepository = RecordingAuthRepository()
        let viewModel = makeViewModel(
            repository: authRepository,
            passkeyRepository: passkeyRepository,
            passkeyCoordinator: RecordingPasskeyCoordinator(registrationEnvelope: .registration(rawID: ""))
        )

        await viewModel.startPasskeyRegistration(username: "reader")

        XCTAssertEqual(passkeyRepository.registrationFinishes, [
            PasskeyFinishCall(challengeID: "registration-challenge-1", rawID: "")
        ])
        XCTAssertTrue(passkeyRepository.authenticationBeginChallenges.isEmpty)
        XCTAssertTrue(authRepository.exchanges.isEmpty)
        XCTAssertResultUnknown(viewModel, kind: .passkeyRegistration)
    }

    func testPasskeyRegistrationPlatformFailurePreservesUnauthenticatedState() async {
        let passkeyRepository = RecordingPasskeyRepository()
        let authRepository = RecordingAuthRepository()
        let viewModel = makeViewModel(
            repository: authRepository,
            passkeyRepository: passkeyRepository,
            passkeyCoordinator: RecordingPasskeyCoordinator(
                registrationError: PasskeyPlatformAuthorizationError.authorizationFailed
            )
        )

        await viewModel.startPasskeyRegistration(username: "reader")

        XCTAssertTrue(passkeyRepository.registrationFinishes.isEmpty)
        XCTAssertTrue(authRepository.exchanges.isEmpty)
        XCTAssertFailed(viewModel, kind: .passkeyRegistration)
    }

    func testPasskeyRegistrationFinishDispatchedCancellationBecomesResultUnknown() async {
        let passkeyRepository = RecordingPasskeyRepository(
            finishRegistrationResult: .failure(CancellationError())
        )
        let authRepository = RecordingAuthRepository()
        let viewModel = makeViewModel(
            repository: authRepository,
            passkeyRepository: passkeyRepository,
            passkeyCoordinator: RecordingPasskeyCoordinator(registrationEnvelope: .registration(rawID: "created-credential-1"))
        )

        await viewModel.startPasskeyRegistration(username: "reader")

        XCTAssertEqual(passkeyRepository.registrationFinishes, [
            PasskeyFinishCall(challengeID: "registration-challenge-1", rawID: "created-credential-1")
        ])
        XCTAssertTrue(authRepository.exchanges.isEmpty)
        XCTAssertResultUnknown(viewModel, kind: .passkeyRegistration)
    }

    func testPasskeyRegistrationCancelBeforeFinishSkipsFinishAndShowsCanceled() async {
        let passkeyRepository = RecordingPasskeyRepository()
        let passkeyCoordinator = CancelingAfterRegistrationPasskeyCoordinator(viewModelProvider: { nil })
        let viewModel = makeViewModel(
            passkeyRepository: passkeyRepository,
            passkeyCoordinator: passkeyCoordinator
        )
        passkeyCoordinator.viewModelProvider = { viewModel }

        await viewModel.startPasskeyRegistration(username: "reader")

        XCTAssertTrue(passkeyRepository.registrationFinishes.isEmpty)
        XCTAssertEqual(viewModel.state, .canceled)
        XCTAssertEqual(viewModel.attemptStatus, .canceled(.passkeyRegistration))
    }

    func testCancelBeforeTokenExchangeSkipsUnsentAuthenticationFinishAndTokenExchange() async {
        let passkeyRepository = RecordingPasskeyRepository()
        let passkeyCoordinator = CancelingBeforeSignupAssertionPasskeyCoordinator(viewModelProvider: { nil })
        let authRepository = RecordingAuthRepository()
        let viewModel = makeViewModel(
            repository: authRepository,
            passkeyRepository: passkeyRepository,
            passkeyCoordinator: passkeyCoordinator
        )
        passkeyCoordinator.viewModelProvider = { viewModel }

        await viewModel.startPasskeyRegistration(username: "reader")

        XCTAssertTrue(passkeyRepository.authenticationFinishes.isEmpty)
        XCTAssertTrue(authRepository.exchanges.isEmpty)
        XCTAssertEqual(viewModel.state, .canceled)
        XCTAssertEqual(viewModel.attemptStatus, .canceled(.passkeyRegistration))
    }

    func testTokenExchangeDispatchCriticalSectionAuthenticatesAfterCancellation() async {
        let authRepository = RecordingAuthRepository(
            result: .success(credentials(accessToken: "critical-access")),
            onExchange: nil
        )
        var completedCredentials: [TokenCredentials] = []
        let viewModel = makeViewModel(
            repository: authRepository,
            passkeyRepository: RecordingPasskeyRepository(),
            passkeyCoordinator: RecordingPasskeyCoordinator(assertionEnvelope: .assertion(rawID: "assertion-1"))
        ) { credentials in
            completedCredentials.append(credentials)
        }
        authRepository.onExchange = { [weak viewModel] in
            viewModel?.cancelActiveAttempt()
        }

        await viewModel.startPasskeyLogin()

        XCTAssertEqual(authRepository.exchanges, [
            AuthCodeExchange(authCode: "auth-code-1", codeVerifier: "verifier-1")
        ])
        XCTAssertEqual(completedCredentials.map(\.accessToken), ["critical-access"])
        XCTAssertEqual(viewModel.state, .authenticated)
    }

    func testDuplicateGuardBlocksPasskeyDuringGoogleLogin() async {
        let sessionStarter = PendingWebAuthenticationSessionStarter()
        let passkeyRepository = RecordingPasskeyRepository()
        let viewModel = makeViewModel(
            sessionStarter: sessionStarter,
            passkeyRepository: passkeyRepository
        )

        let task = Task {
            await viewModel.startGoogleLogin()
        }
        await waitForSessionRequest(sessionStarter)

        await viewModel.startPasskeyLogin()

        XCTAssertTrue(passkeyRepository.authenticationBeginChallenges.isEmpty)
        sessionStarter.cancel()
        await task.value
    }

    func testPasskeyFlowDoesNotRecordAdvertisingInteractionEvents() async {
        let eventRecorder = RecordingLoginEventRecorder()
        let viewModel = makeViewModel(
            passkeyRepository: RecordingPasskeyRepository(),
            passkeyCoordinator: RecordingPasskeyCoordinator(assertionEnvelope: .assertion(rawID: "assertion-1")),
            eventRecorder: eventRecorder
        )

        await viewModel.startPasskeyLogin()

        XCTAssertTrue(eventRecorder.events.isEmpty)
    }

    func testDuplicateTapDuringLoadingDoesNotStartSecondSession() async {
        let sessionStarter = PendingWebAuthenticationSessionStarter()
        let repository = RecordingAuthRepository()
        let viewModel = makeViewModel(
            repository: repository,
            sessionStarter: sessionStarter
        )

        let task = Task {
            await viewModel.startGoogleLogin()
        }
        await waitForSessionRequest(sessionStarter)

        await viewModel.startGoogleLogin()

        XCTAssertEqual(sessionStarter.requests.count, 1)
        XCTAssertTrue(repository.exchanges.isEmpty)

        sessionStarter.cancel()
        await task.value
        XCTAssertEqual(viewModel.state, .canceled)
        XCTAssertEqual(viewModel.attemptStatus, .canceled(.google))
    }

    func testCancellationDoesNotExchangeAndAllowsRetry() async {
        let sessionStarter = PendingWebAuthenticationSessionStarter()
        let repository = RecordingAuthRepository()
        let viewModel = makeViewModel(
            repository: repository,
            sessionStarter: sessionStarter
        )

        let task = Task {
            await viewModel.startGoogleLogin()
        }
        await waitForSessionRequest(sessionStarter)
        sessionStarter.cancel()
        await task.value

        XCTAssertTrue(repository.exchanges.isEmpty)
        XCTAssertEqual(viewModel.state, .canceled)
        XCTAssertEqual(viewModel.attemptStatus, .canceled(.google))
        XCTAssertTrue(viewModel.state.isRetryEnabled)
    }

    func testCallbackParseErrorDoesNotExchangeAndShowsFailure() async {
        let sessionStarter = PendingWebAuthenticationSessionStarter()
        let repository = RecordingAuthRepository()
        let viewModel = makeViewModel(
            repository: repository,
            sessionStarter: sessionStarter
        )

        let task = Task {
            await viewModel.startGoogleLogin()
        }
        await waitForSessionRequest(sessionStarter)
        sessionStarter.succeed(with: URL(string: "feedman://auth/callback")!)
        await task.value

        XCTAssertTrue(repository.exchanges.isEmpty)
        XCTAssertFailed(viewModel)
        XCTAssertTrue(viewModel.state.isRetryEnabled)
    }

    func testExchangeFailureShowsFailureAndAllowsRetry() async {
        let sessionStarter = PendingWebAuthenticationSessionStarter()
        let repository = RecordingAuthRepository(result: .failure(LoginTestError.exchangeRejected))
        let viewModel = makeViewModel(
            repository: repository,
            sessionStarter: sessionStarter
        )

        let task = Task {
            await viewModel.startGoogleLogin()
        }
        await waitForSessionRequest(sessionStarter)
        sessionStarter.succeed(with: URL(string: "feedman://auth/callback?auth_code=auth-1")!)
        await task.value

        XCTAssertEqual(repository.exchanges, [
            AuthCodeExchange(authCode: "auth-1", codeVerifier: "verifier-1")
        ])
        XCTAssertFailed(viewModel)
        XCTAssertTrue(viewModel.state.isRetryEnabled)
    }

    func testSessionUnableToStartShowsRetryableFailureAndDoesNotExchange() async {
        let sessionStarter = FailingWebAuthenticationSessionStarter(error: FeedmanWebAuthenticationError.unableToStart)
        let repository = RecordingAuthRepository()
        let viewModel = makeViewModel(
            repository: repository,
            sessionStarter: sessionStarter
        )

        await viewModel.startGoogleLogin()

        XCTAssertEqual(sessionStarter.requests.count, 1)
        XCTAssertTrue(repository.exchanges.isEmpty)
        XCTAssertFalse(viewModel.state.isLoading)
        XCTAssertFailed(viewModel)
        XCTAssertTrue(viewModel.state.isRetryEnabled)
    }

    private func makeViewModel(
        repository: RecordingAuthRepository = RecordingAuthRepository(),
        sessionStarter: any WebAuthenticationSessionStarting = PendingWebAuthenticationSessionStarter(),
        passkeyRepository: any PasskeyRepository = UnavailablePasskeyRepository(),
        passkeyCoordinator: any PasskeyPlatformAuthorizationCoordinating = UnavailablePasskeyPlatformAuthorizationCoordinator(),
        eventRecorder: any LoginEventRecording = NoOpLoginEventRecorder(),
        onAuthenticated: @escaping (TokenCredentials) -> Void = { _ in }
    ) -> LoginViewModel {
        LoginViewModel(
            authBaseURL: URL(string: "https://api.example.com/base?diagnostic=1&flow=web&code_challenge=old&code_challenge_method=plain")!,
            authRepository: repository,
            sessionStarter: sessionStarter,
            passkeyRepository: passkeyRepository,
            passkeyCoordinator: passkeyCoordinator,
            pkceGenerator: FixedPKCELoginChallengeGenerator(
                challenge: PKCELoginChallenge(
                    verifier: "verifier-1",
                    challenge: "challenge-1"
                )
            ),
            eventRecorder: eventRecorder,
            onAuthenticated: onAuthenticated
        )
    }

    private func waitForSessionRequest(
        _ sessionStarter: PendingWebAuthenticationSessionStarter,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        for _ in 0..<10 where sessionStarter.requests.isEmpty {
            await Task.yield()
        }
        XCTAssertFalse(sessionStarter.requests.isEmpty, file: file, line: line)
    }

    private func credentials(accessToken: String = "access") -> TokenCredentials {
        TokenCredentials(
            accessToken: accessToken,
            refreshToken: "refresh",
            tokenType: "Bearer",
            expiresIn: 900
        )
    }

    private func XCTAssertFailed(
        _ viewModel: LoginViewModel,
        kind: LoginAttemptKind? = nil,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .failed = viewModel.state else {
            XCTFail("Expected failed state, got \(viewModel.state)", file: file, line: line)
            return
        }
        guard let kind else {
            return
        }
        if case let .failed(actualKind, _) = viewModel.attemptStatus, actualKind == kind {
            return
        }
        XCTFail("Expected failed attempt status for \(kind), got \(viewModel.attemptStatus)", file: file, line: line)
    }

    private func XCTAssertResultUnknown(
        _ viewModel: LoginViewModel,
        kind: LoginAttemptKind,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .failed = viewModel.state else {
            XCTFail("Expected resultUnknown to be rendered as failed state, got \(viewModel.state)", file: file, line: line)
            return
        }
        if case let .resultUnknown(actualKind, _) = viewModel.attemptStatus, actualKind == kind {
            return
        }
        XCTFail("Expected resultUnknown attempt status, got \(viewModel.attemptStatus)", file: file, line: line)
    }

    private static func feedmanError(code: String, statusCode: Int) -> FeedmanAPIError {
        FeedmanAPIError.feedmanError(
            FeedmanErrorContext(
                statusCode: statusCode,
                body: FeedmanErrorBody(
                    code: code,
                    message: code,
                    category: "validation",
                    action: "fix_input",
                    details: nil
                ),
                retryAfter: nil
            )
        )
    }
}

private struct FixedPKCELoginChallengeGenerator: PKCELoginChallengeGenerating {
    let challenge: PKCELoginChallenge

    func generateChallenge() throws -> PKCELoginChallenge {
        challenge
    }
}

private struct WebAuthenticationRequest: Equatable {
    let url: URL
    let callbackURLScheme: String
}

@MainActor
private final class PendingWebAuthenticationSessionStarter: WebAuthenticationSessionStarting {
    private(set) var requests: [WebAuthenticationRequest] = []
    private var continuation: CheckedContinuation<URL, Error>?

    // makeViewModel の default 引数 (nonisolated 文脈) から生成できるようにする。
    nonisolated init() {}

    func start(url: URL, callbackURLScheme: String) async throws -> URL {
        requests.append(WebAuthenticationRequest(url: url, callbackURLScheme: callbackURLScheme))
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
        }
    }

    func succeed(with url: URL) {
        continuation?.resume(returning: url)
        continuation = nil
    }

    func cancel() {
        continuation?.resume(throwing: FeedmanWebAuthenticationError.canceled)
        continuation = nil
    }
}

@MainActor
private final class FailingWebAuthenticationSessionStarter: WebAuthenticationSessionStarting {
    private(set) var requests: [WebAuthenticationRequest] = []
    private let error: Error

    init(error: Error) {
        self.error = error
    }

    func start(url: URL, callbackURLScheme: String) async throws -> URL {
        requests.append(WebAuthenticationRequest(url: url, callbackURLScheme: callbackURLScheme))
        throw error
    }
}

private struct AuthCodeExchange: Equatable {
    let authCode: String
    let codeVerifier: String
}

private final class RecordingAuthRepository: AuthRepository {
    private(set) var exchanges: [AuthCodeExchange] = []
    private let result: Result<TokenCredentials, Error>
    var onExchange: (() -> Void)?

    init(result: Result<TokenCredentials, Error> = .success(
        TokenCredentials(
            accessToken: "access",
            refreshToken: "refresh",
            tokenType: "Bearer",
            expiresIn: 900
        )
    ), onExchange: (() -> Void)? = nil) {
        self.result = result
        self.onExchange = onExchange
    }

    @discardableResult
    func exchangeAuthCode(_ authCode: String, codeVerifier: String) async throws -> TokenCredentials {
        exchanges.append(AuthCodeExchange(authCode: authCode, codeVerifier: codeVerifier))
        onExchange?()
        return try result.get()
    }

    @discardableResult
    func refreshTokens() async throws -> TokenCredentials {
        try result.get()
    }

    func revokeAndClearCredentials(accessToken: String?) async throws {}

    func clearLocalCredentials() throws {}
}

private enum LoginTestError: Error {
    case exchangeRejected
    case serverRejected
}

private struct RegistrationBeginCall: Equatable {
    let username: String
    let codeChallenge: String
}

private struct PasskeyFinishCall: Equatable {
    let challengeID: String
    let rawID: String
}

private final class RecordingPasskeyRepository: PasskeyRepository {
    private(set) var registrationBeginRequests: [RegistrationBeginCall] = []
    private(set) var registrationFinishes: [PasskeyFinishCall] = []
    private(set) var authenticationBeginChallenges: [String] = []
    private(set) var authenticationFinishes: [PasskeyFinishCall] = []

    private let beginRegistrationResult: Result<PasskeyRegistrationBeginResponse, Error>
    private let finishRegistrationResult: Result<PasskeyRegistrationFinishResponse, Error>
    private let beginAuthenticationResult: Result<PasskeyAuthenticationBeginResponse, Error>
    private let finishAuthenticationResult: Result<PasskeyAuthenticationFinishResponse, Error>

    init(
        beginRegistrationResult: Result<PasskeyRegistrationBeginResponse, Error> = .success(.registrationBegin()),
        finishRegistrationResult: Result<PasskeyRegistrationFinishResponse, Error> = .success(PasskeyRegistrationFinishResponse(userID: "user-1")),
        beginAuthenticationResult: Result<PasskeyAuthenticationBeginResponse, Error> = .success(.authenticationBegin()),
        finishAuthenticationResult: Result<PasskeyAuthenticationFinishResponse, Error> = .success(PasskeyAuthenticationFinishResponse(authCode: "auth-code-1"))
    ) {
        self.beginRegistrationResult = beginRegistrationResult
        self.finishRegistrationResult = finishRegistrationResult
        self.beginAuthenticationResult = beginAuthenticationResult
        self.finishAuthenticationResult = finishAuthenticationResult
    }

    func beginRegistration(
        username: String,
        codeChallenge: String
    ) async throws -> PasskeyRegistrationBeginResponse {
        registrationBeginRequests.append(RegistrationBeginCall(username: username, codeChallenge: codeChallenge))
        return try beginRegistrationResult.get()
    }

    func finishRegistration(
        challengeID: String,
        credential: PasskeyCredentialEnvelope
    ) async throws -> PasskeyRegistrationFinishResponse {
        registrationFinishes.append(PasskeyFinishCall(challengeID: challengeID, rawID: credential.rawID))
        return try finishRegistrationResult.get()
    }

    func beginAuthentication(codeChallenge: String) async throws -> PasskeyAuthenticationBeginResponse {
        authenticationBeginChallenges.append(codeChallenge)
        return try beginAuthenticationResult.get()
    }

    func finishAuthentication(
        challengeID: String,
        credential: PasskeyCredentialEnvelope
    ) async throws -> PasskeyAuthenticationFinishResponse {
        authenticationFinishes.append(PasskeyFinishCall(challengeID: challengeID, rawID: credential.rawID))
        return try finishAuthenticationResult.get()
    }

    func beginAddRegistration(accessToken: String) async throws -> PasskeyAddRegistrationBeginResponse {
        throw PasskeyRepositoryError.unavailable
    }

    func finishAddRegistration(
        challengeID: String,
        credential: PasskeyCredentialEnvelope,
        accessToken: String
    ) async throws {
        throw PasskeyRepositoryError.unavailable
    }
}

private struct AssertionRequest: Equatable {
    let allowedCredentialID: String?
}

@MainActor
private class RecordingPasskeyCoordinator: PasskeyPlatformAuthorizationCoordinating {
    private(set) var registrationRequests: [PasskeyPublicKeyCredentialCreationOptions] = []
    private(set) var assertionRequests: [AssertionRequest] = []

    private let registrationEnvelope: PasskeyCredentialEnvelope
    private let assertionEnvelope: PasskeyCredentialEnvelope
    private let registrationError: Error?
    private let assertionError: Error?

    init(
        registrationEnvelope: PasskeyCredentialEnvelope = .registration(rawID: "created-credential-1"),
        assertionEnvelope: PasskeyCredentialEnvelope = .assertion(rawID: "assertion-1"),
        registrationError: Error? = nil,
        assertionError: Error? = nil
    ) {
        self.registrationEnvelope = registrationEnvelope
        self.assertionEnvelope = assertionEnvelope
        self.registrationError = registrationError
        self.assertionError = assertionError
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
        assertionRequests.append(AssertionRequest(allowedCredentialID: allowedCredentialID))
        if let assertionError {
            throw assertionError
        }
        return assertionEnvelope
    }

    func cancelActiveAuthorization() {}
}

@MainActor
private final class CancelingAfterRegistrationPasskeyCoordinator: RecordingPasskeyCoordinator {
    var viewModelProvider: () -> LoginViewModel?

    init(viewModelProvider: @escaping () -> LoginViewModel?) {
        self.viewModelProvider = viewModelProvider
        super.init(registrationEnvelope: .registration(rawID: "created-credential-1"))
    }

    override func performRegistration(
        options: PasskeyPublicKeyCredentialCreationOptions
    ) async throws -> PasskeyCredentialEnvelope {
        let envelope = try await super.performRegistration(options: options)
        viewModelProvider()?.cancelActiveAttempt()
        return envelope
    }
}

@MainActor
private final class CancelingBeforeSignupAssertionPasskeyCoordinator: RecordingPasskeyCoordinator {
    var viewModelProvider: () -> LoginViewModel?

    init(viewModelProvider: @escaping () -> LoginViewModel?) {
        self.viewModelProvider = viewModelProvider
        super.init(
            registrationEnvelope: .registration(rawID: "created-credential-1"),
            assertionEnvelope: .assertion(rawID: "created-assertion-1")
        )
    }

    override func performAssertion(
        options: PasskeyPublicKeyCredentialRequestOptions,
        allowedCredentialID: String?
    ) async throws -> PasskeyCredentialEnvelope {
        viewModelProvider()?.cancelActiveAttempt()
        return try await super.performAssertion(options: options, allowedCredentialID: allowedCredentialID)
    }
}

private final class RecordingLoginEventRecorder: LoginEventRecording {
    private(set) var events: [LoginEvent] = []

    func record(_ event: LoginEvent) {
        events.append(event)
    }
}

private extension PasskeyRegistrationBeginResponse {
    static func registrationBegin() -> PasskeyRegistrationBeginResponse {
        PasskeyRegistrationBeginResponse(
            challengeID: "registration-challenge-1",
            options: PasskeyPublicKeyCredentialCreationOptionsEnvelope(
                publicKey: .creationOptions()
            )
        )
    }
}

private extension PasskeyAuthenticationBeginResponse {
    static func authenticationBegin() -> PasskeyAuthenticationBeginResponse {
        PasskeyAuthenticationBeginResponse(
            challengeID: "auth-challenge-1",
            options: PasskeyPublicKeyCredentialRequestOptionsEnvelope(
                publicKey: .requestOptions()
            )
        )
    }
}

private extension PasskeyPublicKeyCredentialCreationOptions {
    static func creationOptions() -> PasskeyPublicKeyCredentialCreationOptions {
        PasskeyPublicKeyCredentialCreationOptions(
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
    }
}

private extension PasskeyPublicKeyCredentialRequestOptions {
    static func requestOptions() -> PasskeyPublicKeyCredentialRequestOptions {
        PasskeyPublicKeyCredentialRequestOptions(
            challenge: "Y2hhbGxlbmdl",
            rpID: "example.com",
            timeout: nil,
            allowCredentials: nil,
            userVerification: nil
        )
    }
}

private extension PasskeyCredentialEnvelope {
    static func registration(rawID: String) -> PasskeyCredentialEnvelope {
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

    static func assertion(rawID: String) -> PasskeyCredentialEnvelope {
        PasskeyCredentialEnvelope(
            id: rawID,
            rawID: rawID,
            type: "public-key",
            response: .assertion(PasskeyAssertionCredentialResponse(
                clientDataJSON: "Y2xpZW50",
                authenticatorData: "YXV0aG4",
                signature: "c2ln",
                userHandle: "dXNlcg"
            ))
        )
    }
}

private extension Array where Element == URLQueryItem {
    func first(named name: String) -> URLQueryItem? {
        first { $0.name == name }
    }
}
