import XCTest
@testable import Feedman

@MainActor
final class AppEnvironmentSessionRestoreTests: XCTestCase {
    private func makeEnvironment(
        repository: SessionRestoreAuthRepositoryMock,
        state: AppAuthenticationState = .restoring,
        deviceRegistrationService: APNsDeviceRegistrationService? = nil
    ) -> AppEnvironment {
        AppEnvironment(
            feedRepository: MockFeedRepository(),
            authRepository: repository,
            accountRepository: UnavailableAccountRepository(),
            deviceRegistrationService: deviceRegistrationService,
            authBaseURL: URL(string: "https://api.example.com")!,
            authenticationState: state
        )
    }

    func testRestoreWithStoredTokenSucceedsAndShowsAuthenticatedShell() async {
        let repository = SessionRestoreAuthRepositoryMock(
            refreshResult: .success(
                TokenCredentials(
                    accessToken: "restored-access",
                    refreshToken: "rotated-refresh",
                    tokenType: "Bearer",
                    expiresIn: 900
                )
            )
        )
        let environment = makeEnvironment(repository: repository)

        await environment.restoreSessionAtLaunch()

        XCTAssertEqual(environment.authenticationState, .authenticated(accessToken: "restored-access"))
        XCTAssertEqual(repository.refreshCallCount, 1)
        XCTAssertEqual(repository.clearLocalCallCount, 0)
    }

    func testRestorePublishesPendingDeviceRegistrationRetryFailureAndKeepsTokenForRetry() async throws {
        let repository = SessionRestoreAuthRepositoryMock(
            refreshResult: .success(
                TokenCredentials(
                    accessToken: "restored-access",
                    refreshToken: "rotated-refresh",
                    tokenType: "Bearer",
                    expiresIn: 900
                )
            )
        )
        let accessTokenBox = SessionRestoreAccessTokenBox(
            result: .failure(AppEnvironmentError.missingAccessToken)
        )
        let deviceRepository = SessionRestoreDeviceRegistrationRepository(
            registerResults: [
                .failure(SessionRestoreTestError.deviceRegistrationRejected),
                .success(DeviceRegistrationResponse(id: "device-1"))
            ]
        )
        let deviceRegistrationService = APNsDeviceRegistrationService(
            repository: deviceRepository,
            stateStore: InMemoryDeviceRegistrationStateStore(),
            accessTokenProvider: {
                try await accessTokenBox.currentAccessToken()
            }
        )
        let environment = makeEnvironment(
            repository: repository,
            deviceRegistrationService: deviceRegistrationService
        )
        let deferredResult = try await deviceRegistrationService.registerDeviceToken(Data([0xAB]))
        await accessTokenBox.update(result: .success("restored-access"))

        await environment.restoreSessionAtLaunch()

        XCTAssertEqual(deferredResult, .deferredUntilAuthenticated)
        XCTAssertEqual(environment.authenticationState, .authenticated(accessToken: "restored-access"))
        XCTAssertEqual(
            environment.pendingDeviceRegistrationRetryError as? SessionRestoreTestError,
            .deviceRegistrationRejected
        )

        let retryResult = try await deviceRegistrationService.retryPendingRegistrationIfPossible()
        XCTAssertEqual(retryResult, .registered(deviceID: "device-1"))
        let requests = await deviceRepository.registerRequests
        XCTAssertEqual(
            requests,
            [
                DeviceRegisterRequest(pushToken: "ab", accessToken: "restored-access"),
                DeviceRegisterRequest(pushToken: "ab", accessToken: "restored-access")
            ]
        )
    }

    func testDisabledRestoreRetryDoesNotPostDeviceRegistration() async throws {
        let repository = SessionRestoreAuthRepositoryMock(
            refreshResult: .success(
                TokenCredentials(
                    accessToken: "restored-access",
                    refreshToken: "rotated-refresh",
                    tokenType: "Bearer",
                    expiresIn: 900
                )
            )
        )
        let accessTokenBox = SessionRestoreAccessTokenBox(
            result: .success("restored-access")
        )
        let deviceRepository = SessionRestoreDeviceRegistrationRepository()
        let deviceStateStore = InMemoryDeviceRegistrationStateStore(
            state: DeviceRegistrationState(deviceID: "stale-device")
        )
        let deviceRegistrationService = APNsDeviceRegistrationService(
            repository: deviceRepository,
            stateStore: deviceStateStore,
            featureFlags: .v1Default,
            accessTokenProvider: {
                try await accessTokenBox.currentAccessToken()
            }
        )
        let environment = makeEnvironment(
            repository: repository,
            deviceRegistrationService: deviceRegistrationService
        )

        let tokenResult = try await deviceRegistrationService.registerDeviceToken(Data([0xAB]))
        await environment.restoreSessionAtLaunch()

        XCTAssertEqual(tokenResult, .skippedFeatureDisabled)
        XCTAssertEqual(environment.authenticationState, .authenticated(accessToken: "restored-access"))
        XCTAssertNil(environment.pendingDeviceRegistrationRetryError)
        let requests = await deviceRepository.registerRequests
        XCTAssertEqual(requests, [])
        let callCount = await accessTokenBox.currentCallCount()
        XCTAssertEqual(callCount, 0)
        XCTAssertNil(deviceStateStore.load())
    }

    func testRestoreWithoutStoredTokenShowsLoginWithoutClearing() async {
        let repository = SessionRestoreAuthRepositoryMock(
            refreshResult: .failure(AuthRepositoryError.missingRefreshToken)
        )
        let environment = makeEnvironment(repository: repository)

        await environment.restoreSessionAtLaunch()

        XCTAssertEqual(environment.authenticationState, .unauthenticated)
        XCTAssertEqual(repository.refreshCallCount, 1)
        XCTAssertEqual(repository.clearLocalCallCount, 0)
    }

    func testRestoreWithRejectedRefreshClearsCredentialsAndShowsLogin() async {
        let repository = SessionRestoreAuthRepositoryMock(
            refreshResult: .failure(SessionRestoreTestError.refreshRejected)
        )
        let environment = makeEnvironment(repository: repository)
        environment.configureAPNsDeviceRegistrationBridge()
        defer {
            resetAPNsDeviceRegistrationBridge()
        }
        APNsDeviceRegistrationBridge.shared.handleRegistrationFailure(
            SessionRestoreTestError.apnsRegistrationRejected
        )

        await environment.restoreSessionAtLaunch()

        XCTAssertEqual(environment.authenticationState, .unauthenticated)
        XCTAssertNil(environment.apnsRegistrationError)
        XCTAssertEqual(repository.refreshCallCount, 1)
        XCTAssertEqual(repository.clearLocalCallCount, 1)
    }

    func testRestoreIsNoOpWhenStateIsNotRestoring() async {
        let repository = SessionRestoreAuthRepositoryMock(
            refreshResult: .failure(SessionRestoreTestError.refreshRejected)
        )
        let environment = makeEnvironment(
            repository: repository,
            state: .authenticated(accessToken: "existing-access")
        )

        await environment.restoreSessionAtLaunch()

        XCTAssertEqual(environment.authenticationState, .authenticated(accessToken: "existing-access"))
        XCTAssertEqual(repository.refreshCallCount, 0)
    }

    func testCompleteLoginStillTransitionsToAuthenticated() async {
        let repository = SessionRestoreAuthRepositoryMock(
            refreshResult: .failure(AuthRepositoryError.missingRefreshToken)
        )
        let environment = makeEnvironment(repository: repository, state: .unauthenticated)

        environment.completeLogin(
            with: TokenCredentials(
                accessToken: "login-access",
                refreshToken: "login-refresh",
                tokenType: "Bearer",
                expiresIn: 900
            )
        )

        XCTAssertEqual(environment.authenticationState, .authenticated(accessToken: "login-access"))
    }

    func testPreviewEnvironmentUsesMockKeywordRepository() {
        XCTAssertTrue(AppEnvironment.preview.keywordRepository is MockKeywordRepository)
    }

    func testProductionEnvironmentUsesV1DefaultDisabledNotificationDependencies() {
        let environment = AppEnvironment.production(apiBaseURL: URL(string: "https://api.example.com")!)

        XCTAssertEqual(environment.notificationFeatures, .v1Default)
        XCTAssertFalse(environment.notificationFeatures.keywordNotificationsEnabled)
        XCTAssertTrue(environment.keywordRepository is DisabledKeywordRepository)
        XCTAssertFalse(environment.deviceRegistrationRepository is APIClientDeviceRegistrationRepository)
    }

    func testProductionEnvironmentCanEnableNotificationDependenciesExplicitly() {
        let environment = AppEnvironment.production(
            apiBaseURL: URL(string: "https://api.example.com")!,
            notificationFeatures: .nextPhaseEnabled
        )

        XCTAssertEqual(environment.notificationFeatures, .nextPhaseEnabled)
        XCTAssertTrue(environment.keywordRepository is APIClientKeywordRepository)
        XCTAssertTrue(environment.deviceRegistrationRepository is APIClientDeviceRegistrationRepository)
    }

    func testProductionEnvironmentUsesConfiguredOriginForNativeLoginBase() {
        let environment = AppEnvironment.production(apiBaseURL: URL(string: "https://api.example.com")!)

        XCTAssertEqual(environment.authBaseURL, URL(string: "https://api.example.com")!)
    }

    func testConfiguredProductionAPIBaseURLUsesEnvironmentOrigin() throws {
        let url = try AppEnvironment.resolveProductionAPIBaseURL(
            infoDictionary: [:],
            environment: ["FEEDMAN_API_BASE_URL": "https://api.example.com"]
        )

        XCTAssertEqual(url, URL(string: "https://api.example.com")!)
    }

    func testConfiguredProductionAPIBaseURLRejectsMissingReleaseEquivalentOrigin() {
        XCTAssertThrowsError(try AppEnvironment.resolveProductionAPIBaseURL(
            infoDictionary: [:],
            environment: [:]
        )) { error in
            XCTAssertEqual(error as? AppEnvironmentConfigurationError, .missingAPIBaseURL)
        }
    }

    func testConfiguredProductionAPIBaseURLDoesNotUseLocalhostAsImplicitReleaseDefault() {
        XCTAssertThrowsError(try AppEnvironment.resolveProductionAPIBaseURL(
            infoDictionary: ["FeedmanAPIBaseURL": "http://localhost:3000"],
            environment: [:]
        )) { error in
            XCTAssertEqual(error as? AppEnvironmentConfigurationError, .localhostAPIBaseURLNotAllowed)
        }
    }

    func testConfiguredProductionAPIBaseURLRejectsInvalidOrigin() {
        let configuredOrigin = "ftp://api.example.com"

        XCTAssertThrowsError(try AppEnvironment.resolveProductionAPIBaseURL(
            infoDictionary: ["FeedmanAPIBaseURL": configuredOrigin],
            environment: [:]
        )) { error in
            XCTAssertEqual(error as? AppEnvironmentConfigurationError, .invalidAPIBaseURL(configuredOrigin))
        }
    }

    func testCompleteLoginPublishesPendingDeviceRegistrationRetryFailureAndKeepsTokenForRetry() async throws {
        let repository = SessionRestoreAuthRepositoryMock(
            refreshResult: .failure(AuthRepositoryError.missingRefreshToken)
        )
        let accessTokenBox = SessionRestoreAccessTokenBox(
            result: .failure(AppEnvironmentError.missingAccessToken)
        )
        let deviceRepository = SessionRestoreDeviceRegistrationRepository(
            registerResults: [
                .failure(SessionRestoreTestError.deviceRegistrationRejected),
                .success(DeviceRegistrationResponse(id: "device-1"))
            ]
        )
        let deviceRegistrationService = APNsDeviceRegistrationService(
            repository: deviceRepository,
            stateStore: InMemoryDeviceRegistrationStateStore(),
            accessTokenProvider: {
                try await accessTokenBox.currentAccessToken()
            }
        )
        let environment = makeEnvironment(
            repository: repository,
            state: .unauthenticated,
            deviceRegistrationService: deviceRegistrationService
        )
        let deferredResult = try await deviceRegistrationService.registerDeviceToken(Data([0xAB]))
        await accessTokenBox.update(result: .success("login-access"))

        environment.completeLogin(
            with: TokenCredentials(
                accessToken: "login-access",
                refreshToken: "login-refresh",
                tokenType: "Bearer",
                expiresIn: 900
            )
        )
        let retryError = await waitForPendingDeviceRegistrationRetryError(environment)

        XCTAssertEqual(deferredResult, .deferredUntilAuthenticated)
        XCTAssertEqual(environment.authenticationState, .authenticated(accessToken: "login-access"))
        XCTAssertEqual(retryError as? SessionRestoreTestError, .deviceRegistrationRejected)

        let retryResult = try await deviceRegistrationService.retryPendingRegistrationIfPossible()
        XCTAssertEqual(retryResult, .registered(deviceID: "device-1"))
        let requests = await deviceRepository.registerRequests
        XCTAssertEqual(
            requests,
            [
                DeviceRegisterRequest(pushToken: "ab", accessToken: "login-access"),
                DeviceRegisterRequest(pushToken: "ab", accessToken: "login-access")
            ]
        )
    }

    func testDisabledCompleteLoginRetryDoesNotPostDeviceRegistration() async throws {
        let repository = SessionRestoreAuthRepositoryMock(
            refreshResult: .failure(AuthRepositoryError.missingRefreshToken)
        )
        let accessTokenBox = SessionRestoreAccessTokenBox(
            result: .success("login-access")
        )
        let deviceRepository = SessionRestoreDeviceRegistrationRepository()
        let deviceRegistrationService = APNsDeviceRegistrationService(
            repository: deviceRepository,
            stateStore: InMemoryDeviceRegistrationStateStore(),
            featureFlags: .v1Default,
            accessTokenProvider: {
                try await accessTokenBox.currentAccessToken()
            }
        )
        let environment = makeEnvironment(
            repository: repository,
            state: .unauthenticated,
            deviceRegistrationService: deviceRegistrationService
        )

        let tokenResult = try await deviceRegistrationService.registerDeviceToken(Data([0xAB]))
        environment.completeLogin(
            with: TokenCredentials(
                accessToken: "login-access",
                refreshToken: "login-refresh",
                tokenType: "Bearer",
                expiresIn: 900
            )
        )

        XCTAssertEqual(tokenResult, .skippedFeatureDisabled)
        XCTAssertEqual(environment.authenticationState, .authenticated(accessToken: "login-access"))
        XCTAssertNil(environment.pendingDeviceRegistrationRetryError)
        let requests = await deviceRepository.registerRequests
        XCTAssertEqual(requests, [])
        let callCount = await accessTokenBox.currentCallCount()
        XCTAssertEqual(callCount, 0)
    }

    func testAPNsRegistrationFailurePublishesDomainErrorWithoutPostingDeviceRegistration() async {
        let repository = SessionRestoreAuthRepositoryMock(
            refreshResult: .failure(AuthRepositoryError.missingRefreshToken)
        )
        let deviceRepository = SessionRestoreDeviceRegistrationRepository()
        let deviceRegistrationService = APNsDeviceRegistrationService(
            repository: deviceRepository,
            stateStore: InMemoryDeviceRegistrationStateStore(),
            accessTokenProvider: {
                "access-1"
            }
        )
        let environment = makeEnvironment(
            repository: repository,
            state: .authenticated(accessToken: "access-1"),
            deviceRegistrationService: deviceRegistrationService
        )
        environment.configureAPNsDeviceRegistrationBridge()
        defer {
            resetAPNsDeviceRegistrationBridge()
        }

        APNsDeviceRegistrationBridge.shared.handleRegistrationFailure(
            SessionRestoreTestError.apnsRegistrationRejected
        )

        XCTAssertEqual(environment.apnsRegistrationError, .remoteNotificationRegistrationFailed)
        XCTAssertEqual(
            APNsDeviceRegistrationBridge.shared.lastRegistrationFailure,
            .remoteNotificationRegistrationFailed
        )
        let requests = await deviceRepository.registerRequests
        XCTAssertEqual(requests, [])
    }

    func testDisabledAPNsDeviceTokenCallbackDoesNotPostDeviceRegistration() async {
        let repository = SessionRestoreAuthRepositoryMock(
            refreshResult: .failure(AuthRepositoryError.missingRefreshToken)
        )
        let accessTokenBox = SessionRestoreAccessTokenBox(
            result: .success("access-1")
        )
        let deviceRepository = SessionRestoreDeviceRegistrationRepository()
        let deviceStateStore = InMemoryDeviceRegistrationStateStore(
            state: DeviceRegistrationState(deviceID: "stale-device")
        )
        let deviceRegistrationService = APNsDeviceRegistrationService(
            repository: deviceRepository,
            stateStore: deviceStateStore,
            featureFlags: .v1Default,
            accessTokenProvider: {
                try await accessTokenBox.currentAccessToken()
            }
        )
        let environment = makeEnvironment(
            repository: repository,
            state: .authenticated(accessToken: "access-1"),
            deviceRegistrationService: deviceRegistrationService
        )
        environment.configureAPNsDeviceRegistrationBridge()
        defer {
            resetAPNsDeviceRegistrationBridge()
        }

        APNsDeviceRegistrationBridge.shared.handleDeviceToken(Data([0xCA, 0xFE]))
        await waitForDeviceRegistrationStateClear(deviceStateStore)

        XCTAssertNil(environment.pendingDeviceRegistrationRetryError)
        XCTAssertNil(environment.apnsRegistrationError)
        let requests = await deviceRepository.registerRequests
        XCTAssertEqual(requests, [])
        let callCount = await accessTokenBox.currentCallCount()
        XCTAssertEqual(callCount, 0)
        XCTAssertNil(deviceStateStore.load())
    }

    func testAPNsDeviceTokenSuccessClearsPublishedRegistrationFailure() async {
        let repository = SessionRestoreAuthRepositoryMock(
            refreshResult: .failure(AuthRepositoryError.missingRefreshToken)
        )
        let deviceRepository = SessionRestoreDeviceRegistrationRepository(
            registerResults: [.success(DeviceRegistrationResponse(id: "device-1"))]
        )
        let deviceRegistrationService = APNsDeviceRegistrationService(
            repository: deviceRepository,
            stateStore: InMemoryDeviceRegistrationStateStore(),
            accessTokenProvider: {
                "access-1"
            }
        )
        let environment = makeEnvironment(
            repository: repository,
            state: .authenticated(accessToken: "access-1"),
            deviceRegistrationService: deviceRegistrationService
        )
        environment.configureAPNsDeviceRegistrationBridge()
        defer {
            resetAPNsDeviceRegistrationBridge()
        }

        APNsDeviceRegistrationBridge.shared.handleRegistrationFailure(
            SessionRestoreTestError.apnsRegistrationRejected
        )
        APNsDeviceRegistrationBridge.shared.handleDeviceToken(Data([0xCA, 0xFE]))
        await waitForDeviceRegistrationRequest(deviceRepository)

        XCTAssertNil(environment.apnsRegistrationError)
        XCTAssertNil(APNsDeviceRegistrationBridge.shared.lastRegistrationFailure)
        let requests = await deviceRepository.registerRequests
        XCTAssertEqual(
            requests,
            [DeviceRegisterRequest(pushToken: "cafe", accessToken: "access-1")]
        )
    }

    func testAPNsDeviceTokenRegistrationFailurePublishesRetryErrorAndKeepsTokenForRetry() async {
        let repository = SessionRestoreAuthRepositoryMock(
            refreshResult: .failure(AuthRepositoryError.missingRefreshToken)
        )
        let deviceStateStore = InMemoryDeviceRegistrationStateStore()
        let deviceRepository = SessionRestoreDeviceRegistrationRepository(
            registerResults: [
                .failure(SessionRestoreTestError.deviceRegistrationRejected),
                .success(DeviceRegistrationResponse(id: "device-1"))
            ]
        )
        let deviceRegistrationService = APNsDeviceRegistrationService(
            repository: deviceRepository,
            stateStore: deviceStateStore,
            accessTokenProvider: {
                "access-1"
            }
        )
        let environment = makeEnvironment(
            repository: repository,
            state: .authenticated(accessToken: "access-1"),
            deviceRegistrationService: deviceRegistrationService
        )
        environment.configureAPNsDeviceRegistrationBridge()
        defer {
            resetAPNsDeviceRegistrationBridge()
        }

        APNsDeviceRegistrationBridge.shared.handleDeviceToken(Data([0xAB]))
        let retryError = await waitForPendingDeviceRegistrationRetryError(environment)

        XCTAssertEqual(retryError as? SessionRestoreTestError, .deviceRegistrationRejected)
        XCTAssertNil(environment.apnsRegistrationError)
        XCTAssertNil(APNsDeviceRegistrationBridge.shared.lastRegistrationFailure)
        XCTAssertNil(deviceStateStore.load())
        let failedRequests = await deviceRepository.registerRequests
        XCTAssertEqual(
            failedRequests,
            [DeviceRegisterRequest(pushToken: "ab", accessToken: "access-1")]
        )

        APNsDeviceRegistrationBridge.shared.handleDeviceToken(Data([0xAB]))
        await waitForDeviceRegistrationRequestCount(deviceRepository, count: 2)
        await waitForPendingDeviceRegistrationRetryErrorClear(environment)

        XCTAssertNil(environment.pendingDeviceRegistrationRetryError)
        XCTAssertEqual(deviceStateStore.load(), DeviceRegistrationState(deviceID: "device-1"))
        let retriedRequests = await deviceRepository.registerRequests
        XCTAssertEqual(
            retriedRequests,
            [
                DeviceRegisterRequest(pushToken: "ab", accessToken: "access-1"),
                DeviceRegisterRequest(pushToken: "ab", accessToken: "access-1")
            ]
        )
    }

    func testAccountDeletionSessionClearClearsCredentialsAndShowsLogin() async {
        let repository = SessionRestoreAuthRepositoryMock(
            refreshResult: .failure(AuthRepositoryError.missingRefreshToken)
        )
        let deviceStateStore = InMemoryDeviceRegistrationStateStore(
            state: DeviceRegistrationState(deviceID: "device-1")
        )
        let deviceRegistrationService = APNsDeviceRegistrationService(
            repository: UnavailableDeviceRegistrationRepository(),
            stateStore: deviceStateStore,
            accessTokenProvider: {
                throw AppEnvironmentError.missingAccessToken
            }
        )
        let environment = makeEnvironment(
            repository: repository,
            state: .authenticated(accessToken: "existing-access"),
            deviceRegistrationService: deviceRegistrationService
        )
        environment.configureAPNsDeviceRegistrationBridge()
        defer {
            resetAPNsDeviceRegistrationBridge()
        }
        APNsDeviceRegistrationBridge.shared.handleRegistrationFailure(
            SessionRestoreTestError.apnsRegistrationRejected
        )

        await environment.clearLocalAuthenticationAfterAccountDeletion()

        XCTAssertEqual(environment.authenticationState, .unauthenticated)
        XCTAssertNil(environment.apnsRegistrationError)
        XCTAssertNil(environment.currentAccessToken)
        XCTAssertNil(deviceStateStore.load())
        XCTAssertEqual(repository.clearLocalCallCount, 1)
        XCTAssertEqual(repository.revokeCallCount, 0)
    }
}

private struct DeviceRegisterRequest: Equatable {
    let pushToken: String
    let accessToken: String
}

private enum SessionRestoreTestError: Error, Equatable {
    case refreshRejected
    case deviceRegistrationRejected
    case apnsRegistrationRejected
}

private actor SessionRestoreAccessTokenBox {
    private var result: Result<String, Error>
    private(set) var callCount = 0

    init(result: Result<String, Error>) {
        self.result = result
    }

    func update(result: Result<String, Error>) {
        self.result = result
    }

    func currentAccessToken() throws -> String {
        callCount += 1
        return try result.get()
    }

    func currentCallCount() -> Int {
        callCount
    }
}

private actor SessionRestoreDeviceRegistrationRepository: DeviceRegistrationRepository {
    private(set) var registerRequests: [DeviceRegisterRequest] = []
    private var registerResults: [Result<DeviceRegistrationResponse, Error>]

    init(registerResults: [Result<DeviceRegistrationResponse, Error>] = []) {
        self.registerResults = registerResults
    }

    func registerDevice(pushToken: String, accessToken: String) async throws -> DeviceRegistrationResponse {
        registerRequests.append(DeviceRegisterRequest(pushToken: pushToken, accessToken: accessToken))
        if registerResults.isEmpty {
            return DeviceRegistrationResponse(id: "device-1")
        }
        return try registerResults.removeFirst().get()
    }

    func unregisterDevice(id: String, accessToken: String) async throws {}
}

private final class SessionRestoreAuthRepositoryMock: AuthRepository {
    private let refreshResult: Result<TokenCredentials, Error>
    private(set) var refreshCallCount = 0
    private(set) var clearLocalCallCount = 0
    private(set) var revokeCallCount = 0

    init(refreshResult: Result<TokenCredentials, Error>) {
        self.refreshResult = refreshResult
    }

    @discardableResult
    func exchangeAuthCode(_ authCode: String, codeVerifier: String) async throws -> TokenCredentials {
        throw SessionRestoreTestError.refreshRejected
    }

    @discardableResult
    func refreshTokens() async throws -> TokenCredentials {
        refreshCallCount += 1
        return try refreshResult.get()
    }

    func revokeAndClearCredentials(accessToken: String?) async throws {
        revokeCallCount += 1
    }

    func clearLocalCredentials() throws {
        clearLocalCallCount += 1
    }
}

@MainActor
private func waitForPendingDeviceRegistrationRetryError(
    _ environment: AppEnvironment,
    file: StaticString = #filePath,
    line: UInt = #line
) async -> Error? {
    for _ in 0..<50 {
        if let error = environment.pendingDeviceRegistrationRetryError {
            return error
        }
        try? await Task.sleep(nanoseconds: 1_000_000)
    }
    XCTFail("Timed out waiting for pending device registration retry error", file: file, line: line)
    return nil
}

@MainActor
private func waitForDeviceRegistrationRequest(
    _ repository: SessionRestoreDeviceRegistrationRepository,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    await waitForDeviceRegistrationRequestCount(repository, count: 1, file: file, line: line)
}

@MainActor
private func waitForDeviceRegistrationRequestCount(
    _ repository: SessionRestoreDeviceRegistrationRepository,
    count: Int,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    for _ in 0..<50 {
        if await repository.registerRequests.count == count {
            return
        }
        try? await Task.sleep(nanoseconds: 1_000_000)
    }
    XCTFail("Timed out waiting for device registration request", file: file, line: line)
}

@MainActor
private func waitForPendingDeviceRegistrationRetryErrorClear(
    _ environment: AppEnvironment,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    for _ in 0..<50 {
        if environment.pendingDeviceRegistrationRetryError == nil {
            return
        }
        try? await Task.sleep(nanoseconds: 1_000_000)
    }
    XCTFail("Timed out waiting for pending device registration retry error clear", file: file, line: line)
}

private func waitForDeviceRegistrationStateClear(
    _ stateStore: DeviceRegistrationStateStore,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    for _ in 0..<50 {
        if stateStore.load() == nil {
            return
        }
        try? await Task.sleep(nanoseconds: 1_000_000)
    }
    XCTFail("Timed out waiting for device registration state clear", file: file, line: line)
}

@MainActor
private func resetAPNsDeviceRegistrationBridge() {
    APNsDeviceRegistrationBridge.shared.configure(
        service: APNsDeviceRegistrationService(
            repository: UnavailableDeviceRegistrationRepository(),
            stateStore: InMemoryDeviceRegistrationStateStore(),
            accessTokenProvider: {
                throw AppEnvironmentError.missingAccessToken
            }
        )
    )
    APNsDeviceRegistrationBridge.shared.clearRegistrationFailure()
    APNsDeviceRegistrationBridge.shared.clearDeviceRegistrationRetryFailure()
}
