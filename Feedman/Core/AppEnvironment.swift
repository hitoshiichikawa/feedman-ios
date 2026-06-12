import Combine
import Foundation

enum AppAuthenticationState: Equatable {
    case restoring
    case unauthenticated
    case authenticated(accessToken: String)

    var isAuthenticated: Bool {
        switch self {
        case .restoring, .unauthenticated:
            return false
        case .authenticated:
            return true
        }
    }
}

enum AppEnvironmentError: Error, Equatable {
    case missingAccessToken
}

final class AppAccessTokenStore: @unchecked Sendable {
    private let lock = NSLock()
    private var accessToken: String?

    init(accessToken: String? = nil) {
        self.accessToken = accessToken
    }

    func update(accessToken: String?) {
        lock.lock()
        defer { lock.unlock() }
        self.accessToken = accessToken
    }

    func currentAccessToken() throws -> String {
        lock.lock()
        defer { lock.unlock() }

        guard let accessToken, !accessToken.isEmpty else {
            throw AppEnvironmentError.missingAccessToken
        }
        return accessToken
    }
}

@MainActor
final class AppEnvironment: ObservableObject {
    let feedRepository: FeedRepository
    let authRepository: any AuthRepository
    let authBaseURL: URL

    private let accessTokenStore: AppAccessTokenStore

    @Published private(set) var authenticationState: AppAuthenticationState

    init(
        feedRepository: FeedRepository,
        authRepository: any AuthRepository,
        authBaseURL: URL,
        authenticationState: AppAuthenticationState = .unauthenticated,
        accessTokenStore: AppAccessTokenStore? = nil
    ) {
        self.feedRepository = feedRepository
        self.authRepository = authRepository
        self.authBaseURL = authBaseURL
        self.accessTokenStore = accessTokenStore ?? AppAccessTokenStore(
            accessToken: authenticationState.accessToken
        )
        self.authenticationState = authenticationState
    }

    func completeLogin(with credentials: TokenCredentials) {
        accessTokenStore.update(accessToken: credentials.accessToken)
        authenticationState = .authenticated(accessToken: credentials.accessToken)
    }

    /// 起動時に保存済み refresh token からセッションを復元する。
    /// `restoring` 状態のときだけ実行され、結果に応じて authenticated / unauthenticated へ遷移する。
    func restoreSessionAtLaunch() async {
        guard case .restoring = authenticationState else {
            return
        }

        do {
            let credentials = try await authRepository.refreshTokens()
            accessTokenStore.update(accessToken: credentials.accessToken)
            authenticationState = .authenticated(accessToken: credentials.accessToken)
        } catch AuthRepositoryError.missingRefreshToken {
            // 保存 token がなければ消すものもないため、そのまま未認証へ。
            accessTokenStore.update(accessToken: nil)
            authenticationState = .unauthenticated
        } catch {
            // 保存 token があるのに refresh が拒否された場合は失効済みとして
            // ローカル credential を破棄する (server への revoke は行わない)。
            try? authRepository.clearLocalCredentials()
            accessTokenStore.update(accessToken: nil)
            authenticationState = .unauthenticated
        }
    }

    static func production(
        apiBaseURL: URL = URL(string: "http://localhost:3000")!
    ) -> AppEnvironment {
        let accessTokenStore = AppAccessTokenStore()
        let authAPIClient = APIClient(baseURL: apiBaseURL)
        let authRepository = FeedmanAuthRepository(
            apiClient: authAPIClient,
            tokenStore: KeychainTokenStore()
        )
        let apiClient = APIClient(
            baseURL: apiBaseURL,
            accessTokenRefreshHook: {
                let credentials = try await authRepository.refreshTokens()
                accessTokenStore.update(accessToken: credentials.accessToken)
                return credentials.accessToken
            }
        )
        return AppEnvironment(
            feedRepository: APIClientFeedRepository(
                apiClient: apiClient,
                accessTokenProvider: {
                    try accessTokenStore.currentAccessToken()
                }
            ),
            authRepository: authRepository,
            authBaseURL: apiBaseURL,
            authenticationState: .restoring,
            accessTokenStore: accessTokenStore
        )
    }

    static let preview = AppEnvironment(
        feedRepository: MockFeedRepository(),
        authRepository: UnavailableAuthRepository(),
        authBaseURL: URL(string: "https://example.com")!,
        authenticationState: .authenticated(accessToken: "preview-access-token")
    )
}

private extension AppAuthenticationState {
    var accessToken: String? {
        switch self {
        case .restoring, .unauthenticated:
            return nil
        case let .authenticated(accessToken):
            return accessToken
        }
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

    func clearLocalCredentials() throws {}
}
