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
    let authBaseURL: URL
    private let accessTokenProvider: CurrentAccessTokenProvider?

    @Published private(set) var authenticationState: AppAuthenticationState

    init(
        feedRepository: FeedRepository,
        authRepository: any AuthRepository,
        authBaseURL: URL,
        authenticationState: AppAuthenticationState = .unauthenticated,
        accessTokenProvider: CurrentAccessTokenProvider? = nil
    ) {
        self.feedRepository = feedRepository
        self.authRepository = authRepository
        self.authBaseURL = authBaseURL
        self.authenticationState = authenticationState
        self.accessTokenProvider = accessTokenProvider
    }

    func completeLogin(with credentials: TokenCredentials) {
        accessTokenProvider?.store(credentials.accessToken)
        authenticationState = .authenticated(accessToken: credentials.accessToken)
    }

    static func production(
        apiBaseURL: URL = URL(string: "http://localhost:3000")!
    ) -> AppEnvironment {
        let tokenStore = KeychainTokenStore()
        let accessTokenProvider = CurrentAccessTokenProvider()
        let authAPIClient = APIClient(baseURL: apiBaseURL)
        let authRepository = FeedmanAuthRepository(
            apiClient: authAPIClient,
            tokenStore: tokenStore
        )
        let feedAPIClient = APIClient(
            baseURL: apiBaseURL,
            accessTokenRefreshHook: {
                let credentials = try await authRepository.refreshTokens()
                accessTokenProvider.store(credentials.accessToken)
                return credentials.accessToken
            }
        )
        return AppEnvironment(
            feedRepository: APIClientFeedRepository(
                apiClient: feedAPIClient,
                accessTokenProvider: {
                    try accessTokenProvider.load()
                }
            ),
            authRepository: authRepository,
            authBaseURL: apiBaseURL,
            accessTokenProvider: accessTokenProvider
        )
    }

    static let preview = AppEnvironment(
        feedRepository: MockFeedRepository(),
        authRepository: UnavailableAuthRepository(),
        authBaseURL: URL(string: "https://example.com")!,
        authenticationState: .authenticated(accessToken: "preview-access-token")
    )
}

final class CurrentAccessTokenProvider: @unchecked Sendable {
    private let lock = NSLock()
    private var accessToken: String?

    func store(_ accessToken: String) {
        lock.lock()
        self.accessToken = accessToken
        lock.unlock()
    }

    func load() throws -> String {
        lock.lock()
        defer {
            lock.unlock()
        }

        guard let accessToken else {
            throw FeedmanAPIError.authRequired(
                AuthRequiredContext(
                    reason: .credentialsUnavailable,
                    statusCode: nil,
                    underlyingError: AuthRepositoryError.missingRefreshToken
                )
            )
        }

        return accessToken
    }
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
