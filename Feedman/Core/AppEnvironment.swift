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

struct NotificationFeatureFlags: Equatable {
    let keywordNotificationsEnabled: Bool

    static let v1Default = NotificationFeatureFlags(keywordNotificationsEnabled: false)
    static let nextPhaseEnabled = NotificationFeatureFlags(keywordNotificationsEnabled: true)
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
    let keywordRepository: any KeywordRepository
    let deviceRegistrationRepository: any DeviceRegistrationRepository
    let authRepository: any AuthRepository
    let accountRepository: any AccountRepository
    let notificationPermissionCoordinator: NotificationPermissionCoordinator
    let deviceRegistrationService: APNsDeviceRegistrationService
    let notificationFeatures: NotificationFeatureFlags
    let authBaseURL: URL
    private let searchRepositoryFactory: SearchRepositoryFactory

    private let accessTokenStore: AppAccessTokenStore

    @Published private(set) var authenticationState: AppAuthenticationState
    @Published private(set) var pendingDeviceRegistrationRetryError: Error?
    @Published private(set) var apnsRegistrationError: APNsDeviceRegistrationError?
    @Published private(set) var pendingNotificationArticleTarget: NotificationArticleTarget?
    @Published private(set) var notificationNavigationError: NotificationArticleTargetRejectionReason?

    init(
        feedRepository: FeedRepository,
        itemRepository: any ItemRepository = MockItemRepository(),
        keywordRepository: any KeywordRepository = MockKeywordRepository(),
        deviceRegistrationRepository: any DeviceRegistrationRepository = UnavailableDeviceRegistrationRepository(),
        authRepository: any AuthRepository,
        accountRepository: any AccountRepository,
        notificationPermissionCoordinator: NotificationPermissionCoordinator? = nil,
        deviceRegistrationService: APNsDeviceRegistrationService? = nil,
        notificationFeatures: NotificationFeatureFlags = .nextPhaseEnabled,
        authBaseURL: URL,
        searchRepositoryFactory: @escaping SearchRepositoryFactory = { _ in MockSearchRepository() },
        authenticationState: AppAuthenticationState = .unauthenticated,
        accessTokenStore: AppAccessTokenStore? = nil
    ) {
        self.feedRepository = feedRepository
        self.itemRepository = itemRepository
        self.keywordRepository = keywordRepository
        self.deviceRegistrationRepository = deviceRegistrationRepository
        self.authRepository = authRepository
        self.accountRepository = accountRepository
        self.notificationPermissionCoordinator = notificationPermissionCoordinator ?? NotificationPermissionCoordinator(
            authorizationProvider: UnavailableNotificationAuthorizationProvider(),
            remoteNotificationRegistrar: UnavailableRemoteNotificationRegistrar()
        )
        self.deviceRegistrationService = deviceRegistrationService ?? APNsDeviceRegistrationService(
            repository: UnavailableDeviceRegistrationRepository(),
            stateStore: InMemoryDeviceRegistrationStateStore(),
            accessTokenProvider: {
                throw AppEnvironmentError.missingAccessToken
            }
        )
        self.notificationFeatures = notificationFeatures
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
        Task {
            await retryPendingDeviceRegistrationIfPossible()
        }
    }

    func clearLocalAuthenticationAfterAccountDeletion() async {
        try? authRepository.clearLocalCredentials()
        accessTokenStore.update(accessToken: nil)
        await deviceRegistrationService.clearLocalState()
        pendingDeviceRegistrationRetryError = nil
        apnsRegistrationError = nil
        pendingNotificationArticleTarget = nil
        notificationNavigationError = nil
        authenticationState = .unauthenticated
    }

    @discardableResult
    func logout() async -> AppLogoutResult {
        let accessToken = currentAccessToken
        let unregisterResult = await deviceRegistrationService.unregisterKnownDeviceForLogout(
            accessToken: accessToken
        )

        var authRevokeError: Error?
        do {
            try await authRepository.revokeAndClearCredentials(accessToken: accessToken)
        } catch {
            authRevokeError = error
            try? authRepository.clearLocalCredentials()
        }

        accessTokenStore.update(accessToken: nil)
        pendingDeviceRegistrationRetryError = nil
        apnsRegistrationError = nil
        pendingNotificationArticleTarget = nil
        notificationNavigationError = nil
        authenticationState = .unauthenticated

        return AppLogoutResult(
            deviceUnregisterResult: unregisterResult,
            authRevokeError: authRevokeError
        )
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
            await retryPendingDeviceRegistrationIfPossible()
        } catch AuthRepositoryError.missingRefreshToken {
            // 保存 token がなければ消すものもないため、そのまま未認証へ。
            accessTokenStore.update(accessToken: nil)
            await deviceRegistrationService.clearLocalState()
            pendingDeviceRegistrationRetryError = nil
            apnsRegistrationError = nil
            authenticationState = .unauthenticated
        } catch {
            // 保存 token があるのに refresh が拒否された場合は失効済みとして
            // ローカル credential を破棄する (server への revoke は行わない)。
            try? authRepository.clearLocalCredentials()
            accessTokenStore.update(accessToken: nil)
            await deviceRegistrationService.clearLocalState()
            pendingDeviceRegistrationRetryError = nil
            apnsRegistrationError = nil
            authenticationState = .unauthenticated
        }
    }

    private func retryPendingDeviceRegistrationIfPossible() async {
        do {
            _ = try await deviceRegistrationService.retryPendingRegistrationIfPossible()
            pendingDeviceRegistrationRetryError = nil
        } catch {
            pendingDeviceRegistrationRetryError = error
        }
    }

    func configureAPNsDeviceRegistrationBridge() {
        APNsDeviceRegistrationBridge.shared.configure(
            service: deviceRegistrationService,
            registrationErrorHandler: { [weak self] error in
                self?.apnsRegistrationError = error
            },
            deviceRegistrationRetryErrorHandler: { [weak self] error in
                self?.pendingDeviceRegistrationRetryError = error
            }
        )
    }

    func configureNotificationArticleNavigationBridge() {
        NotificationArticleNavigationBridge.shared.configure { [weak self] userInfo in
            self?.handleNotificationPayload(userInfo)
        }
    }

    func handleNotificationPayload(_ userInfo: [AnyHashable: Any]) {
        switch NotificationArticleTargetParser().resolve(userInfo: userInfo) {
        case let .target(target):
            pendingNotificationArticleTarget = target
            notificationNavigationError = nil
        case let .rejected(reason):
            pendingNotificationArticleTarget = nil
            notificationNavigationError = reason
        case .ignored:
            break
        }
    }

    func clearPendingNotificationArticleTarget() {
        pendingNotificationArticleTarget = nil
    }

    func clearNotificationNavigationError() {
        notificationNavigationError = nil
    }

    func makeSearchRepository() -> any SearchRepository {
        guard case let .authenticated(accessToken) = authenticationState else {
            return MockSearchRepository(defaultResponse: .success([]))
        }

        return searchRepositoryFactory(accessToken)
    }

    static func production(
        apiBaseURL: URL = URL(string: "http://localhost:3000")!,
        notificationFeatures: NotificationFeatureFlags = .v1Default
    ) -> AppEnvironment {
        let accessTokenStore = AppAccessTokenStore()
        let authAPIClient = APIClient(baseURL: apiBaseURL)
        let authRepository = FeedmanAuthRepository(
            apiClient: authAPIClient,
            tokenStore: KeychainTokenStore()
        )
        let deviceRegistrationStateStore = UserDefaultsDeviceRegistrationStateStore()
        let apiClient = APIClient(
            baseURL: apiBaseURL,
            accessTokenRefreshHook: {
                let credentials = try await authRepository.refreshTokens()
                accessTokenStore.update(accessToken: credentials.accessToken)
                return credentials.accessToken
            }
        )
        let keywordRepository: any KeywordRepository = notificationFeatures.keywordNotificationsEnabled
            ? APIClientKeywordRepository(apiClient: apiClient)
            : DisabledKeywordRepository()
        let deviceRegistrationRepository: any DeviceRegistrationRepository = notificationFeatures.keywordNotificationsEnabled
            ? APIClientDeviceRegistrationRepository(apiClient: apiClient)
            : UnavailableDeviceRegistrationRepository()
        return AppEnvironment(
            feedRepository: APIClientFeedRepository(
                apiClient: apiClient,
                accessTokenProvider: {
                    try accessTokenStore.currentAccessToken()
                }
            ),
            itemRepository: FeedmanItemRepository(apiClient: apiClient),
            keywordRepository: keywordRepository,
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
            accessTokenStore: accessTokenStore,
            notificationFeatures: notificationFeatures,
            deviceRegistrationRepository: deviceRegistrationRepository,
            deviceRegistrationStateStore: deviceRegistrationStateStore
        )
    }

    private convenience init(
        feedRepository: FeedRepository,
        itemRepository: any ItemRepository,
        keywordRepository: any KeywordRepository,
        authRepository: any AuthRepository,
        accountRepository: any AccountRepository,
        authBaseURL: URL,
        searchRepositoryFactory: @escaping SearchRepositoryFactory,
        authenticationState: AppAuthenticationState,
        accessTokenStore: AppAccessTokenStore,
        notificationFeatures: NotificationFeatureFlags,
        deviceRegistrationRepository: any DeviceRegistrationRepository,
        deviceRegistrationStateStore: any DeviceRegistrationStateStore
    ) {
        let deviceRegistrationService = APNsDeviceRegistrationService(
            repository: deviceRegistrationRepository,
            stateStore: deviceRegistrationStateStore,
            accessTokenProvider: {
                try accessTokenStore.currentAccessToken()
            }
        )
        self.init(
            feedRepository: feedRepository,
            itemRepository: itemRepository,
            keywordRepository: keywordRepository,
            deviceRegistrationRepository: deviceRegistrationRepository,
            authRepository: authRepository,
            accountRepository: accountRepository,
            notificationPermissionCoordinator: NotificationPermissionCoordinator(
                authorizationProvider: UserNotificationCenterAuthorizationProvider(),
                remoteNotificationRegistrar: UIApplicationRemoteNotificationRegistrar()
            ),
            deviceRegistrationService: deviceRegistrationService,
            notificationFeatures: notificationFeatures,
            authBaseURL: authBaseURL,
            searchRepositoryFactory: searchRepositoryFactory,
            authenticationState: authenticationState,
            accessTokenStore: accessTokenStore
        )
        configureAPNsDeviceRegistrationBridge()
        configureNotificationArticleNavigationBridge()
    }

    static let preview = AppEnvironment(
        feedRepository: MockFeedRepository(),
        itemRepository: MockItemRepository(),
        keywordRepository: MockKeywordRepository(),
        authRepository: UnavailableAuthRepository(),
        accountRepository: UnavailableAccountRepository(),
        notificationPermissionCoordinator: NotificationPermissionCoordinator(
            authorizationProvider: UnavailableNotificationAuthorizationProvider(),
            remoteNotificationRegistrar: UnavailableRemoteNotificationRegistrar()
        ),
        deviceRegistrationService: APNsDeviceRegistrationService(
            repository: UnavailableDeviceRegistrationRepository(),
            stateStore: InMemoryDeviceRegistrationStateStore(),
            accessTokenProvider: {
                "preview-access-token"
            }
        ),
        authBaseURL: URL(string: "https://example.com")!,
        searchRepositoryFactory: { _ in MockSearchRepository() },
        authenticationState: .authenticated(accessToken: "preview-access-token")
    )
}

struct AppLogoutResult {
    let deviceUnregisterResult: Result<DeviceUnregisterOutcome, Error>
    let authRevokeError: Error?
}

final class InMemoryDeviceRegistrationStateStore: DeviceRegistrationStateStore {
    private var state: DeviceRegistrationState?

    init(state: DeviceRegistrationState? = nil) {
        self.state = state
    }

    func load() -> DeviceRegistrationState? {
        state
    }

    func save(_ state: DeviceRegistrationState) {
        self.state = state
    }

    func clear() {
        state = nil
    }
}

struct UnavailableNotificationAuthorizationProvider: NotificationAuthorizationProviding {
    func currentStatus() async throws -> NotificationPermissionStatus {
        .denied
    }

    func requestAuthorization() async throws -> NotificationPermissionStatus {
        .denied
    }
}

@MainActor
final class UnavailableRemoteNotificationRegistrar: RemoteNotificationRegistering {
    func registerForRemoteNotifications() {}
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
