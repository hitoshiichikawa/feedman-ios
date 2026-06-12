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
    let feedRepository: FeedRepository
    let authRepository: any AuthRepository
    let accountRepository: any AccountRepository
    let authBaseURL: URL

    @Published private(set) var authenticationState: AppAuthenticationState

    init(
        feedRepository: FeedRepository,
        authRepository: any AuthRepository,
        accountRepository: any AccountRepository,
        authBaseURL: URL,
        authenticationState: AppAuthenticationState = .unauthenticated
    ) {
        self.feedRepository = feedRepository
        self.authRepository = authRepository
        self.accountRepository = accountRepository
        self.authBaseURL = authBaseURL
        self.authenticationState = authenticationState
    }

    var currentAccessToken: String? {
        switch authenticationState {
        case .unauthenticated:
            return nil
        case let .authenticated(accessToken):
            return accessToken
        }
    }

    func completeLogin(with credentials: TokenCredentials) {
        authenticationState = .authenticated(accessToken: credentials.accessToken)
    }

    static func production(
        apiBaseURL: URL = URL(string: "http://localhost:3000")!
    ) -> AppEnvironment {
        let tokenStore = KeychainTokenStore()
        let authRepository = FeedmanAuthRepository(
            apiClient: APIClient(baseURL: apiBaseURL),
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
            accountRepository: FeedmanAccountRepository(apiClient: authenticatedAPIClient),
            authBaseURL: apiBaseURL
        )
    }

    static let preview = AppEnvironment(
        feedRepository: MockFeedRepository(),
        authRepository: UnavailableAuthRepository(),
        accountRepository: UnavailableAccountRepository(),
        authBaseURL: URL(string: "https://example.com")!,
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
