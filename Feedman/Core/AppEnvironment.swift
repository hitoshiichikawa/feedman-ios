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
    typealias SearchRepositoryFactory = (String) -> any SearchRepository

    let feedRepository: FeedRepository
    let itemRepository: any ItemRepository
    let authRepository: any AuthRepository
    let accountRepository: any AccountRepository
    let authBaseURL: URL
    private let searchRepositoryFactory: SearchRepositoryFactory

    private let accessTokenStore: AppAccessTokenStore

    @Published private(set) var authenticationState: AppAuthenticationState

    init(
        feedRepository: FeedRepository,
        itemRepository: any ItemRepository = MockItemRepository(),
        authRepository: any AuthRepository,
        accountRepository: any AccountRepository,
        authBaseURL: URL,
        searchRepositoryFactory: @escaping SearchRepositoryFactory = { _ in MockSearchRepository() },
        authenticationState: AppAuthenticationState = .unauthenticated,
        accessTokenStore: AppAccessTokenStore? = nil
    ) {
        self.feedRepository = feedRepository
        self.itemRepository = itemRepository
        self.authRepository = authRepository
        self.accountRepository = accountRepository
        self.authBaseURL = authBaseURL
        self.searchRepositoryFactory = searchRepositoryFactory
        self.accessTokenStore = accessTokenStore ?? AppAccessTokenStore(
            accessToken: authenticationState.accessToken
        )
        self.authenticationState = authenticationState
    }

    var currentAccessToken: String? {
        switch authenticationState {
        case .restoring, .unauthenticated:
            return nil
        case let .authenticated(accessToken):
            return accessToken
        }
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

    func makeSearchRepository() -> any SearchRepository {
        guard case let .authenticated(accessToken) = authenticationState else {
            return MockSearchRepository(defaultResponse: .success([]))
        }

        return searchRepositoryFactory(accessToken)
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
            itemRepository: FeedmanItemRepository(apiClient: apiClient),
            authRepository: authRepository,
            accountRepository: FeedmanAccountRepository(apiClient: apiClient),
            authBaseURL: apiBaseURL,
            searchRepositoryFactory: { accessToken in
                APIClientSearchRepository(
                    apiClient: apiClient,
                    accessTokenProvider: {
                        accessToken
                    }
                )
            },
            authenticationState: .restoring,
            accessTokenStore: accessTokenStore
        )
    }

    static let preview = AppEnvironment(
        feedRepository: MockFeedRepository(),
        itemRepository: MockItemRepository(
            itemDetails: [
                "item-1": ItemDetail(
                    id: "item-1",
                    feedID: "publickey",
                    feedTitle: "Publickey",
                    feedFaviconURL: nil,
                    title: "Goの新しいイテレータが安定版に、range-over-funcの実用例まとめ",
                    summary: "range-over-func が GA となり、独自コレクションのイテレートが書きやすくなった。",
                    content: "<p>range-over-func が GA となり、独自コレクションのイテレートが書きやすくなった。</p><p>実装例と注意点を整理します。</p>",
                    link: "https://example.com/articles/1",
                    publishedAt: "2026-06-08T08:30:00Z",
                    isDateEstimated: false,
                    isRead: false,
                    isStarred: false,
                    hatebuCount: 142,
                    hatebuFetchedAt: "2026-06-08T08:35:00Z",
                    author: "Feedman"
                ),
                "item-2": ItemDetail(
                    id: "item-2",
                    feedID: "zenn",
                    feedTitle: "Zenn トレンド",
                    feedFaviconURL: nil,
                    title: "個人開発のSaaSを1年運用して分かったコスト最適化の勘所",
                    summary: "小さく始めて計測しながら削る、という当たり前を徹底した結果を共有する。",
                    content: "<p>小さく始めて計測しながら削る、という当たり前を徹底した結果を共有する。</p>",
                    link: "https://example.com/articles/2",
                    publishedAt: "2026-06-08T06:45:00Z",
                    isDateEstimated: false,
                    isRead: true,
                    isStarred: true,
                    hatebuCount: 64,
                    hatebuFetchedAt: "2026-06-08T06:50:00Z",
                    author: nil
                )
            ]
        ),
        authRepository: UnavailableAuthRepository(),
        accountRepository: UnavailableAccountRepository(),
        authBaseURL: URL(string: "https://example.com")!,
        searchRepositoryFactory: { _ in MockSearchRepository() },
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
