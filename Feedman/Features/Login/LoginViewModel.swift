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

enum LoginViewState: Equatable {
    case idle
    case loading
    case authenticated
    case canceled
    case failed(String)

    var isLoading: Bool {
        self == .loading
    }

    var isRetryEnabled: Bool {
        self != .loading
    }
}

@MainActor
final class LoginViewModel: ObservableObject {
    @Published private(set) var state: LoginViewState = .idle

    private let authBaseURL: URL
    private let authRepository: any AuthRepository
    private let sessionStarter: any WebAuthenticationSessionStarting
    private let pkceGenerator: any PKCELoginChallengeGenerating
    private let onAuthenticated: (TokenCredentials) -> Void
    private let callbackURLScheme = "feedman"

    private var inFlightCodeVerifier: String?

    init(
        authBaseURL: URL,
        authRepository: any AuthRepository,
        sessionStarter: any WebAuthenticationSessionStarting = ASWebAuthenticationSessionCoordinator(),
        pkceGenerator: any PKCELoginChallengeGenerating = LivePKCELoginChallengeGenerator(),
        onAuthenticated: @escaping (TokenCredentials) -> Void
    ) {
        self.authBaseURL = authBaseURL
        self.authRepository = authRepository
        self.sessionStarter = sessionStarter
        self.pkceGenerator = pkceGenerator
        self.onAuthenticated = onAuthenticated
    }

    func startGoogleLogin() async {
        guard !state.isLoading else {
            return
        }

        state = .loading

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
            state = .canceled
        } catch {
            state = .failed("Google ログインを完了できませんでした。時間をおいて再試行してください。")
        }
    }

    private func makeGoogleLoginURL(codeChallenge: String) throws -> URL {
        guard var components = URLComponents(url: authBaseURL, resolvingAgainstBaseURL: false) else {
            throw FeedmanAPIError.invalidRequestURL(path: "/auth/google/login")
        }

        components.percentEncodedPath = joinedPath(
            components.percentEncodedPath,
            "/auth/google/login"
        )
        components.queryItems = (components.queryItems ?? []) + [
            URLQueryItem(name: "flow", value: "native"),
            URLQueryItem(name: "code_challenge", value: codeChallenge)
        ]

        guard let url = components.url else {
            throw FeedmanAPIError.invalidRequestURL(path: "/auth/google/login")
        }
        return url
    }

    private func joinedPath(_ basePath: String, _ endpointPath: String) -> String {
        let trimmedBase = basePath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let trimmedEndpoint = endpointPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        switch (trimmedBase.isEmpty, trimmedEndpoint.isEmpty) {
        case (true, true):
            return "/"
        case (true, false):
            return "/" + trimmedEndpoint
        case (false, true):
            return "/" + trimmedBase
        case (false, false):
            return "/" + trimmedBase + "/" + trimmedEndpoint
        }
    }
}
