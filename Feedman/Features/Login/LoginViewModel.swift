import Combine
import Foundation

struct PKCELoginChallenge: Equatable {
    let verifier: String
    let challenge: String
}

protocol PKCELoginChallengeGenerating {
    func generateChallenge() throws -> PKCELoginChallenge
}

struct LivePKCELoginChallengeGenerator: PKCELoginChallengeGenerating {
    func generateChallenge() throws -> PKCELoginChallenge {
        let verifier = try PKCE.generateVerifier()
        return PKCELoginChallenge(
            verifier: verifier,
            challenge: try PKCE.challenge(for: verifier)
        )
    }
}

enum LoginAttemptKind: Equatable {
    case google
    case passkeyLogin
    case passkeyRegistration
}

enum LoginViewState: Equatable {
    case idle
    case loading(LoginAttemptKind)
    case authenticated
    case canceled(LoginAttemptKind)
    case failed(LoginAttemptKind, String)
    case resultUnknown(LoginAttemptKind, String)

    var isLoading: Bool {
        if case .loading = self {
            return true
        }
        return false
    }

    var isRetryEnabled: Bool {
        !isLoading
    }

    func isLoading(_ kind: LoginAttemptKind) -> Bool {
        self == .loading(kind)
    }
}

protocol LoginEventRecording {
    func record(_ event: LoginEvent)
}

enum LoginEvent: Equatable {
    case googleLoginStarted
}

struct NoOpLoginEventRecorder: LoginEventRecording {
    func record(_ event: LoginEvent) {}
}

struct UnavailablePasskeyPlatformAuthorizationCoordinator: PasskeyPlatformAuthorizationCoordinating {
    nonisolated init() {}

    func performRegistration(
        options: PasskeyPublicKeyCredentialCreationOptions
    ) async throws -> PasskeyCredentialEnvelope {
        throw PasskeyRepositoryError.unavailable
    }

    func performAssertion(
        options: PasskeyPublicKeyCredentialRequestOptions,
        allowedCredentialID: String?
    ) async throws -> PasskeyCredentialEnvelope {
        throw PasskeyRepositoryError.unavailable
    }

    func cancelActiveAuthorization() {}
}

@MainActor
final class LoginViewModel: ObservableObject {
    @Published private(set) var state: LoginViewState = .idle

    private let authBaseURL: URL
    private let authRepository: any AuthRepository
    private let sessionStarter: any WebAuthenticationSessionStarting
    private let passkeyRepository: any PasskeyRepository
    private let passkeyCoordinator: any PasskeyPlatformAuthorizationCoordinating
    private let pkceGenerator: any PKCELoginChallengeGenerating
    private let eventRecorder: any LoginEventRecording
    private let onAuthenticated: (TokenCredentials) -> Void
    private let callbackURLScheme = "feedman"

    private var inFlightCodeVerifier: String?
    private var activeAttempt: LoginAttempt?

    init(
        authBaseURL: URL,
        authRepository: any AuthRepository,
        sessionStarter: any WebAuthenticationSessionStarting = ASWebAuthenticationSessionCoordinator(),
        passkeyRepository: any PasskeyRepository = UnavailablePasskeyRepository(),
        passkeyCoordinator: any PasskeyPlatformAuthorizationCoordinating = UnavailablePasskeyPlatformAuthorizationCoordinator(),
        pkceGenerator: any PKCELoginChallengeGenerating = LivePKCELoginChallengeGenerator(),
        eventRecorder: any LoginEventRecording = NoOpLoginEventRecorder(),
        onAuthenticated: @escaping (TokenCredentials) -> Void
    ) {
        self.authBaseURL = authBaseURL
        self.authRepository = authRepository
        self.sessionStarter = sessionStarter
        self.passkeyRepository = passkeyRepository
        self.passkeyCoordinator = passkeyCoordinator
        self.pkceGenerator = pkceGenerator
        self.eventRecorder = eventRecorder
        self.onAuthenticated = onAuthenticated
    }

    func startGoogleLogin() async {
        guard !state.isLoading else {
            return
        }

        let attempt = beginAttempt(kind: .google)
        state = .loading(.google)
        eventRecorder.record(.googleLoginStarted)

        do {
            let challenge = try pkceGenerator.generateChallenge()
            inFlightCodeVerifier = challenge.verifier
            defer { inFlightCodeVerifier = nil }

            let loginURL = try makeGoogleLoginURL(codeChallenge: challenge.challenge)
            let callbackURL = try await sessionStarter.start(
                url: loginURL,
                callbackURLScheme: callbackURLScheme
            )
            let authCode = try AuthCallbackParser.authCode(from: callbackURL)
            let credentials = try await authRepository.exchangeAuthCode(
                authCode,
                codeVerifier: challenge.verifier
            )

            state = .authenticated
            onAuthenticated(credentials)
        } catch FeedmanWebAuthenticationError.canceled {
            state = .canceled(.google)
        } catch {
            state = .failed(.google, "Google ログインを完了できませんでした。時間をおいて再試行してください。")
        }

        finishAttempt(attempt)
    }

    func startPasskeyLogin() async {
        guard !state.isLoading else {
            return
        }

        let attempt = beginAttempt(kind: .passkeyLogin)
        state = .loading(.passkeyLogin)

        do {
            let challenge = try pkceGenerator.generateChallenge()
            inFlightCodeVerifier = challenge.verifier
            defer { inFlightCodeVerifier = nil }

            try checkActive(attempt)
            let beginResponse = try await passkeyRepository.beginAuthentication(codeChallenge: challenge.challenge)
            try checkActive(attempt)
            let credential = try await passkeyCoordinator.performAssertion(
                options: beginResponse.options.publicKey,
                allowedCredentialID: nil
            )
            try checkActive(attempt)
            let finishResponse = try await finishAuthentication(
                attempt: attempt,
                challengeID: beginResponse.challengeID,
                credential: credential
            )
            let credentials = try await exchangeAuthCodeCriticalSection(
                attempt: attempt,
                authCode: finishResponse.authCode,
                codeVerifier: challenge.verifier
            )

            state = .authenticated
            onAuthenticated(credentials)
        } catch LoginAttemptError.canceled {
            state = .canceled(.passkeyLogin)
        } catch is CancellationError {
            state = .canceled(.passkeyLogin)
        } catch PasskeyPlatformAuthorizationError.canceled {
            state = .canceled(.passkeyLogin)
        } catch LoginAttemptError.resultUnknown {
            state = .resultUnknown(.passkeyLogin, Self.passkeyResultUnknownMessage)
        } catch {
            state = .failed(.passkeyLogin, "パスキーでログインできませんでした。時間をおいて再試行してください。")
        }

        finishAttempt(attempt)
    }

    func startPasskeyRegistration(username: String) async {
        guard !state.isLoading else {
            return
        }

        let trimmedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedUsername.isEmpty else {
            state = .failed(.passkeyRegistration, "ユーザー名を入力してください。")
            return
        }

        let attempt = beginAttempt(kind: .passkeyRegistration)
        state = .loading(.passkeyRegistration)

        do {
            let challenge = try pkceGenerator.generateChallenge()
            inFlightCodeVerifier = challenge.verifier
            defer { inFlightCodeVerifier = nil }

            try checkActive(attempt)
            let registrationBegin = try await passkeyRepository.beginRegistration(
                username: trimmedUsername,
                codeChallenge: challenge.challenge
            )
            try checkActive(attempt)
            let registrationCredential = try await passkeyCoordinator.performRegistration(
                options: registrationBegin.options.publicKey
            )
            try checkActive(attempt)
            _ = try await finishRegistration(
                attempt: attempt,
                challengeID: registrationBegin.challengeID,
                credential: registrationCredential
            )

            guard !registrationCredential.rawID.isEmpty else {
                throw LoginAttemptError.resultUnknown
            }

            try checkActive(attempt)
            let authenticationBegin = try await passkeyRepository.beginAuthentication(codeChallenge: challenge.challenge)
            try checkActive(attempt)
            let assertionCredential = try await passkeyCoordinator.performAssertion(
                options: authenticationBegin.options.publicKey,
                allowedCredentialID: registrationCredential.rawID
            )
            try checkActive(attempt)
            let authenticationFinish = try await finishAuthentication(
                attempt: attempt,
                challengeID: authenticationBegin.challengeID,
                credential: assertionCredential
            )
            let credentials = try await exchangeAuthCodeCriticalSection(
                attempt: attempt,
                authCode: authenticationFinish.authCode,
                codeVerifier: challenge.verifier
            )

            state = .authenticated
            onAuthenticated(credentials)
        } catch LoginAttemptError.canceled {
            state = .canceled(.passkeyRegistration)
        } catch is CancellationError {
            state = .canceled(.passkeyRegistration)
        } catch PasskeyPlatformAuthorizationError.canceled {
            state = .canceled(.passkeyRegistration)
        } catch LoginAttemptError.resultUnknown {
            state = .resultUnknown(.passkeyRegistration, Self.passkeyResultUnknownMessage)
        } catch {
            state = .failed(.passkeyRegistration, Self.passkeyRegistrationFailureMessage(from: error))
        }

        finishAttempt(attempt)
    }

    func cancelActiveAttempt() {
        passkeyCoordinator.cancelActiveAuthorization()
        guard let activeAttempt, !activeAttempt.tokenExchangeDispatched else {
            return
        }
        activeAttempt.cancel()
    }

    private func makeGoogleLoginURL(codeChallenge: String) throws -> URL {
        guard var components = URLComponents(url: authBaseURL, resolvingAgainstBaseURL: false) else {
            throw FeedmanAPIError.invalidRequestURL(path: "/auth/google/login")
        }

        components.path = "/auth/google/login"
        let inheritedQueryItems = (components.queryItems ?? []).filter {
            $0.name != "flow"
                && $0.name != "code_challenge"
                && $0.name != "code_challenge_method"
        }
        components.queryItems = inheritedQueryItems + [
            URLQueryItem(name: "flow", value: "native"),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256")
        ]

        guard let url = components.url else {
            throw FeedmanAPIError.invalidRequestURL(path: "/auth/google/login")
        }
        return url
    }

    private func beginAttempt(kind: LoginAttemptKind) -> LoginAttempt {
        let attempt = LoginAttempt(kind: kind)
        activeAttempt = attempt
        return attempt
    }

    private func finishAttempt(_ attempt: LoginAttempt) {
        if activeAttempt === attempt {
            activeAttempt = nil
        }
    }

    private func checkActive(_ attempt: LoginAttempt) throws {
        guard activeAttempt === attempt, !attempt.isCanceled, !Task.isCancelled else {
            throw LoginAttemptError.canceled
        }
    }

    private func finishRegistration(
        attempt: LoginAttempt,
        challengeID: String,
        credential: PasskeyCredentialEnvelope
    ) async throws -> PasskeyRegistrationFinishResponse {
        try checkActive(attempt)
        attempt.registrationFinishDispatched = true
        do {
            return try await passkeyRepository.finishRegistration(
                challengeID: challengeID,
                credential: credential
            )
        } catch {
            if Self.isResultUnknownError(error) || attempt.isCanceled {
                throw LoginAttemptError.resultUnknown
            }
            throw error
        }
    }

    private func finishAuthentication(
        attempt: LoginAttempt,
        challengeID: String,
        credential: PasskeyCredentialEnvelope
    ) async throws -> PasskeyAuthenticationFinishResponse {
        try checkActive(attempt)
        attempt.authenticationFinishDispatched = true
        do {
            return try await passkeyRepository.finishAuthentication(
                challengeID: challengeID,
                credential: credential
            )
        } catch {
            if Self.isResultUnknownError(error) || attempt.isCanceled {
                throw LoginAttemptError.resultUnknown
            }
            throw error
        }
    }

    private func exchangeAuthCodeCriticalSection(
        attempt: LoginAttempt,
        authCode: String,
        codeVerifier: String
    ) async throws -> TokenCredentials {
        try checkActive(attempt)
        attempt.tokenExchangeDispatched = true
        return try await authRepository.exchangeAuthCode(authCode, codeVerifier: codeVerifier)
    }

    private static func isResultUnknownError(_ error: Error) -> Bool {
        if error is CancellationError {
            return true
        }
        if case FeedmanAPIError.successDecodingFailed = error {
            return true
        }
        if case let FeedmanAPIError.transportFailed(underlyingError) = error,
           (underlyingError as? URLError)?.code == .timedOut {
            return true
        }
        return false
    }

    private static func passkeyRegistrationFailureMessage(from error: Error) -> String {
        guard case let FeedmanAPIError.feedmanError(context) = error else {
            return "アカウントを作成できませんでした。時間をおいて再試行してください。"
        }

        switch context.code {
        case "INVALID_USERNAME":
            return "このユーザー名は使用できません。別のユーザー名を入力してください。"
        case "USERNAME_TAKEN":
            return "このユーザー名はすでに使われています。別のユーザー名を入力してください。"
        default:
            return "アカウントを作成できませんでした。時間をおいて再試行してください。"
        }
    }

    private static let passkeyResultUnknownMessage =
        "アカウント作成またはログイン結果を確認できませんでした。再試行またはパスキーでログインして照合してください。"
}

private final class LoginAttempt {
    let id = UUID()
    let kind: LoginAttemptKind
    var isCanceled = false
    var registrationFinishDispatched = false
    var authenticationFinishDispatched = false
    var tokenExchangeDispatched = false

    init(kind: LoginAttemptKind) {
        self.kind = kind
    }

    func cancel() {
        isCanceled = true
    }
}

private enum LoginAttemptError: Error {
    case canceled
    case resultUnknown
}
