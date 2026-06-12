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

@MainActor
final class AppEnvironment: ObservableObject {
    let feedRepository: FeedRepository
    let authRepository: any AuthRepository
    let authBaseURL: URL

    @Published private(set) var authenticationState: AppAuthenticationState

    init(
        feedRepository: FeedRepository,
        authRepository: any AuthRepository,
        authBaseURL: URL,
        authenticationState: AppAuthenticationState = .unauthenticated
    ) {
        self.feedRepository = feedRepository
        self.authRepository = authRepository
        self.authBaseURL = authBaseURL
        self.authenticationState = authenticationState
    }

    func completeLogin(with credentials: TokenCredentials) {
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
            authenticationState = .authenticated(accessToken: credentials.accessToken)
        } catch AuthRepositoryError.missingRefreshToken {
            // 保存 token がなければ消すものもないため、そのまま未認証へ。
            authenticationState = .unauthenticated
        } catch {
            // 保存 token があるのに refresh が拒否された場合は失効済みとして
            // ローカル credential を破棄する (server への revoke は行わない)。
            try? authRepository.clearLocalCredentials()
            authenticationState = .unauthenticated
        }
    }

    static func production(
        apiBaseURL: URL = URL(string: "http://localhost:3000")!
    ) -> AppEnvironment {
        let apiClient = APIClient(baseURL: apiBaseURL)
        return AppEnvironment(
            feedRepository: MockFeedRepository(),
            authRepository: FeedmanAuthRepository(
                apiClient: apiClient,
                tokenStore: KeychainTokenStore()
            ),
            authBaseURL: apiBaseURL,
            authenticationState: .restoring
        )
    }

    static let preview = AppEnvironment(
        feedRepository: MockFeedRepository(),
        authRepository: UnavailableAuthRepository(),
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

    func clearLocalCredentials() throws {}
}
