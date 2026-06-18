import XCTest
@testable import Feedman

@MainActor
final class AppEnvironmentLogoutTests: XCTestCase {
    func testLogoutUnregistersKnownDeviceClearsStateAndShowsLogin() async {
        let authRepository = LogoutAuthRepositoryMock()
        let deviceRepository = EnvironmentDeviceRegistrationRepositoryMock()
        let stateStore = InMemoryDeviceRegistrationStateStore(
            state: DeviceRegistrationState(deviceID: "device-1")
        )
        let environment = makeEnvironment(
            authRepository: authRepository,
            deviceRepository: deviceRepository,
            stateStore: stateStore
        )
        environment.configureAPNsDeviceRegistrationBridge()
        defer {
            resetAPNsDeviceRegistrationBridge()
        }
        APNsDeviceRegistrationBridge.shared.handleRegistrationFailure(
            EnvironmentLogoutTestError.apnsRegistrationRejected
        )

        let result = await environment.logout()

        XCTAssertEqual(environment.authenticationState, .unauthenticated)
        XCTAssertNil(environment.apnsRegistrationError)
        XCTAssertNil(environment.currentAccessToken)
        XCTAssertNil(stateStore.load())
        XCTAssertEqual(
            await deviceRepository.unregisterRequests,
            [EnvironmentDeviceUnregisterRequest(deviceID: "device-1", accessToken: "access-1")]
        )
        XCTAssertEqual(authRepository.revokeAccessTokens, ["access-1"])
        XCTAssertNil(result.authRevokeError)
        XCTAssertEqual(try? result.deviceUnregisterResult.get(), .unregistered(deviceID: "device-1"))
    }

    func testLogoutWithoutKnownDeviceDoesNotCallUnregisterAndClearsStaleState() async {
        let authRepository = LogoutAuthRepositoryMock()
        let deviceRepository = EnvironmentDeviceRegistrationRepositoryMock()
        let stateStore = InMemoryDeviceRegistrationStateStore()
        let environment = makeEnvironment(
            authRepository: authRepository,
            deviceRepository: deviceRepository,
            stateStore: stateStore
        )

        let result = await environment.logout()

        XCTAssertEqual(environment.authenticationState, .unauthenticated)
        XCTAssertEqual(await deviceRepository.unregisterRequests, [])
        XCTAssertEqual(try? result.deviceUnregisterResult.get(), .skippedNoKnownDevice)
    }

    func testLogoutContinuesWhenDeviceUnregisterFailsAndExposesFailure() async {
        let authRepository = LogoutAuthRepositoryMock()
        let deviceRepository = EnvironmentDeviceRegistrationRepositoryMock(
            unregisterResult: .failure(EnvironmentLogoutTestError.unregisterRejected)
        )
        let stateStore = InMemoryDeviceRegistrationStateStore(
            state: DeviceRegistrationState(deviceID: "device-1")
        )
        let environment = makeEnvironment(
            authRepository: authRepository,
            deviceRepository: deviceRepository,
            stateStore: stateStore
        )

        let result = await environment.logout()

        XCTAssertEqual(environment.authenticationState, .unauthenticated)
        XCTAssertNil(stateStore.load())
        XCTAssertEqual(authRepository.revokeAccessTokens, ["access-1"])

        switch result.deviceUnregisterResult {
        case .success:
            XCTFail("Expected unregister failure")
        case .failure(let error):
            XCTAssertTrue(error is EnvironmentLogoutTestError)
        }
    }

    private func makeEnvironment(
        authRepository: LogoutAuthRepositoryMock,
        deviceRepository: EnvironmentDeviceRegistrationRepositoryMock,
        stateStore: InMemoryDeviceRegistrationStateStore
    ) -> AppEnvironment {
        let accessTokenStore = AppAccessTokenStore(accessToken: "access-1")
        let service = APNsDeviceRegistrationService(
            repository: deviceRepository,
            stateStore: stateStore,
            accessTokenProvider: {
                try accessTokenStore.currentAccessToken()
            }
        )
        return AppEnvironment(
            feedRepository: MockFeedRepository(),
            authRepository: authRepository,
            accountRepository: UnavailableAccountRepository(),
            deviceRegistrationService: service,
            authBaseURL: URL(string: "https://api.example.com")!,
            authenticationState: .authenticated(accessToken: "access-1"),
            accessTokenStore: accessTokenStore
        )
    }
}

private final class LogoutAuthRepositoryMock: AuthRepository {
    private(set) var revokeAccessTokens: [String?] = []
    private(set) var clearLocalCallCount = 0

    @discardableResult
    func exchangeAuthCode(_ authCode: String, codeVerifier: String) async throws -> TokenCredentials {
        throw EnvironmentLogoutTestError.authRejected
    }

    @discardableResult
    func refreshTokens() async throws -> TokenCredentials {
        throw EnvironmentLogoutTestError.authRejected
    }

    func revokeAndClearCredentials(accessToken: String?) async throws {
        revokeAccessTokens.append(accessToken)
    }

    func clearLocalCredentials() throws {
        clearLocalCallCount += 1
    }
}

private struct EnvironmentDeviceUnregisterRequest: Equatable {
    let deviceID: String
    let accessToken: String
}

private actor EnvironmentDeviceRegistrationRepositoryMock: DeviceRegistrationRepository {
    private(set) var unregisterRequests: [EnvironmentDeviceUnregisterRequest] = []
    private let unregisterResult: Result<Void, Error>

    init(unregisterResult: Result<Void, Error> = .success(())) {
        self.unregisterResult = unregisterResult
    }

    func registerDevice(pushToken: String, accessToken: String) async throws -> DeviceRegistrationResponse {
        DeviceRegistrationResponse(id: "device-1")
    }

    func unregisterDevice(id: String, accessToken: String) async throws {
        unregisterRequests.append(EnvironmentDeviceUnregisterRequest(deviceID: id, accessToken: accessToken))
        try unregisterResult.get()
    }
}

private enum EnvironmentLogoutTestError: Error {
    case authRejected
    case unregisterRejected
    case apnsRegistrationRejected
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
}
