import Foundation
import UIKit
import UserNotifications

struct APNsDeviceTokenFormatter {
    func string(from deviceToken: Data) -> String {
        deviceToken.map { String(format: "%02x", $0) }.joined()
    }
}

enum APNsDeviceRegistrationResult: Equatable {
    case registered(deviceID: String)
    case deferredUntilAuthenticated
    case alreadyRegistered(deviceID: String)
    case alreadyInFlight
    case skippedFeatureDisabled
}

enum DeviceUnregisterOutcome: Equatable {
    case skippedNoKnownDevice
    case skippedNoAuthenticatedSession(deviceID: String)
    case skippedFeatureDisabled(deviceID: String?)
    case unregistered(deviceID: String)
}

enum APNsDeviceRegistrationError: Error, Equatable {
    case remoteNotificationRegistrationFailed
}

actor APNsDeviceRegistrationService {
    typealias AccessTokenProvider = @Sendable () async throws -> String

    private let repository: any DeviceRegistrationRepository
    private let stateStore: any DeviceRegistrationStateStore
    private let featureFlags: NotificationFeatureFlags
    private let tokenFormatter: APNsDeviceTokenFormatter
    private let accessTokenProvider: AccessTokenProvider

    private var pendingPushToken: String?
    private var inFlightPushToken: String?
    private var registeredPushToken: String?

    init(
        repository: any DeviceRegistrationRepository,
        stateStore: any DeviceRegistrationStateStore,
        featureFlags: NotificationFeatureFlags = .nextPhaseEnabled,
        tokenFormatter: APNsDeviceTokenFormatter = APNsDeviceTokenFormatter(),
        accessTokenProvider: @escaping AccessTokenProvider
    ) {
        self.repository = repository
        self.stateStore = stateStore
        self.featureFlags = featureFlags
        self.tokenFormatter = tokenFormatter
        self.accessTokenProvider = accessTokenProvider
    }

    func registerDeviceToken(_ deviceToken: Data) async throws -> APNsDeviceRegistrationResult {
        try await registerPushToken(tokenFormatter.string(from: deviceToken))
    }

    func retryPendingRegistrationIfPossible() async throws -> APNsDeviceRegistrationResult? {
        guard featureFlags.keywordNotificationsEnabled else {
            clearLocalState()
            return nil
        }

        guard let pendingPushToken else {
            return nil
        }
        return try await registerPushToken(pendingPushToken)
    }

    func unregisterKnownDeviceForLogout(accessToken: String?) async -> Result<DeviceUnregisterOutcome, Error> {
        guard featureFlags.keywordNotificationsEnabled else {
            let deviceID = stateStore.load()?.deviceID
            clearLocalState()
            return .success(.skippedFeatureDisabled(deviceID: deviceID))
        }

        guard let deviceID = stateStore.load()?.deviceID else {
            clearLocalState()
            return .success(.skippedNoKnownDevice)
        }

        guard let accessToken, !accessToken.isEmpty else {
            clearLocalState()
            return .success(.skippedNoAuthenticatedSession(deviceID: deviceID))
        }

        do {
            try await repository.unregisterDevice(id: deviceID, accessToken: accessToken)
            clearLocalState()
            return .success(.unregistered(deviceID: deviceID))
        } catch {
            clearLocalState()
            return .failure(error)
        }
    }

    func clearLocalState() {
        pendingPushToken = nil
        inFlightPushToken = nil
        registeredPushToken = nil
        stateStore.clear()
    }

    private func registerPushToken(_ pushToken: String) async throws -> APNsDeviceRegistrationResult {
        guard featureFlags.keywordNotificationsEnabled else {
            clearLocalState()
            return .skippedFeatureDisabled
        }

        if inFlightPushToken == pushToken {
            return .alreadyInFlight
        }

        if registeredPushToken == pushToken,
           let deviceID = stateStore.load()?.deviceID {
            return .alreadyRegistered(deviceID: deviceID)
        }

        let accessToken: String
        do {
            accessToken = try await accessTokenProvider()
        } catch AppEnvironmentError.missingAccessToken {
            pendingPushToken = pushToken
            return .deferredUntilAuthenticated
        }

        inFlightPushToken = pushToken
        do {
            let response = try await repository.registerDevice(
                pushToken: pushToken,
                accessToken: accessToken
            )
            let state = DeviceRegistrationState(deviceID: response.id)
            stateStore.save(state)
            pendingPushToken = nil
            registeredPushToken = pushToken
            inFlightPushToken = nil
            return .registered(deviceID: response.id)
        } catch {
            pendingPushToken = pushToken
            inFlightPushToken = nil
            throw error
        }
    }
}

@MainActor
final class APNsDeviceRegistrationBridge {
    static let shared = APNsDeviceRegistrationBridge()

    private var service: APNsDeviceRegistrationService?
    private var registrationErrorHandler: (@MainActor (APNsDeviceRegistrationError?) -> Void)?
    private var deviceRegistrationRetryErrorHandler: (@MainActor (Error?) -> Void)?
    private(set) var lastRegistrationFailure: APNsDeviceRegistrationError?

    private init() {}

    func configure(
        service: APNsDeviceRegistrationService,
        registrationErrorHandler: (@MainActor (APNsDeviceRegistrationError?) -> Void)? = nil,
        deviceRegistrationRetryErrorHandler: (@MainActor (Error?) -> Void)? = nil
    ) {
        self.service = service
        self.registrationErrorHandler = registrationErrorHandler
        self.deviceRegistrationRetryErrorHandler = deviceRegistrationRetryErrorHandler
    }

    func clearRegistrationFailure() {
        lastRegistrationFailure = nil
        registrationErrorHandler?(nil)
    }

    func clearDeviceRegistrationRetryFailure() {
        deviceRegistrationRetryErrorHandler?(nil)
    }

    func handleDeviceToken(_ deviceToken: Data) {
        clearRegistrationFailure()
        clearDeviceRegistrationRetryFailure()

        guard let service else {
            return
        }

        Task {
            do {
                _ = try await service.registerDeviceToken(deviceToken)
                await MainActor.run {
                    self.clearRegistrationFailure()
                    self.clearDeviceRegistrationRetryFailure()
                }
            } catch {
                await MainActor.run {
                    self.clearRegistrationFailure()
                    self.deviceRegistrationRetryErrorHandler?(error)
                }
            }
        }
    }

    func handleRegistrationFailure(_: Error) {
        let registrationError = APNsDeviceRegistrationError.remoteNotificationRegistrationFailed
        lastRegistrationFailure = registrationError
        registrationErrorHandler?(registrationError)
    }
}

final class FeedmanAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Task { @MainActor in
            APNsDeviceRegistrationBridge.shared.handleDeviceToken(deviceToken)
        }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        Task { @MainActor in
            APNsDeviceRegistrationBridge.shared.handleRegistrationFailure(error)
        }
    }
}

extension FeedmanAppDelegate: UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        await MainActor.run {
            NotificationArticleNavigationBridge.shared.handle(
                userInfo: response.notification.request.content.userInfo
            )
        }
    }
}
