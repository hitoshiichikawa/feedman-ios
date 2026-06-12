import Combine
import Foundation

enum AppAuthenticationState: Equatable {
    case unauthenticated
    case authenticated(accessToken: String)

    var isAuthenticated: Bool {
        switch self {
        case .unauthenticated:
            return false
        case .authenticated:
            return true
        }
    }
}

@MainActor
final class AppEnvironment: ObservableObject {
    typealias SearchRepositoryFactory = (String) -> any SearchRepository

    let feedRepository: FeedRepository
    let authRepository: any AuthRepository
    let authBaseURL: URL
    private let searchRepositoryFactory: SearchRepositoryFactory

    @Published private(set) var authenticationState: AppAuthenticationState

    init(
        feedRepository: FeedRepository,
        authRepository: any AuthRepository,
        authBaseURL: URL,
        searchRepositoryFactory: @escaping SearchRepositoryFactory = { _ in MockSearchRepository() },
        authenticationState: AppAuthenticationState = .unauthenticated
    ) {
        self.feedRepository = feedRepository
        self.authRepository = authRepository
        self.authBaseURL = authBaseURL
        self.searchRepositoryFactory = searchRepositoryFactory
        self.authenticationState = authenticationState
    }

    func completeLogin(with credentials: TokenCredentials) {
        authenticationState = .authenticated(accessToken: credentials.accessToken)
    }

    func makeSearchRepository() -> any SearchRepository {
        guard case let .authenticated(accessToken) = authenticationState else {
            return MockSearchRepository(defaultResponse: .success([]))
        }

        return searchRepositoryFactory(accessToken)
    }

    static func production(
        apiBaseURL: URL = URL(string: "http://localhost:3000")!
    ) -> AppEnvironment {
        let tokenStore = KeychainTokenStore()
        let authAPIClient = APIClient(baseURL: apiBaseURL)
        let authRepository = FeedmanAuthRepository(
            apiClient: authAPIClient,
            tokenStore: tokenStore
        )
        let authenticatedAPIClient = APIClient(
            baseURL: apiBaseURL,
            accessTokenRefreshHook: {
                try await authRepository.refreshTokens().accessToken
            }
        )

        return AppEnvironment(
            feedRepository: MockFeedRepository(),
            authRepository: authRepository,
            authBaseURL: apiBaseURL,
            searchRepositoryFactory: { accessToken in
                APIClientSearchRepository(
                    apiClient: authenticatedAPIClient,
                    accessTokenProvider: {
                        accessToken
                    }
                )
            }
        )
    }

    static let preview = AppEnvironment(
        feedRepository: MockFeedRepository(),
        authRepository: UnavailableAuthRepository(),
        authBaseURL: URL(string: "https://example.com")!,
        searchRepositoryFactory: { _ in MockSearchRepository() },
        authenticationState: .authenticated(accessToken: "preview-access-token")
    )
}

struct UnavailableAuthRepository: AuthRepository {
    @discardableResult
    func exchangeAuthCode(_ authCode: String, codeVerifier: String) async throws -> TokenCredentials {
        throw AuthRepositoryError.missingRefreshToken
    }

    @discardableResult
    func refreshTokens() async throws -> TokenCredentials {
        throw AuthRepositoryError.missingRefreshToken
    }

    func revokeAndClearCredentials(accessToken: String?) async throws {}
}
