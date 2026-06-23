import XCTest
@testable import Feedman

@MainActor
final class NotificationPermissionCoordinatorTests: XCTestCase {
    func testNotDeterminedPermissionRequestsAuthorizationAndRegistersWhenGranted() async throws {
        let authorizationProvider = RecordingNotificationAuthorizationProvider(
            currentStatusResult: .success(.notDetermined),
            requestStatusResult: .success(.authorized)
        )
        let registrar = RecordingRemoteNotificationRegistrar()
        let coordinator = NotificationPermissionCoordinator(
            authorizationProvider: authorizationProvider,
            remoteNotificationRegistrar: registrar
        )

        let status = try await coordinator.requestPermissionAndRegisterIfAuthorized()

        XCTAssertEqual(status, .authorized)
        XCTAssertEqual(authorizationProvider.currentStatusCallCount, 1)
        XCTAssertEqual(authorizationProvider.requestAuthorizationCallCount, 1)
        XCTAssertEqual(registrar.registerCallCount, 1)
    }

    func testDeniedPermissionDoesNotRequestAgainOrRegisterRemoteNotifications() async throws {
        let authorizationProvider = RecordingNotificationAuthorizationProvider(
            currentStatusResult: .success(.denied),
            requestStatusResult: .success(.authorized)
        )
        let registrar = RecordingRemoteNotificationRegistrar()
        let coordinator = NotificationPermissionCoordinator(
            authorizationProvider: authorizationProvider,
            remoteNotificationRegistrar: registrar
        )

        let status = try await coordinator.requestPermissionAndRegisterIfAuthorized()

        XCTAssertEqual(status, .denied)
        XCTAssertEqual(authorizationProvider.currentStatusCallCount, 1)
        XCTAssertEqual(authorizationProvider.requestAuthorizationCallCount, 0)
        XCTAssertEqual(registrar.registerCallCount, 0)
    }

    func testExistingAuthorizedPermissionRegistersWithoutPromptingAgain() async throws {
        let authorizationProvider = RecordingNotificationAuthorizationProvider(
            currentStatusResult: .success(.provisional),
            requestStatusResult: .success(.denied)
        )
        let registrar = RecordingRemoteNotificationRegistrar()
        let coordinator = NotificationPermissionCoordinator(
            authorizationProvider: authorizationProvider,
            remoteNotificationRegistrar: registrar
        )

        let status = try await coordinator.requestPermissionAndRegisterIfAuthorized()

        XCTAssertEqual(status, .provisional)
        XCTAssertEqual(authorizationProvider.requestAuthorizationCallCount, 0)
        XCTAssertEqual(registrar.registerCallCount, 1)
    }

    func testDisabledFeatureDoesNotRegisterRemoteNotificationsWhenAuthorized() async throws {
        let authorizationProvider = RecordingNotificationAuthorizationProvider(
            currentStatusResult: .success(.authorized),
            requestStatusResult: .success(.denied)
        )
        let registrar = RecordingRemoteNotificationRegistrar()
        let coordinator = NotificationPermissionCoordinator(
            authorizationProvider: authorizationProvider,
            remoteNotificationRegistrar: registrar,
            notificationFeatures: .v1Default
        )

        let status = try await coordinator.requestPermissionAndRegisterIfAuthorized()

        XCTAssertEqual(status, .authorized)
        XCTAssertEqual(authorizationProvider.currentStatusCallCount, 1)
        XCTAssertEqual(authorizationProvider.requestAuthorizationCallCount, 0)
        XCTAssertEqual(registrar.registerCallCount, 0)
    }

    func testPermissionRequestFailureSurfacesRetryableErrorWithoutRemoteRegistration() async {
        let authorizationProvider = RecordingNotificationAuthorizationProvider(
            currentStatusResult: .success(.notDetermined),
            requestStatusResult: .failure(NotificationPermissionError.requestFailed)
        )
        let registrar = RecordingRemoteNotificationRegistrar()
        let coordinator = NotificationPermissionCoordinator(
            authorizationProvider: authorizationProvider,
            remoteNotificationRegistrar: registrar
        )

        do {
            _ = try await coordinator.requestPermissionAndRegisterIfAuthorized()
            XCTFail("Expected request failure")
        } catch NotificationPermissionError.requestFailed {
            XCTAssertEqual(registrar.registerCallCount, 0)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}

private final class RecordingNotificationAuthorizationProvider: NotificationAuthorizationProviding {
    private let currentStatusResult: Result<NotificationPermissionStatus, Error>
    private let requestStatusResult: Result<NotificationPermissionStatus, Error>
    private(set) var currentStatusCallCount = 0
    private(set) var requestAuthorizationCallCount = 0

    init(
        currentStatusResult: Result<NotificationPermissionStatus, Error>,
        requestStatusResult: Result<NotificationPermissionStatus, Error>
    ) {
        self.currentStatusResult = currentStatusResult
        self.requestStatusResult = requestStatusResult
    }

    func currentStatus() async throws -> NotificationPermissionStatus {
        currentStatusCallCount += 1
        return try currentStatusResult.get()
    }

    func requestAuthorization() async throws -> NotificationPermissionStatus {
        requestAuthorizationCallCount += 1
        return try requestStatusResult.get()
    }
}

@MainActor
private final class RecordingRemoteNotificationRegistrar: RemoteNotificationRegistering {
    private(set) var registerCallCount = 0

    func registerForRemoteNotifications() {
        registerCallCount += 1
    }
}
