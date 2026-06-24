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
        XCTAssertFailed(viewModel.state)
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
        XCTAssertFailed(viewModel.state)
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
        XCTAssertFailed(viewModel.state)
        XCTAssertTrue(viewModel.state.isRetryEnabled)
    }

    private func makeViewModel(
        repository: RecordingAuthRepository = RecordingAuthRepository(),
        sessionStarter: any WebAuthenticationSessionStarting = PendingWebAuthenticationSessionStarter(),
        onAuthenticated: @escaping (TokenCredentials) -> Void = { _ in }
    ) -> LoginViewModel {
        LoginViewModel(
            authBaseURL: URL(string: "https://api.example.com/base?diagnostic=1&flow=web&code_challenge=old&code_challenge_method=plain")!,
            authRepository: repository,
            sessionStarter: sessionStarter,
            pkceGenerator: FixedPKCELoginChallengeGenerator(
                challenge: PKCELoginChallenge(
                    verifier: "verifier-1",
                    challenge: "challenge-1"
                )
            ),
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
        _ state: LoginViewState,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        if case .failed = state {
            return
        }
        XCTFail("Expected failed state, got \(state)", file: file, line: line)
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

    init(result: Result<TokenCredentials, Error> = .success(
        TokenCredentials(
            accessToken: "access",
            refreshToken: "refresh",
            tokenType: "Bearer",
            expiresIn: 900
        )
    )) {
        self.result = result
    }

    @discardableResult
    func exchangeAuthCode(_ authCode: String, codeVerifier: String) async throws -> TokenCredentials {
        exchanges.append(AuthCodeExchange(authCode: authCode, codeVerifier: codeVerifier))
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
}

private extension Array where Element == URLQueryItem {
    func first(named name: String) -> URLQueryItem? {
        first { $0.name == name }
    }
}
